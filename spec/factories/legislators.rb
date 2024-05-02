# == Schema Information
#
# Table name: legislators
#
#  id          :integer          not null, primary key
#  external_id :string           not null
#  active      :boolean          not null
#  link        :string
#  email       :string
#  title       :string
#  first_name  :string           not null
#  last_name   :string           not null
#  phone       :string
#  fax         :string
#  party       :string           not null
#  photo_url   :string
#  address_id  :integer          not null
#  district_id :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  twitter     :string
#
FactoryBot.define do
  factory :legislator do
    external_id { Faker::Color.color_name }
    active { true }
    first_name { Faker::Color.color_name }
    last_name { Faker::Color.color_name }
    party { 'D' }
    address
    district

    initialize_with { new({ external_id:, active:, first_name:, last_name:, party:, address:, district: }) }
  end
end
