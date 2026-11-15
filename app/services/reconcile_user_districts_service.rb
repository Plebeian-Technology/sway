# frozen_string_literal: true

# @lat: [[reconcile-user-districts-service-design#Why call does not catch its own lookup failure]]
class ReconcileUserDistrictsService
  def initialize(user, sway_locale)
    @user = user
    @sway_locale = sway_locale
  end

  # @lat: [[reconcile-user-districts-service-design#Why call does not catch its own lookup failure]]
  def call
    address = @user.address
    return if address.blank?

    service = registration_service(address)
    resolved_legislators = service.district_legislators
    # @lat: [[representative-resolution#Representative resolution by seat#Resolution branches]]
    skipped_error = service.skipped_resolution_errors.first
    raise skipped_error if skipped_error

    apply_diff(resolved_legislators)
  end

  private

  def registration_service(address)
    SwayRegistrationService.new(@user, address, @sway_locale, invited_by_id: nil, async: false)
  end

  def apply_diff(resolved_legislators)
    resolved_legislator_ids = resolved_legislators.map(&:id)
    resolved_districts = resolved_legislators.filter_map(&:district).uniq(&:id)
    resolved_district_ids = resolved_districts.map(&:id)

    stored_uls = @user.user_legislators_by_locale(@sway_locale)
    stored_legislator_ids = stored_uls.map(&:legislator_id)

    stored_user_districts =
      UserDistrict
        .active
        .joins(:district)
        .where(user: @user, districts: {sway_locale_id: @sway_locale.id})
        .to_a
    stored_district_ids = stored_user_districts.map(&:district_id)

    stale_legislator_ids = stored_legislator_ids - resolved_legislator_ids
    new_legislator_ids = resolved_legislator_ids - stored_legislator_ids
    stale_district_ids = stored_district_ids - resolved_district_ids
    new_district_ids = resolved_district_ids - stored_district_ids

    return if stale_legislator_ids.blank? && new_legislator_ids.blank? &&
      stale_district_ids.blank? && new_district_ids.blank?

    new_uls = [] #: Array[UserLegislator]

    ApplicationRecord.transaction do
      stored_uls
        .select { |ul| stale_legislator_ids.include?(ul.legislator_id) }
        .each { |ul| ul.update!(active: false) }

      new_uls =
        resolved_legislators
          .select { |l| new_legislator_ids.include?(l.id) }
          .map { |legislator| activate_user_legislator!(legislator) }

      stored_user_districts
        .select { |ud| stale_district_ids.include?(ud.district_id) }
        .each { |ud| ud.update!(active: false) }

      resolved_districts
        .select { |d| new_district_ids.include?(d.id) }
        .each { |district| activate_user_district!(district) }
    end

    begin
      RepresentativeReassignmentObserver.observe_diff!(
        user: @user,
        stale_district_ids:,
        new_district_ids:,
        stale_legislator_ids:,
        new_legislator_ids:,
        stored_uls:,
        resolved_legislators:,
        stored_user_districts:,
        resolved_districts:
      )
    rescue => e
      SwayLogging.log_exception(
        "reconcile_user_districts.observe_diff_failed",
        exception: e,
        user_id: @user.id,
        sway_locale_id: @sway_locale.id
      )
    end

    new_uls.each do |ul|
      term = ul.legislator.active_term
      ScoreRecomputeService.recompute_user_legislator!(ul, term) if term
    end

    stale_legislators =
      stored_uls
        .select { |ul| stale_legislator_ids.include?(ul.legislator_id) }
        .filter_map(&:legislator)
    new_legislators = resolved_legislators.select { |l| new_legislator_ids.include?(l.id) }

    (stale_legislators + new_legislators).uniq(&:id).each do |legislator|
      term = legislator.active_term
      ScoreRecomputeService.recompute_legislator_district!(term) if term
    end

    Bill.where(sway_locale: @sway_locale, id: @user.user_votes.select(:bill_id)).find_each do |bill|
      ScoreRecomputeService.recompute_bill!(bill)
    end

    ScoreUpdaterService.broadcast_score_refresh(@user)
  end

  def activate_user_legislator!(legislator)
    ul = UserLegislator.find_or_initialize_by(user: @user, legislator:)
    ul.active = true unless ul.active
    ul.save!
    ul
  end

  def activate_user_district!(district)
    ud = UserDistrict.find_or_initialize_by(user: @user, district:)
    ud.active = true unless ud.active
    ud.save!
  end
end
