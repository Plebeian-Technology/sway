# frozen_string_literal: true

# @lat: [[identity-and-access#Registration is asynchronous by necessity]]
class SwayRegistrationService
  include SwayGeocode

  attr_reader :address, :sway_locale

  def initialize(user, address, sway_locale, invited_by_id:, async: true)
    @user = user
    @address = address
    @sway_locale = sway_locale
    @legislators = sway_locale.legislators.with_active_term

    @invited_by_id = invited_by_id
    @async = async

    @feature = nil
    @districts = nil
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
    unresolved = terms.find { |term| term.seat_id.blank? || term.seat.nil? }
    if unresolved
      raise Seats::UnresolvedSeatError,
        "Locale-wide term #{unresolved.id} in #{sway_locale.name} has no persisted seat identity"
    end

    terms.map(&:legislator)
  end

  def resolve_seat_candidates(candidates)
    candidate_terms = candidates.filter_map(&:active_term).uniq(&:id)
      .reject { |term| unseated_unconfigured_office?(term) }
    unresolved = candidate_terms.find { |term| term.seat_id.blank? || term.seat.nil? }
    if unresolved
      raise Seats::UnresolvedSeatError,
        "Current term #{unresolved.id} in #{sway_locale.name} has no persisted seat identity"
    end

    candidate_terms.each do |term|
      seat = term.seat
      unless seat && term.district.sway_locale_id == sway_locale.id &&
          seat.district_id == term.district_id &&
          term.legislator.sway_locale_id == sway_locale.id
        raise Seats::UnresolvedSeatError,
          "Current term #{term.id} has a seat outside its locale or district"
      end
    end

    seat_ids = candidate_terms.map(&:seat_id).uniq
    return [] if seat_ids.empty?

    current_terms = LegislatorTerm.current
      .where(seat_id: seat_ids)
      .includes(:legislator, :seat, district: :sway_locale)
      .to_a
    current_terms.group_by(&:seat_id).each do |seat_id, occupants|
      if occupants.length > 1
        seat = occupants.first.seat
        raise Seats::OverlapValidator::OverlapError,
          "Seat #{seat&.seat_identifier || seat_id} has multiple current occupants"
      end
    end

    current_terms.each do |term|
      unless term.seat&.district_id == term.district_id &&
          term.district.sway_locale_id == sway_locale.id &&
          term.legislator.sway_locale_id == sway_locale.id
        raise Seats::UnresolvedSeatError,
          "Current term #{term.id} has a seat outside its locale or district"
      end
    end

    current_terms.map(&:legislator).uniq(&:id)
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
