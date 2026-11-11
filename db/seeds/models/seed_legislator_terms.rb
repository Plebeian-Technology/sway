# frozen_string_literal: true

# Writes one legislator's term rows from what the source proves.
# @lat: [[current-legislator-term#Which term a legislator is serving now#Planned automatic legislator updates#Officially supported title completion]]
class SeedLegislatorTerms
  TITLE_ALIASES = {"State Delegate" => "Delegate", "State Senator" => "Senator"}.freeze

  # @param first_sighting [Boolean] this run created the person row AND the
  #   locale already held legislators. See #stamp_observed_start!.
  def initialize(legislator, prepared, first_sighting: false, observed_on: Date.current)
    @legislator = legislator
    @prepared = prepared
    @first_sighting = first_sighting
    @observed_on = observed_on
  end

  def call
    return if official_service_entry? && !supported_prepared_service?

    seat_context = configured_seat_context
    add_missing_terms!
    if prepared.terms_from_history?
      correct_terms!
      retire_unproven_terms!
    end
    attach_configured_current_seat!(seat_context) if seat_context
    fill_missing_titles!
    clear_observed_departure!
  end

  private

  attr_reader :legislator, :prepared, :first_sighting, :observed_on

  # Makes sure a row exists for every term the source proves, PLUS the current
  # term when the source still lists this person as holding office.
  # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster evidence for observed departures]]
  def add_missing_terms!
    terms = proven_terms
    terms += [current_term_attrs] if prepared.current_member?

    terms
      .uniq { |term_attrs| term_attrs[:term_start_year] }
      .each { |term_attrs| create_term!(term_attrs) }
  end

  def current_term_attrs
    {
      term_start_year: prepared.term_start_year,
      term_end_year: prepared.term_end_year,
      title: prepared.title
    }
  end

  def configured_seat_context
    return if official_service_entry?

    rules = legislator.sway_locale.term_rules
    chambers = rules.seat_chambers
    return if chambers.empty?
    return unless prepared.current_member?
    return if rules.publishes_term_history && !prepared.terms_from_history?

    district = prepared.district
    unless district.is_a?(District) && district.sway_locale_id == legislator.sway_locale_id
      raise Seats::UnresolvedSeatError,
        "Prepared district belongs to a different locale than #{legislator.sway_locale.name}"
    end

    identity = prepared.identity
    unless identity.is_a?(LegislatorIdentity)
      raise Seats::UnresolvedSeatError,
        "Prepared identity #{identity.inspect} is invalid in #{legislator.sway_locale.name}"
    end

    office_identity =
      case rules.identified_by
      when :seat
        unless identity.source == LegislatorIdentity::SEAT_AND_NAME
          raise Seats::UnresolvedSeatError,
            "Configured seat chambers in #{legislator.sway_locale.name} require a seat-and-name identity"
        end

        extracted = LegislatorIdentity.seat_from(identity.value)
        if extracted.blank? || extracted.include?(LegislatorIdentity::SEPARATOR)
          raise Seats::UnresolvedSeatError,
            "Prepared identity #{identity} does not contain a configured office identity"
        end
        extracted
      when :person
        extracted = prepared.respond_to?(:current_office_identity) ? prepared.current_office_identity : nil
        if extracted.blank?
          raise Seats::UnresolvedSeatError,
            "Prepared person identity #{identity} does not provide a configured office identity in #{legislator.sway_locale.name}"
        end
        extracted
      else
        raise Seats::UnresolvedSeatError,
          "Unsupported identified_by #{rules.identified_by.inspect} for configured seat chambers in #{legislator.sway_locale.name}"
      end

    identifier = LegislatorIdentifier.find_by(
      sway_locale_id: legislator.sway_locale_id,
      source: identity.source,
      value: identity.value
    )
    unless identifier&.legislator_id == legislator.id
      raise Seats::UnresolvedSeatError,
        "Prepared identity #{identity} does not identify this legislator in #{legislator.sway_locale.name}"
    end

    seat_title = chambers.key?(prepared.title) ? prepared.title : TITLE_ALIASES.fetch(prepared.title, prepared.title)
    chamber = chambers[seat_title]
    if chamber.blank?
      raise Seats::UnresolvedSeatError,
        "No configured chamber for current title #{prepared.title.inspect} in #{legislator.sway_locale.name}"
    end

    {identity:, office_identity:, chamber:, district:, seat_title:}
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding#Configured office metadata for current seat-keyed rosters]]
  def attach_configured_current_seat!(seat_context)
    identity = seat_context.fetch(:identity)
    office_identity = seat_context.fetch(:office_identity)
    chamber = seat_context.fetch(:chamber)
    district = seat_context.fetch(:district)
    seat_title = seat_context.fetch(:seat_title, prepared.title)
    current_terms = LegislatorTerm
      .where(legislator_id: legislator.id)
      .current(Date.current)
      .includes(:seat, :district)
      .to_a
    if current_terms.length > 1
      raise Seats::UnresolvedSeatError,
        "Multiple current terms prevent resolving configured seat identity for #{identity}"
    end

    term = TermWindow.running_on(Date.current, current_terms)
    return unless term

    term.with_lock do
      term.reload
      next unless TermWindow.running_on(Date.current, [term])

      unless term.legislator_id == legislator.id &&
          term.term_start_year == prepared.term_start_year &&
          term.term_end_year == prepared.term_end_year &&
          term.title == prepared.title &&
          term.district_id == district.id &&
          term.district.sway_locale_id == legislator.sway_locale_id
        raise Seats::UnresolvedSeatError,
          "Current term metadata does not match the prepared current term for #{identity}"
      end

      if term.seat_id.present?
        current_seat = term.seat
        unless current_seat
          raise Seats::UnresolvedSeatError,
            "Current term has an unresolved seat id #{term.seat_id.inspect} for #{identity}"
        end

        matching_seat = current_seat.district_id == district.id &&
          current_seat.seat_identifier == office_identity &&
          (current_seat.title == seat_title || current_seat.title == prepared.title) &&
          current_seat.chamber == chamber
        next true if matching_seat

        raise Seats::UnresolvedSeatError,
          "Current term seat #{current_seat.seat_identifier.inspect} conflicts with the prepared office identity #{office_identity.inspect}"
      end

      seat = Seat.find_or_create_by_identity!(
        district: district,
        office_identity: office_identity,
        title: seat_title,
        chamber: chamber
      )
      seat.with_lock do
        overlapping_terms = overlapping_terms_for_configured_seat(seat, term)
        same_person_overlap = overlapping_terms.find { |other| other.legislator_id == term.legislator_id }
        if same_person_overlap
          raise Seats::OverlapValidator::OverlapError,
            "Seat #{seat.seat_identifier} has overlapping terms for legislator #{term.legislator_id}: " \
            "Term #{term.id} conflicts with Term #{same_person_overlap.id}"
        end

        conflicting_term = overlapping_terms.first
        if conflicting_term
          warn_configured_seat_overlap(
            seat: seat,
            term: term,
            conflicting_term: conflicting_term,
            office_identity: office_identity
          )
          next false
        end

        term.update!(seat: seat)
        true
      end
    rescue Seat::IdentityConflictError => error
      raise Seats::UnresolvedSeatError, error.message
    end
  end

  def overlapping_terms_for_configured_seat(seat, term)
    target_start, target_end = configured_seat_interval(term)

    seat.legislator_terms.where.not(id: term.id).to_a.select do |other|
      other_start, other_end = configured_seat_interval(other)
      Seats::OverlapValidator.overlaps?(
        target_start,
        target_end,
        other_start,
        other_end
      )
    end
  end

  def configured_seat_interval(term)
    start_date = TermWindow.begins_on(term)
    end_date = TermWindow.ends_on(term)
    unless start_date < end_date
      raise Seats::OverlapValidator::InvalidIntervalError,
        "Term #{term.id || "new"} has an invalid seat interval: it must end after it begins"
    end

    [start_date, end_date]
  rescue SwayLocale::TermRules::Undeclared => error
    raise Seats::OverlapValidator::InvalidIntervalError,
      "Term #{term.id || "new"} has no declared calendar for seat occupancy: #{error.message}"
  end

  def warn_configured_seat_overlap(seat:, term:, conflicting_term:, office_identity:)
    metadata = {
      sway_locale: legislator.sway_locale.name,
      office_identity: office_identity,
      seat_identifier: seat.seat_identifier,
      incoming_legislator_id: term.legislator_id,
      incoming_term_id: term.id,
      conflicting_legislator_id: conflicting_term.legislator_id,
      conflicting_term_id: conflicting_term.id,
      starts_on: TermWindow.begins_on(term),
      ends_on: TermWindow.ends_on(term)
    }
    SwayLogging.warn("seed_legislator_terms.configured_seat_overlap", **metadata)
    Sentry.capture_message(
      "seed_legislator_terms.configured_seat_overlap in #{legislator.sway_locale.name}: " \
      "seat=#{seat.seat_identifier.inspect} incoming_term_id=#{term.id} " \
      "conflicting_term_id=#{conflicting_term.id}",
      level: :warning
    )
    nil
  end

  # @lat: [[representative-resolution#Representative resolution by seat#Seat identity]]
  def create_term!(term_attrs)
    return if term_attrs[:term_start_year].blank?

    LegislatorTerm.find_or_create_by!(
      legislator: legislator,
      term_start_year: term_attrs[:term_start_year]
    ) do |t|
      t.term_end_year = term_attrs[:term_end_year]
      t.title = term_attrs[:title]
      if supported_prepared_service?
        fact = prepared.official_fact
        t.district = prepared.district
        t.seat = Seat.find_or_create_by_identity!(
          district: prepared.district,
          office_identity: fact.office_identity,
          title: fact.title,
          chamber: fact.chamber
        )
        t.began_on = fact.start_date
        t.began_on_source = LegislatorTerm::DateSource::PUBLISHED
        t.ended_on = fact.end_date
        t.ended_on_source = LegislatorTerm::DateSource::PUBLISHED
      else
        t.district = term_attrs[:district] || prepared.district
        t.ended_on = published_ended_on(term_attrs)
        t.ended_on_source = LegislatorTerm::DateSource::PUBLISHED if t.ended_on
        t.began_on = published_began_on(term_attrs)
        t.began_on_source = LegislatorTerm::DateSource::PUBLISHED if t.began_on
        stamp_observed_start!(t)
      end
    end
  end

  def fill_missing_titles!
    return unless supported_prepared_service?

    stored_terms.each do |term|
      self.class.fill_missing_title!(term, prepared: prepared)
    end
  end

  def supported_prepared_service?
    prepared.is_a?(OfficialEvidence::PreparedServiceEntry) &&
      prepared.official_fact.supported_service? &&
      prepared.official_service_result.supported? &&
      prepared.official_service_result.facts.include?(prepared.official_fact) &&
      prepared.identity == prepared.official_fact.person_identity &&
      prepared.district.is_a?(District) &&
      prepared.district.name == prepared.official_fact.district &&
      prepared.official_fact.start_date.year == prepared.term_start_year &&
      prepared.official_fact.end_date.year == prepared.term_end_year &&
      prepared.official_fact.evidence.sway_locale_id == legislator.sway_locale_id &&
      prepared.district.sway_locale_id == legislator.sway_locale_id &&
      legislator.legislator_identifiers.any? { |identifier| identifier.identity == prepared.identity }
  end

  def official_service_entry?
    prepared.is_a?(OfficialEvidence::PreparedServiceEntry)
  end

  class << self
    # Fills a blank title when the retained fact identifies this exact term and seat.
    def fill_missing_title!(term, prepared:)
      return false unless title_match?(term, prepared)

      term.with_lock do
        term.reload
        next false if term.title.present?
        next false unless title_match?(term, prepared)

        term.update_columns(title: prepared.official_fact.title)
        true
      end
    end

    private

    def title_match?(term, prepared)
      return false unless prepared.is_a?(OfficialEvidence::PreparedServiceEntry)

      fact = prepared.official_fact
      result = prepared.official_service_result
      return false unless result.is_a?(OfficialEvidence::Result) && result.supported?
      return false unless result.facts.count { |candidate| exact_fact_for_term?(candidate, term) } == 1
      return false unless result.facts.include?(fact) && exact_fact_for_term?(fact, term)
      return false unless fact.supported_title? && fact.supported_service?
      return false unless fact.evidence.is_a?(OfficialEvidence) && fact.evidence.persisted? && !fact.evidence.changed?
      return false unless prepared.identity == fact.person_identity
      return false unless prepared.district.is_a?(District) && prepared.district.id == term.district_id
      return false unless prepared.district.sway_locale_id == term.legislator.sway_locale_id
      return false unless term.district.sway_locale_id == term.legislator.sway_locale_id
      return false unless fact.evidence.sway_locale_id == term.district.sway_locale_id
      return false unless fact.district == prepared.district.name && fact.district == term.district.name
      return false unless fact.office_identity == term.seat&.seat_identifier
      return false unless term.seat&.district_id == term.district_id
      return false unless term.seat&.sway_locale_id == term.legislator.sway_locale_id
      return false unless term.began_on == fact.start_date && term.ended_on == fact.end_date
      return false unless term.term_start_year == fact.start_date.year && term.term_end_year == fact.end_date.year
      return false unless term.began_on_source == LegislatorTerm::DateSource::PUBLISHED
      return false unless term.ended_on_source == LegislatorTerm::DateSource::PUBLISHED

      term.legislator.legislator_identifiers.any? do |identifier|
        identifier.sway_locale_id == term.legislator.sway_locale_id && identifier.identity == fact.person_identity
      end
    end

    def exact_fact_for_term?(fact, term)
      fact.is_a?(OfficialEvidence::Fact) &&
        fact.person_identity == term.legislator.legislator_identifiers.map(&:identity).find { |identity| identity == fact.person_identity } &&
        fact.office_identity == term.seat&.seat_identifier &&
        fact.district == term.district.name &&
        fact.start_date == term.began_on && fact.end_date == term.ended_on &&
        fact.evidence&.sway_locale_id == term.legislator.sway_locale_id
    end
  end

  # Records the day Sway first saw somebody in a seat, where that beats the
  # handover day their term year implies. Truth table in the spec.
  def stamp_observed_start!(term)
    # The jurisdiction's own published day outranks Sway's sighting.
    return if term.began_on.present?

    # A first seed of an empty locale would otherwise stamp every sitting
    # member with today, putting every past vote outside every term.
    return unless first_sighting

    # Tighter than "its convening date has passed": a published history writes
    # this person's PAST terms in the same run, and today began none of them.
    return unless TermWindow.running_on(observed_on, [term])

    term.began_on = observed_on
    term.began_on_source = LegislatorTerm::DateSource::OBSERVED
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster evidence for observed departures]]
  def clear_observed_departure!
    return unless prepared.current_member?

    observed =
      LegislatorTerm
        .where(legislator_id: legislator.id)
        .where.not(ended_on: nil)
        .where(term_start_year: LegislatorTerm.where(legislator_id: legislator.id).maximum(:term_start_year))

    observed.find_each do |term|
      Rails.logger.info(
        "[SeedLegislatorTerms] #{prepared.external_id} is in the roster again — preserving " \
        "existing departure date #{term.ended_on}"
      )
    end
  end

  # The day the source says this term ended, or nil.
  # @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars#Who says when a term began or ended is recorded, not flattened]]
  def published_ended_on(term_attrs)
    return nil unless legislator.sway_locale.term_rules.publishes_exact_term_dates

    date = term_attrs[:ended_on]
    return nil if date.nil?

    # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster evidence for observed departures]]
    return nil if serving_term?(term_attrs)

    # A future day on a past term or a departed entry is malformed data.
    return nil if date > Date.current

    date
  end

  # The serving term is the latest one a still-listed member's entry carries.
  # A departed entry has none.
  def serving_term?(term_attrs)
    serving_term_start_year.present? &&
      term_attrs[:term_start_year] == serving_term_start_year
  end

  def serving_term_start_year
    return nil unless prepared.current_member?

    @serving_term_start_year ||=
      [prepared.term_start_year, *proven_terms.pluck(:term_start_year)].compact.max
  end

  # The day the source says this term began, or nil. Same locale gate as the
  # end date. A future day IS kept: somebody not yet seated reading as not yet
  # serving is the honest answer, and the day arriving makes it true.
  def published_began_on(term_attrs)
    return nil unless legislator.sway_locale.term_rules.publishes_exact_term_dates

    term_attrs[:began_on]
  end

  # Brings a stored term's end year and title into line with the proven term
  # that starts the same year.
  # @lat: [[representative-resolution#Representative resolution by seat#Seat identity]]
  def correct_terms!
    stored_terms.each do |term|
      proven = proven_by_start_year[term.term_start_year]
      next if proven.nil?

      changes = {}
      changes[:term_end_year] = proven[:term_end_year] if proven[:term_end_year].present? &&
        proven[:term_end_year] != term.term_end_year
      changes[:title] = proven[:title] if proven[:title].present? && proven[:title] != term.title

      # @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars#Who says when a term began or ended is recorded, not flattened]]
      published = published_ended_on(proven)
      if published.present? && (published != term.ended_on || term.ended_on_source != LegislatorTerm::DateSource::PUBLISHED)
        changes[:ended_on] = published
        changes[:ended_on_source] = LegislatorTerm::DateSource::PUBLISHED
      end

      # @lat: [[current-legislator-term#Which term a legislator is serving now#A term carries the day it really began]]
      published_start = published_began_on(proven)
      if published_start.present? && (published_start != term.began_on || term.began_on_source != LegislatorTerm::DateSource::PUBLISHED)
        changes[:began_on] = published_start
        changes[:began_on_source] = LegislatorTerm::DateSource::PUBLISHED
      end

      next if changes.empty?

      Rails.logger.info(
        "[SeedLegislatorTerms] correcting #{prepared.external_id} term #{term.term_start_year}: #{changes.inspect}"
      )
      term.update_columns(changes)
    end
  end

  # Deletes a stored term the history does not know about.
  # @lat: [[current-legislator-term#Which term a legislator is serving now#Why a Congress term is rebuilt from published history]]
  def retire_unproven_terms!
    # An empty list is not evidence that every stored term is invented. It
    # means the entry arrived malformed, and acting on it would delete a
    # person's whole history.
    return if proven_by_start_year.empty?

    doomed = stored_terms.reject { |term| proven_by_start_year.key?(term.term_start_year) }
    return if doomed.empty?

    Rails.logger.info(
      "[SeedLegislatorTerms] retiring #{prepared.external_id} terms " \
      "#{doomed.map(&:term_start_year).sort.inspect} — no such term in the published history"
    )

    term_ids = doomed.map(&:id)
    # One transaction, because this is four statements that only make sense
    # together. A crash between them would leave the counts gone and the term
    # they were counted under still standing.
    LegislatorTerm.transaction do
      LegislatorDistrictScore.where(legislator_term_id: term_ids).delete_all
      LegislatorLocaleScore.where(legislator_term_id: term_ids).delete_all
      UserLegislatorTermScore.where(legislator_term_id: term_ids).delete_all
      LegislatorVote.where(legislator_term_id: term_ids).delete_all if LegislatorVote.column_names.include?("legislator_term_id")
      LegislatorTerm.where(id: term_ids).delete_all
    end

    rebuild_scores_for_remaining_terms!
  end

  # @lat: [[scores-and-agreement#The one-time repair walks every term, not only the current one]]
  def rebuild_scores_for_remaining_terms!
    remaining = LegislatorTerm.where(legislator_id: legislator.id).to_a
    return if remaining.empty?

    reader_links = UserLegislator.where(legislator_id: legislator.id).to_a

    remaining.each do |term|
      ScoreRecomputeService.recompute_legislator!(term)
      reader_links.each do |reader_link|
        ScoreRecomputeService.recompute_user_legislator!(reader_link, term)
      end
    end
  end

  def stored_terms
    @stored_terms ||= LegislatorTerm.where(legislator_id: legislator.id).to_a
  end

  # Asked twice per person, and each call walks every term and looks its seat
  # up in the districts table. On Congress that is about 2,900 terms, so held
  # once rather than paid twice on every boot.
  def proven_terms
    @proven_terms ||= prepared.proven_terms
  end

  def proven_by_start_year
    @proven_by_start_year ||= proven_terms.index_by { |term_attrs| term_attrs[:term_start_year] }
  end
end
