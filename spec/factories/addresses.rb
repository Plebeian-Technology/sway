# == Schema Information
#
# Table name: addresses
# Database name: primary
#
#  id                      :integer          not null, primary key
#  city                    :string           not null
#  country                 :string           default("US"), not null
#  geocode_abandoned_at    :datetime
#  geocode_next_attempt_at :datetime
#  latitude                :string
#  longitude               :string
#  normalized_key          :string
#  place_types             :json             not null
#  postal_code             :string           not null
#  region_code             :string           not null
#  street                  :string           not null
#  street2                 :string
#  street3                 :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_addresses_on_normalized_key  (normalized_key)
#
FactoryBot.define do
  factory :address do
    street { Faker::Address.street_address(include_secondary: false) }
    # @lat: [[sway-locale-factory-design#Why the address factory hardcodes a real city]]
    city { "Baltimore" }
    region_code { "MD" }
    postal_code { Faker::Address.postcode }

    initialize_with { new({street:, city:, region_code:, postal_code:}) }
  end
end
