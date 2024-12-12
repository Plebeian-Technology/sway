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
    uls = district_legislators.map do |l|
      UserLegislator.find_or_create_by!(
        user: @user,
        legislator: l
      )
    end

    return uls if uls.blank?

    @user.is_registration_complete = true
    @user.save!

    create_invite

    uls
  end

  private

  def districts
    @districts ||= SwayGeocode.build(sway_locale, address).districts
  end

  sig { returns(T::Array[Legislator]) }
  def district_legislators
    return [] if @legislators.blank?

    T.let(@legislators, T::Array[Legislator]).filter do |legislator|
      (legislator.district.region_code == address.region_code) && districts.include?(legislator.district.number)
    end
  end

  def create_invite
    return if @invited_by_id.blank?

    u = User.find_by(id: @invited_by_id)
    return if u.blank?

    Invite.find_or_create_by!(inviter: u, invitee: @user)
  end
end
