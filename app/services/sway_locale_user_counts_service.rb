# frozen_string_literal: true

# @lat: [[locale-user-counts#Why the count matches against existing locale rows]]
class SwayLocaleUserCountsService
  def self.by_sway_locale_id
    new.by_sway_locale_id
  end

  def by_sway_locale_id
    counts = Hash.new(0)

    address_components_by_sway_locale_id.each do |sway_locale_id, components|
      counts[sway_locale_id] = user_count_for(components)
    end

    counts
  end

  private

  # @lat: [[locale-user-counts#Why only the distinct address components are read]]
  def address_components_by_sway_locale_id
    components_by_sway_locale_id = Hash.new { |hash, key| hash[key] = [] }

    address_components_in_use.each do |city, region_code, country|
      Address.sway_locale_attribute_sets_for(city:, region_code:, country:).each do |attrs|
        sway_locale = sway_locale_for_address(attrs)
        components_by_sway_locale_id[sway_locale.id] << {city:, region_code:, country:} if sway_locale
      end
    end

    components_by_sway_locale_id
  end

  def address_components_in_use
    UserAddress
      .joins(:address)
      .distinct
      .pluck("addresses.city", "addresses.region_code", "addresses.country")
  end

  # @lat: [[locale-user-counts#Why the count is asked locale by locale]]
  def user_count_for(components)
    UserAddress.where(address: addresses_with(components)).distinct.count(:user_id)
  end

  def addresses_with(components)
    components.map { |attrs| Address.where(**attrs) }.reduce(:or)
  end

  def sway_locales_by_key
    @sway_locales_by_key ||= SwayLocale.all.index_by do |sway_locale|
      [sway_locale.city, sway_locale.state, sway_locale.country]
    end
  end

  def sway_locale_for_address(attrs)
    normalized = SwayLocale.normalize_attributes(attrs)
    city = normalized[:city]
    state = normalized[:state]
    country = normalized[:country]
    return unless city && state && country

    sway_locales_by_key[[city, state, country]]
  end
end
