# typed: true

# frozen_string_literal: true

class SwayRegistrationService
  extend T::Sig

  sig { returns(Address) }
  attr_reader :address

  sig { params(user: User, address: Address).void }
  def initialize(user, address)
    @user = user
    @address = address
    @legislators = address.sway_locale.legislators

    @feature = T.let(nil, T.nilable(RGeo::GeoJSON::Feature))
    @districts = nil
  end

  sig { returns(T::Array[UserLegislator]) }
  def run
    user_legislators.map do |l|
      UserLegislator.find_or_create_by!(
        user: @user,
        legislator: l
      )
    end
  end

  private

  sig { returns(T::Array[Legislator]) }
  def user_legislators
    @legislators.filter do |legislator|
      districts.include?(legislator.district&.number)
    end
  end

  def districts
    @districts ||= [0, feature.district]
  end

  sig { returns(RGeo::GeoJSON::Feature) }
  def feature
    @feature ||= T.let(load_geojson_for_locale.find do |f|
      T.let(f, RGeo::GeoJSON::Feature).geometry.contains?(address.to_cartesian)
    end, T.nilable(RGeo::GeoJSON::Feature))
  end

  sig { returns(RGeo::GeoJSON::FeatureCollection) }
  def load_geojson_for_locale
    address.sway_locale.load_geojson
  end
end
