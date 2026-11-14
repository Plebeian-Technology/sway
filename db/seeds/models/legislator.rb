# frozen_string_literal: true

require_relative "../seed_preparers/legislators/congress_dot_gov"
require_relative "../seed_preparers/legislators/open_states"
require_relative "../seed_preparers/legislators/sway"
require_relative "../seedable"
require_relative "../seed_log"
require_relative "seed_legislator_terms"

# Creates a Legislator in Sway only if they do not exist, and keeps their
# person attributes in step with the source. Their term rows are written by
# SeedLegislatorTerms, which owns the rules about when a stored term may be
# changed.
class SeedLegislator
  include Seedable

  class MissingRegionCode < StandardError
  end

  class NonStateRegionCode < StandardError
  end

  # Raised when one JSON row cannot be seeded (for example, a required
  # NOT NULL field is missing). The message carries the locale and external_id
  # so the bad row can be found, instead of the run dying with an opaque
  # database error or KeyError.
  class SeedError < StandardError
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding]]
  def self.preparer_class_for(roster_source)
    case roster_source&.to_sym
    when :congress_dot_gov then SeedPreparers::Legislators::CongressDotGov
    when :open_states then SeedPreparers::Legislators::OpenStates
    when :curated then SeedPreparers::Legislators::Sway
    else
      raise SeedError, "No legislator seed preparer reads roster source/engine #{roster_source.inspect}"
    end
  end

  ###################################
  # Class Methods
  ###################################

  def self.read_legislators(sway_locale)
    # Reads the committed seed roster for the locale:
    #   db/seeds/data/<reversed_name with - replaced by />/legislators.json
    JSON.parse(
      File.read(
        "db/seeds/data/#{sway_locale.reversed_name.tr("-", "/")}/legislators.json"
      )
    )
  end

  def self.run(sway_locales, force: false)
    sway_locales.each do |sway_locale|
      legislators_json = read_legislators(sway_locale)
      official_service_result = official_service_result_for(sway_locale)
      total = legislators_json.size
      SeedLog.say("→ #{sway_locale.name}: seeding #{total} legislators from JSON…")

      # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding]]
      seen_identity_values = []

      # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding]]
      unidentified_entries = []

      # @lat: [[current-legislator-term#Which term a legislator is serving now#A term carries the day it really began]]
      locale_had_legislators = Legislator.where(sway_locale: sway_locale).exists?

      executive_preparers = []
      legislators_json.each_with_index do |j, index|
        # Heartbeat for large rosters (e.g. Congress ~537) so the terminal shows
        # movement during a long run instead of looking frozen.
        if total > 100 && ((index + 1) % 100).zero?
          SeedLog.say("   …#{index + 1}/#{total}")
        end

        seed_legislator =
          SeedLegislator.new(
            j,
            sway_locale,
            force: force,
            locale_had_legislators: locale_had_legislators,
            official_service_result:
          )
        next unless seed_legislator.present? && seed_legislator.prepared.present?
        next if seed_legislator.unconfigured_executive_office?
        if seed_legislator.uncurated_executive?
          executive_preparers << seed_legislator.prepared
          next
        end

        begin
          identity = seed_legislator.prepared.identity
          if identity
            seen_identity_values << identity.value
          else
            unidentified_entries << seed_legislator.prepared.external_id
          end
          seed_legislator.seed
        rescue => e
          # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding]]
          raise SeedError,
            "Failed to seed #{sway_locale.name} legislator external_id=" \
            "#{j["id"] || j["external_id"] || j["externalId"] || j["bioguideId"] || "?"}: " \
            "#{e.class}: #{e.message}"
        end
      end

      retire_unevidenced_executive_terms!(
        sway_locale,
        official_service_result: official_service_result,
        executive_preparers: executive_preparers
      )

      OfficialEvidence::SeedService.new(
        sway_locale: sway_locale,
        result: official_service_result
      ).call
      ExecutiveTitleFillService.new(
        sway_locale,
        official_service_result: official_service_result
      ).call

      # Remove duplicate ids before the roster-size check. The list gains one
      # entry per JSON row, so a bad fetch that repeats an external_id must
      # not inflate the count and slip past the truncated-fetch guard below.
      seen_identity_values.uniq!
      unidentified_entries.uniq!

      # @lat: [[current-legislator-term#Which term a legislator is serving now#Departure safeguards]]
      current_serving = Legislator.where(sway_locale: sway_locale).serving.count

      if seen_identity_values.empty? || seen_identity_values.size < (current_serving / 2.0)
        Rails.logger.warn(
          "[SeedLegislator] #{sway_locale.name}: fresh roster #{seen_identity_values.size}" \
          " << serving #{current_serving}; skipping reconcile enqueue"
        )
        SeedLog.say(
          "✓ #{sway_locale.name}: #{total} processed (reconcile enqueue skipped — " \
          "fresh roster #{seen_identity_values.size} << serving #{current_serving})"
        )
        next
      end

      # Only past the floor above, and the service bounds how many people one
      # run may retire. A locale whose roster keeps departed
      # members declares so and this does nothing.
      RetireDepartedLegislatorsService.new(
        sway_locale, seen_identity_values, unidentified_entries: unidentified_entries
      ).call

      serving_now = Legislator.where(sway_locale: sway_locale).serving.count
      SeedLog.say("✓ #{sway_locale.name}: #{total} processed, #{serving_now} serving")

      # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding]]
      ReconcileUserDistrictsJob.perform_later(sway_locale.id)
    end
  end

  def self.official_service_result_for(sway_locale)
    Legislation::Adapters::GenericRosterAdapter.new(sway_locale)
      .fetch_official_service(sway_locale:)
  end

  def self.district_name(region_code, district)
    return nil if region_code.blank?
    "#{region_code}#{district}"
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Planned automatic legislator updates#Presidential display]]
  def self.retire_unevidenced_executive_terms!(sway_locale, official_service_result:, executive_preparers:)
    return unless official_service_result&.unsupported?
    return if executive_preparers.empty?

    executive_legislators = executive_preparers.filter_map do |prep|
      identity = prep.identity
      leg = LegislatorIdentifier.legislator_for(sway_locale: sway_locale, identity: identity) if identity
      leg || Legislator.find_by(sway_locale: sway_locale, external_id: prep.external_id)
    end.uniq

    return if executive_legislators.empty?

    doomed_terms = LegislatorTerm.where(
      legislator: executive_legislators,
      seat_id: nil,
      title: nil
    ).to_a

    has_term_id_on_votes = LegislatorVote.column_names.include?("legislator_term_id")
    doomed_terms.select! do |term|
      if has_term_id_on_votes
        LegislatorVote.where(legislator_term_id: term.id).none?
      else
        LegislatorVote.where(legislator_id: term.legislator_id).none?
      end
    end

    return if doomed_terms.empty?

    term_ids = doomed_terms.map(&:id)
    Rails.logger.info(
      "[SeedLegislator] retiring un-evidenced executive sentinel terms #{term_ids.inspect} in #{sway_locale.name}"
    )

    LegislatorTerm.transaction do
      LegislatorDistrictScore.where(legislator_term_id: term_ids).delete_all
      LegislatorLocaleScore.where(legislator_term_id: term_ids).delete_all
      UserLegislatorTermScore.where(legislator_term_id: term_ids).delete_all
      LegislatorVote.where(legislator_term_id: term_ids).delete_all if has_term_id_on_votes
      LegislatorTerm.where(id: term_ids).delete_all
    end
  end

  ###################################
  # Instance Methods
  ###################################

  attr_reader :prepared, :sway_locale

  def initialize(json, sway_locale, force: false, locale_had_legislators: false, official_service_result: nil)
    @sway_locale = sway_locale
    @force = force
    @locale_had_legislators = locale_had_legislators
    @official_service_result = official_service_result

    rules = sway_locale.jurisdiction_rules
    engine = rules.retrieval_for(:roster) ||
      rules.roster_rules&.dig(:retrieval) ||
      rules.roster_rules&.dig("retrieval") ||
      rules.roster_rules&.dig(:engine) ||
      rules.roster_rules&.dig("engine") ||
      (rules.respond_to?(:roster_source) ? rules.roster_source : nil)
    @prepared = self.class
      .preparer_class_for(engine)
      .new(json, sway_locale)
  end

  def seed
    legislator
  end

  # Returns true when the entry holds an executive office whose title the
  # locale's term_rules.seat_chambers leaves out; such entries are not seeded.
  # @lat: [[representative-resolution#Maryland seat identity conventions#Executive offices without a configured chamber]]
  def unconfigured_executive_office?
    return false unless prepared.respond_to?(:executive_office?) && prepared.executive_office?

    chambers = sway_locale.term_rules.seat_chambers
    return false if chambers.empty?

    title = prepared.title
    return false if title.blank?

    !chambers.key?(title) && !chambers.key?(SeedLegislatorTerms::TITLE_ALIASES.fetch(title, title))
  end

  # @lat: [[official-service-evidence#The curated President record]]
  def uncurated_executive?
    prepared.executive? && !prepared.curated_president?
  end

  def legislator
    return nil if prepared.json.nil?
    return nil if uncurated_executive?

    Rails.logger.info(
      "Seeding #{sway_locale.city.titleize} Legislator external_id: #{prepared.external_id}"
    )

    identity = prepared.identity
    return skip_unidentifiable_entry if identity.nil?

    l = person_for(identity)

    # Read before the save below, which turns a new row into a stored one. See
    # SeedLegislatorTerms#stamp_observed_start!.
    first_sighting = @locale_had_legislators && l.new_record?

    if seed_or_skip?(l, force: @force)
      Rails.logger.info(
        "SeedLegislator: leaving #{l.external_id} person attributes alone — edited out-of-band since last seed"
      )
    else
      # Person attributes update IN PLACE on every clean re-seed.
      # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding]]
      l.sway_locale = sway_locale
      l.first_name = prepared.first_name
      l.last_name = prepared.last_name
      l.party = prepared.party
      l.photo_url = prepared.photo_url
      l.phone = prepared.phone
      l.email = prepared.email
      l.twitter = prepared.twitter
      l.link = prepared.link

      # Only call save! when something actually changed.
      l.save! if l.new_record? || l.changed?
      stamp_seeded_at!(l)
    end

    # Recorded after the save, because a brand new person has no id until then,
    # and outside the guard above, because the guard protects a HAND EDIT to
    # the person attributes. Nobody edits an identifier by hand, and the row
    # this seed just resolved is by definition the one that identity names.
    LegislatorIdentifier.record!(legislator: l, identity: identity)

    # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding]]
    SeedLegislatorTerms.new(l, prepared, first_sighting: first_sighting).call unless uncurated_executive?

    l
  end

  private

  attr_reader :official_service_result

  # The person this locale's source already calls +identity+, or an unsaved new
  # one.
  # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding]]
  def person_for(identity)
    LegislatorIdentifier.legislator_for(sway_locale: sway_locale, identity: identity) ||
      Legislator.find_or_initialize_by(sway_locale: sway_locale, external_id: identity.value)
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding]]
  def skip_unidentifiable_entry
    SwayLogging.warn(
      "seed_legislator.unidentifiable_entry",
      sway_locale: sway_locale.name,
      external_id: prepared.external_id
    )

    # @lat: [[boot-failure-reporting]]
    Sentry.capture_message(
      "seed_legislator: #{sway_locale.name} entry #{prepared.external_id.inspect} names no " \
      "person, so the row it would seed was left alone",
      level: :warning
    )
    nil
  end
end
