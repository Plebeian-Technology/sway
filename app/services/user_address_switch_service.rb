# frozen_string_literal: true

# @lat: [[identity-and-access#A user holds one address]]
class UserAddressSwitchService
  COOLDOWN_PERIOD = 30.days

  def self.cooldown_active_for?(user)
    user.user_address_changes.where("created_at >= ?", COOLDOWN_PERIOD.ago).exists?
  end

  def initialize(user, previous_address:, new_address:)
    @user = user
    @previous_address = previous_address
    @new_address = new_address
  end

  def call
    resolved_legislators, skipped_legislator_ids = resolve_legislators_for_new_address
    return nil if resolved_legislators.empty?

    resolved_legislator_ids = resolved_legislators.map(&:id).uniq
    resolved_districts = resolved_legislators.filter_map(&:district).uniq(&:id)
    resolved_district_ids = resolved_districts.map(&:id).uniq

    active_uls = [] #: Array[UserLegislator]
    stale_legislator_ids = [] #: Array[Integer]
    new_legislator_ids = [] #: Array[Integer]
    new_uls = [] #: Array[UserLegislator]
    change = nil #: UserAddressChange?

    ApplicationRecord.transaction do
      active_uls = @user.user_legislators.active.includes(legislator: [:district, :legislator_terms]).to_a
      active_uds = @user.user_districts.active.includes(:district).to_a

      active_legislator_ids = active_uls.map(&:legislator_id).uniq
      active_district_ids = (
        active_uds.map(&:district_id) +
        active_uls.filter_map { |ul| ul.legislator.district&.id }
      ).uniq

      skipped_district_ids = active_uls
        .select { |ul| skipped_legislator_ids.include?(ul.legislator_id) }
        .filter_map { |ul| ul.legislator.district&.id }

      # @lat: [[representative-resolution#Resolution branches]]
      stale_legislator_ids = active_legislator_ids - resolved_legislator_ids - skipped_legislator_ids
      new_legislator_ids = resolved_legislator_ids - active_legislator_ids
      stale_district_ids = active_district_ids - resolved_district_ids - skipped_district_ids
      new_district_ids = resolved_district_ids - active_district_ids

      previous_sway_locale_ids = (
        active_uds.filter_map { |ud| ud.district.sway_locale_id } +
        active_uls.filter_map { |ul| ul.legislator.district&.sway_locale_id || ul.legislator.sway_locale_id }
      ).uniq
      previous_sway_locale_ids = @previous_address.sway_locales.map(&:id).uniq if previous_sway_locale_ids.empty?

      new_sway_locale_ids = resolved_districts.map(&:sway_locale_id).uniq

      votes = @user.user_votes.includes(:bill).to_a
      prior_vote_count = votes.size
      prior_voted_bill_ids = votes.map(&:bill_id).uniq
      prior_voted_sway_locale_ids = votes.filter_map { |v| v.bill.sway_locale_id }.uniq

      existing_link = @user.user_address
      if existing_link
        existing_link.update!(address: @new_address)
      else
        UserAddress.create!(user: @user, address: @new_address)
      end

      active_uls
        .select { |ul| stale_legislator_ids.include?(ul.legislator_id) }
        .each { |ul| ul.update!(active: false) }

      new_uls =
        resolved_legislators
          .map { |legislator| activate_user_legislator!(legislator) }
          .select { |ul| new_legislator_ids.include?(ul.legislator_id) }

      active_uds
        .select { |ud| stale_district_ids.include?(ud.district_id) }
        .each { |ud| ud.update!(active: false) }

      resolved_districts.each { |district| activate_user_district!(district) }

      change = UserAddressChange.create!(
        user: @user,
        previous_address: @previous_address,
        new_address: @new_address,
        deactivated_legislator_ids: stale_legislator_ids,
        activated_legislator_ids: new_legislator_ids,
        deactivated_district_ids: stale_district_ids,
        activated_district_ids: new_district_ids,
        previous_sway_locale_ids: previous_sway_locale_ids,
        new_sway_locale_ids: new_sway_locale_ids,
        prior_vote_count: prior_vote_count,
        prior_voted_bill_ids: prior_voted_bill_ids,
        prior_voted_sway_locale_ids: prior_voted_sway_locale_ids
      )
    end

    return nil unless change

    recompute_scores(
      active_uls: active_uls,
      resolved_legislators: resolved_legislators,
      stale_legislator_ids: stale_legislator_ids,
      new_legislator_ids: new_legislator_ids,
      new_uls: new_uls
    )

    SwayLogging.info(
      "sway_registration.address_switched",
      user_id: @user.id,
      user_address_change_id: change.id,
      previous_address_id: @previous_address.id,
      new_address_id: @new_address.id
    )
    ScoreUpdaterService.broadcast_score_refresh(@user)

    change
  end

  private

  def resolve_legislators_for_new_address
    services = @new_address.sway_locales.map do |sway_locale|
      SwayRegistrationService.new(
        @user,
        @new_address,
        sway_locale,
        invited_by_id: nil
      )
    end
    legislators = services.flat_map(&:district_legislators).uniq(&:id)
    [legislators, services.flat_map(&:skipped_legislator_ids).uniq]
  end

  def activate_user_legislator!(legislator)
    ul = UserLegislator.find_or_initialize_by(user: @user, legislator: legislator)
    ul.active = true unless ul.active
    ul.save!
    ul
  end

  def activate_user_district!(district)
    ud = UserDistrict.find_or_initialize_by(user: @user, district: district)
    ud.active = true unless ud.active
    ud.save!
  end

  def recompute_scores(active_uls:, resolved_legislators:, stale_legislator_ids:, new_legislator_ids:, new_uls:)
    new_uls.each do |ul|
      term = ul.legislator.active_term
      ScoreRecomputeService.recompute_user_legislator!(ul, term) if term
    end

    stale_legislators =
      active_uls
        .select { |ul| stale_legislator_ids.include?(ul.legislator_id) }
        .filter_map(&:legislator)
    new_legislators = resolved_legislators.select { |l| new_legislator_ids.include?(l.id) }

    # @lat: [[voter-privacy-threshold#Bill tallies are recomputed before the legislator scores that read them]]
    bill_ids = @user.user_votes.pluck(:bill_id)
    Bill.where(id: bill_ids).find_each do |bill|
      ScoreRecomputeService.recompute_bill!(bill)
    end

    moved_legislators = (stale_legislators + new_legislators).uniq(&:id)
    moved_legislators.each do |legislator|
      term = legislator.active_term
      ScoreRecomputeService.recompute_legislator_locale!(term) if term
    end
    ScoreRecomputeService.recompute_district_scores!(bill_ids, legislators: moved_legislators)
  end
end
