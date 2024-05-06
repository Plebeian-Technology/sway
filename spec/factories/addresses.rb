# == Schema Information
#
# Table name: addresses
#
#  id          :integer          not null, primary key
#  street      :string           not null
#  street2     :string
#  street3     :string
#  city        :string           not null
#  region_code :string           not null
#  postal_code :string           not null
#  country     :string           default("US"), not null
#  latitude    :float
#  longitude   :float
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
FactoryBot.define do
  factory :address do
    street { Faker::Address.street_address(include_secondary: false) }
    city { Faker::Address.city }
    region_code { Faker::Address.state_abbr }
    postal_code { Faker::Address.postcode }

    initialize_with { new({ street:, city:, region_code:, postal_code: }) }
  end
end
