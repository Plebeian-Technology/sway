# typed: true

module SwayGeocode
  class << self
    extend T::Sig

    sig { params(sway_locale: SwayLocale, address: Address).returns(T.any(Congress, Local)) }
    def build(sway_locale, address)
      sway_locale.congress? ? Congress.new(address) : Local.new(sway_locale, address)
    end

    class Congress
      extend T::Sig
      include Census

      def initialize(address)
        @address = T.let(address, Address)
      end

      sig { returns(T::Array[Integer]) }
      def districts
        d = Census::Congress.new(@address).congressional_district
        d.present? ? [0, d.to_i] : []
      end
    end

    class Local
      extend T::Sig

      def initialize(sway_locale, address)
        @sway_locale = T.let(sway_locale, SwayLocale)
        @address = T.let(address, Address)
      end

      sig { returns(T::Array[Integer]) }
      def districts
        load_feature

        return [] unless @feature.present?

        [0, T.cast(@feature, RGeo::GeoJSON::Feature).district.to_i]
      end

      private

      sig { returns(T.nilable(RGeo::GeoJSON::Feature)) }
      def load_feature
        @feature ||= T.let(load_geojson_for_locale&.find do |f|
          T.let(f, RGeo::GeoJSON::Feature).geometry.contains?(@address.to_cartesian)
        end, T.nilable(RGeo::GeoJSON::Feature))
      end

      sig { returns(T.nilable(RGeo::GeoJSON::FeatureCollection)) }
      def load_geojson_for_locale
        @sway_locale.load_geojson
      end
    end
  end
end
