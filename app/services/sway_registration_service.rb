# frozen_string_literal: true

# @lat: [[identity-and-access#Registration is asynchronous by necessity]]
class SwayRegistrationService
  include SwayGeocode

  attr_reader :address, :sway_locale, :skipped_resolution_errors, :skipped_legislator_ids

  def initialize(user, address, sway_locale, invited_by_id:, async: true)
    @user = user
    @address = address
    @sway_locale = sway_locale
    @legislators = sway_locale.legislators.with_active_term

    @invited_by_id = invited_by_id
    @async = async

    @feature = nil
    @districts = nil

    @skipped_resolution_errors = []
    @skipped_term_ids = []
    @skipped_legislator_ids = []
  end

  def call
    if @async && @sway_locale.regional?
      @user.start_processing! if @user.pending?
      SwayRegistrationJob.perform_later(
        @user.id,
        @address.id,
        @sway_locale.id,
        invited_by_id: @invited_by_id,
        enqueued_at_epoch: Time.current.to_f
      )
      return []
    end

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    uls = create_user_legislators
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    if uls.blank?
      SwayLogging.info("sway_registration.no_user_legislators_created", user_id: @user.id)
      @user.transient_funnel_metadata = {latency_ms: duration_ms, reason: "no_user_legislators_created"}
      return uls
    end

    @user.transient_funnel_metadata = {latency_ms: duration_ms}
    @user.complete! if @user.registered?

    create_invite

    uls
  end

  def create_user_legislators
    district_legislators.map do |l|
      ul = UserLegislator.find_or_initialize_by(user: @user, legislator: l)
      ul.active = true unless ul.active
      ul.save!

      # @lat: [[identity-and-access#Registration is asynchronous by necessity]]
      if l.district
        ud = UserDistrict.find_or_initialize_by(user: @user, district: l.district)
        ud.active = true unless ud.active
        ud.save!
      end

      # @lat: [[identity-and-access#Registration is asynchronous by necessity#Registration service results preserve their rows]]
      ul
    end
  end

  # @lat: [[representative-resolution#Resolution branches]]
  def district_legislators
    if @legislators.blank?
      SwayLogging.info("sway_registration.no_legislators_in_locale", sway_locale: @sway_locale.name)
      all_candidates = []
    else
      candidates = if sway_locale.regional?
        find_legislators_from_open_states_geo_endpoint
      elsif sway_locale.congress?
        state_code = address.us_state_code
        district_numbers = state_code ? congress_district_numbers : []
        @legislators.filter do |legislator|
          term = legislator.active_term
          term && term.district.region_code == state_code && district_numbers.include?(term.district.number)
        end
      else
        @legislators.filter do |legislator|
          term = legislator.active_term
          term && term.district.region_code == address.region_code && districts.include?(term.district.number)
        end
      end
      all_candidates = candidates + locale_wide_candidates
    end

    resolved = resolve_seat_candidates(all_candidates)
    if resolved.blank?
      SwayLogging.info("sway_registration.no_district_legislators_found", sway_locale: @sway_locale.name)
    else
      SwayLogging.info(
        "sway_registration.district_legislators_found",
        count: resolved.length,
        sway_locale: @sway_locale.name
      )
    end
    resolved
  end

  private

  def locale_wide_candidates
    unless sway_locale.congress?
      matches_locale = address.region_code == sway_locale.state_code &&
        (sway_locale.regional? || address.city.to_s.casecmp?(sway_locale.city.to_s))
      return [] unless matches_locale
    end

    district_name = sway_locale.locale_wide_district_name
    return [] if district_name.blank?

    district = sway_locale.districts.find_by(name: district_name)
    return [] unless district

    terms = district.legislator_terms.current.includes(:legislator, :seat).to_a
      .reject { |term| unseated_unconfigured_office?(term) }
    seated_terms, unseated_terms = terms.partition { |term| term.seat_id.present? && term.seat.present? }
    unseated_terms.each do |term|
      skip_unresolved_terms(
        [term],
        Seats::UnresolvedSeatError.new(
          "Locale-wide term #{term.id} in #{sway_locale.name} has no persisted seat identity"
        )
      )
    end

    seated_terms.map(&:legislator)
  end

  def resolve_seat_candidates(candidates)
    candidate_terms = candidates.filter_map(&:active_term).uniq(&:id)
      .reject { |term| unseated_unconfigured_office?(term) }
    seated_terms, unseated_terms = candidate_terms.partition { |term| term.seat_id.present? && term.seat.present? }
    unseated_terms.each do |term|
      skip_unresolved_terms(
        [term],
        Seats::UnresolvedSeatError.new(
          "Current term #{term.id} in #{sway_locale.name} has no persisted seat identity"
        )
      )
    end

    seat_ids = terms_within_locale(seated_terms).map(&:seat_id).uniq
    return [] if seat_ids.empty?

    current_terms = LegislatorTerm.current
      .where(seat_id: seat_ids)
      .includes(:legislator, :seat, district: :sway_locale)
      .to_a
    single_occupants = current_terms.group_by(&:seat_id).filter_map do |seat_id, occupants|
      next occupants.first if occupants.length == 1

      seat = occupants.first.seat
      skip_unresolved_terms(
        occupants,
        Seats::OverlapValidator::OverlapError.new(
          "Seat #{seat&.seat_identifier || seat_id} has multiple current occupants"
        )
      )
      nil
    end

    terms_within_locale(single_occupants).map(&:legislator).uniq(&:id)
  end

  def terms_within_locale(terms)
    inside, outside = terms.partition do |term|
      term.seat&.district_id == term.district_id &&
        term.district.sway_locale_id == sway_locale.id &&
        term.legislator.sway_locale_id == sway_locale.id
    end
    outside.each do |term|
      skip_unresolved_terms(
        [term],
        Seats::UnresolvedSeatError.new("Current term #{term.id} has a seat outside its locale or district")
      )
    end
    inside
  end

  # @lat: [[representative-resolution#Representative resolution by seat#Resolution branches]]
  def skip_unresolved_terms(terms, error)
    term_ids = terms.map(&:id)
    return if (term_ids - @skipped_term_ids).empty?

    @skipped_term_ids.concat(term_ids)
    @skipped_legislator_ids.concat(terms.map(&:legislator_id))
    @skipped_resolution_errors << error
    SwayLogging.warn(
      "sway_registration.unresolved_term_skipped",
      term_ids:,
      district: terms.first.district.name,
      sway_locale: sway_locale.name,
      error_class: error.class.name
    )
    Sentry.capture_exception(error, level: :warning)
  end

  # @lat: [[representative-resolution#Representative resolution by seat#Unconfigured offices]]
  def unseated_unconfigured_office?(term)
    return false if term.seat_id.present? || term.title.blank?
    return false unless SwayLocale::TermRulesRegistry.declared?(sway_locale.name)

    rules = sway_locale.term_rules
    rules.seat_chambers.any? && rules.seat_chamber_for(term.title).nil?
  end

  def districts
    @districts ||= SwayGeocode.build(sway_locale, address).districts
  end

  # @lat: [[representative-resolution#Congress fallback]]
  def congress_district_numbers
    return [0] unless address.located?

    districts.presence || [0]
  rescue SwayGeocode::ServiceUnavailableError => e
    @skipped_resolution_errors << e
    @skipped_legislator_ids.concat(state_house_legislator_ids)
    SwayLogging.warn(
      "sway_registration.house_district_skipped",
      sway_locale: sway_locale.name,
      error_class: e.class.name
    )
    Sentry.capture_exception(e, level: :warning)
    [0]
  end

  def state_house_legislator_ids
    @legislators.filter_map do |legislator|
      district = legislator.active_term&.district
      legislator.id if district && district.region_code == address.us_state_code && district.number != 0
    end
  end

  def find_legislators_from_open_states_geo_endpoint
    # @lat: [[identity-and-access#Registration is asynchronous by necessity#Regional lookup uses one configured request path]]
    open_states_api_key = EnvSecret.read("OPEN_STATES_API_KEY")

    if open_states_api_key.blank?
      SwayLogging.error(
        "\n####################################################################################\n"
      )
      SwayLogging.error(
        "No OPEN_STATES_API_KEY Found! Cannot register state legislators with a user."
      )
      SwayLogging.error(
        "\n####################################################################################\n"
      )
      return []
    end

    # @lat: [[identity-and-access#Registration is asynchronous by necessity#Regional lookup uses one configured request path]]
    response =
      Sway::FaradayStack.open_states.get(
        "people.geo",
        apikey: open_states_api_key,
        lat: address.latitude,
        lng: address.longitude
      )

    unless response.status.between?(200, 299)
      raise SwayGeocode::ServiceUnavailableError,
        "OpenStates geocoding returned HTTP #{response.status}"
    end

    # @lat: [[identity-and-access#Registration is asynchronous by necessity#Regional lookup uses one configured request path]]
    result = Array(JSON.parse(response.body)["results"]) #: Array[untyped]

    filtered =
      result
        .filter do |res|
          RegionUtil.from_region_name_to_region_code(
            res.dig("jurisdiction", "name")
          ) == sway_locale.region_code
        end
        .pluck("id")
        .compact

    # @lat: [[identity-and-access#Registration is asynchronous by necessity#Regional lookup uses one configured request path]]
    @legislators.filter do |legislator|
      filtered.include?(legislator.external_id)
    end
  rescue Faraday::Error, JSON::ParserError => e
    raise SwayGeocode::ServiceUnavailableError,
      "OpenStates geocoding is unavailable: #{e.message}"
  end

  def create_invite
    return if @invited_by_id.blank?

    u = User.find_by(id: @invited_by_id)
    return if u.blank?

    # @lat: [[identity-and-access#Registration is asynchronous by necessity#Invite bookkeeping cannot abort registration]]
    Invite.create_or_find_by!(inviter: u, invitee: @user)
  rescue ActiveRecord::RecordInvalid => e
    SwayLogging.log_exception(
      "sway_registration.create_invite_failed",
      exception: e,
      inviter_id: u&.id,
      invitee_id: @user.id
    )
  end
end
