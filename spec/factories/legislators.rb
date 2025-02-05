# == Schema Information
#
# Table name: legislators
#
#  id          :integer          not null, primary key
#  active      :boolean          not null
#  email       :string
#  fax         :string
#  first_name  :string           not null
#  last_name   :string           not null
#  link        :string
#  party       :string           not null
#  phone       :string
#  photo_url   :string
#  title       :string
#  twitter     :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  district_id :integer          not null
#  external_id :string           not null
#
# Indexes
#
#  index_legislators_on_district_id  (district_id)
#
# Foreign Keys
#
#  district_id  (district_id => districts.id)
#
FactoryBot.define do
  factory :legislator do
    external_id { Faker::Color.color_name }
    active { true }
    first_name { Faker::Color.color_name }
    last_name { Faker::Color.color_name }
    party { "D" }
    district

    initialize_with { new({external_id:, active:, first_name:, last_name:, party:, district:}) }
  end
end
