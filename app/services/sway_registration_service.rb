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

  sig { params(user: User, address: Address, sway_locale: SwayLocale).void }
  def initialize(user, address, sway_locale)
    @user = user
    @address = address
    @sway_locale = sway_locale
    @legislators = sway_locale.legislators

    @feature = T.let(nil, T.nilable(RGeo::GeoJSON::Feature))
    @districts = nil
  end

  sig { returns(T::Array[UserLegislator]) }
  def run
    uls = user_legislators.map do |l|
      UserLegislator.find_or_create_by!(
        user: @user,
        legislator: l
      )
    end

    return uls unless uls.present?

    @user.is_registration_complete = true
    @user.save!

    uls
  end

  private

  def districts
    @districts ||= SwayGeocode.build(sway_locale, address).districts
  end

  sig { returns(T::Array[Legislator]) }
  def user_legislators
    return [] unless @legislators.present?

    T.let(@legislators, T::Array[Legislator]).filter do |legislator|
      (legislator.district.region_code == address.region_code) && districts.include?(legislator.district.number)
    end
  end
end
