require "faraday"

module SwayGeocode
  # @lat: [[census-and-geocode-implementation-notes#Why ServiceUnavailableError wraps upstream HTTP failures]]
  class ServiceUnavailableError < StandardError; end

  # @lat: [[census-and-geocode-implementation-notes#Why SwayGeocode::Congress and SwayGeocode::Local are plain nested classes]]
  def self.build(sway_locale, address)
    sway_locale.congress? ? Congress.new(address) : Local.new(sway_locale, address)
  end

  class Congress
    def initialize(address)
      @address = address
    end

    def districts
      d = Census::Congress.new(@address).congressional_district
      d.present? ? [0, d.to_i] : []
    rescue Faraday::Error => e
      raise SwayGeocode::ServiceUnavailableError,
        "Census TIGERweb geocoding is unavailable: #{e.message}"
    end
  end

  class Local
    def initialize(sway_locale, address)
      @sway_locale = sway_locale
      @address = address
    end

    def districts
      load_feature

      return [] if @feature.blank?

      [0, @feature.district.to_i]
    end

    private

    def load_feature
      @feature ||= load_geojson_for_locale&.find do |f|
        f.geometry.contains?(@address.to_cartesian)
      end
    end

    def load_geojson_for_locale
      @sway_locale.load_geojson
    end
  end
end
