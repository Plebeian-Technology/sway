# frozen_string_literal: true

class DevelopmentAccountAddressService
  SAMPLE_ADDRESS_COLUMNS = %i[
    sample_street
    sample_postal_code
    sample_latitude
    sample_longitude
  ].freeze

  class << self
    # @lat: [[address-normalized-key]]
    def resolve(sway_locale:)
      blank = SAMPLE_ADDRESS_COLUMNS.select { |column| sway_locale.public_send(column).blank? }
      unless blank.empty?
        raise "Sway locale #{sway_locale.name} carries no sample address: #{blank.join(", ")} blank"
      end

      latitude = sway_locale.sample_latitude
      longitude = sway_locale.sample_longitude
      normalized_key = Address.normalized_key_for(latitude:, longitude:)
      Address.find_by(normalized_key:) ||
        Address.create!(
          city: sway_locale.city,
          postal_code: sway_locale.sample_postal_code,
          region_code: sway_locale.region_code,
          street: sway_locale.sample_street,
          latitude:,
          longitude:,
          normalized_key:
        )
    end
  end
end
