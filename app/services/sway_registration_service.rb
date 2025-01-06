# typed: true

# frozen_string_literal: true

# require 'lib/sway_geocode'

class SwayRegistrationService
  extend T::Sig
  include SwayGeocode

  sig { returns(Address) }
  attr_reader :address

  sig { returns(SwayLocale) }
  attr_reader :sway_locale

  sig { params(user: User, address: Address, sway_locale: SwayLocale, invited_by_id: T.nilable(Integer)).void }
  def initialize(user, address, sway_locale, invited_by_id:)
    @user = user
    @address = address
    @sway_locale = sway_locale
    @legislators = sway_locale.legislators

    @invited_by_id = invited_by_id

    @feature = T.let(nil, T.nilable(RGeo::GeoJSON::Feature))
    @districts = nil
  end

  sig { returns(T::Array[UserLegislator]) }
  def run
    uls = create_user_legislators

    if uls.blank?
      Rails.logger.info("SwayRegistrationService.run - no UserLegislators created for User: #{@user.id}")
      puts("SwayRegistrationService.run - no UserLegislators created for User: #{@user.id}")
      return uls
    end

    @user.is_registration_complete = true
    @user.save!

    create_invite

    uls
  end

  sig { returns(T::Array[UserLegislator]) }
  def create_user_legislators
    district_legislators.map do |l|
      ul = UserLegislator.find_or_initialize_by(
        user: @user,
        legislator: l
      )
      unless ul.active
        ul.active = true
      end
      ul.save!
    end
  end

  private

  def districts
    @districts ||= SwayGeocode.build(sway_locale, address).districts
  end

  sig { returns(T::Array[Legislator]) }
  def district_legislators
    if @legislators.blank?
      Rails.logger.info("SwayRegistrationService.district_legislators - no Legislators in SwayLocale: #{@sway_locale.name}")
      puts("SwayRegistrationService.district_legislators - no Legislators in SwayLocale: #{@sway_locale.name}")
      return []
    end

    dls = T.let(@legislators, T::Array[Legislator]).filter do |legislator|
      legislator.active && (legislator.district.region_code == address.region_code) && districts.include?(legislator.district.number)
    end
    if dls.blank?
      Rails.logger.info("SwayRegistrationService.district_legislators - no district_legislators found in SwayLocale: #{@sway_locale.name}")
      puts("SwayRegistrationService.district_legislators - no district_legislators found in SwayLocale: #{@sway_locale.name}")
    else
      Rails.logger.info("SwayRegistrationService.district_legislators - #{dls.length} district_legislators found in SwayLocale: #{@sway_locale.name}")
      puts("SwayRegistrationService.district_legislators - #{dls.length} district_legislators found in SwayLocale: #{@sway_locale.name}")
    end
    dls
  end

  def create_invite
    return if @invited_by_id.blank?

    u = User.find_by(id: @invited_by_id)
    return if u.blank?

    Invite.find_or_create_by!(inviter: u, invitee: @user)
  end
end
