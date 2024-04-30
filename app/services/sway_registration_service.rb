# typed: true

# frozen_string_literal: true

class SwayRegistrationService
  extend T::Sig

  sig { returns(Address) }
  attr_reader :address

  sig { params(user: User, address: Address).void }
  def initialize(user, address)
    @current_user = user
    @address = address

    @feature = T.let(nil, T.nilable(RGeo::GeoJSON::Feature))
    @legislators = T.let([], T::Array[Legislator])
  end

  sig { returns(T::Array[UserLegislator]) }
  def build_user_legislators
    legislators.map do |l|
      u = UserLegislator.new(
        user: @current_user,
        legislator: l
      )
      u.save!
      u
    end
  end

  private

  sig { returns(T::Array[Legislator]) }
  def legislators
    districts = [0, nil, feature.district]

    if @legislators.empty?
      @legislators = address.sway_locale.legislators.filter do |legislator|
        districts.include?(legislator.district&.number)
      end
    end

    @legislators
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
