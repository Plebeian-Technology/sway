# frozen_string_literal: true

# @lat: [[address-normalization]]
class NormalizeAddressService
  class << self
    def call(target = nil, **attributes)
      if target.respond_to?(:city=) && target.respond_to?(:region_code=)
        new(target).call
      else
        attrs = if target.is_a?(Hash)
          target.symbolize_keys.merge(attributes)
        else
          attributes
        end
        normalize_attributes(attrs)
      end
    end

    def normalize_attributes(attrs)
      normalized = attrs.dup.symbolize_keys

      region = normalized[:region_code] || normalized[:state]
      if region.present?
        normalized_region = normalize_region_code(region)
        normalized[:region_code] = normalized_region if normalized.key?(:region_code)
        normalized[:state] = normalized_region if normalized.key?(:state)
        normalized[:region_code] ||= normalized_region
      end

      if normalized.key?(:city)
        normalized[:city] = normalize_city(normalized[:city])
      end

      normalized
    end

    def normalize_region_code(region_code)
      return region_code if region_code.blank?

      str = region_code.to_s.strip
      return region_code if str.blank?

      code = if str.length > 2
        RegionUtil.from_region_name_to_region_code(str) || str
      else
        str
      end

      code.present? ? code.upcase : code
    end

    def normalize_city(city)
      return city if city.blank?

      city.to_s.strip.titleize
    end
  end

  def initialize(address)
    @address = address
  end

  def call
    if @address.region_code.present?
      @address.region_code = self.class.normalize_region_code(@address.region_code)
    end
    if @address.city.present?
      @address.city = self.class.normalize_city(@address.city)
    end
    @address
  end
end
