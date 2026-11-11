# == Schema Information
#
# Table name: legislators
# Database name: primary
#
#  id             :integer          not null, primary key
#  email          :string
#  fax            :string
#  first_name     :string           not null
#  last_name      :string           not null
#  last_seeded_at :datetime
#  link           :string
#  party          :string           not null
#  phone          :string
#  photo_url      :string
#  twitter        :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  external_id    :string           not null
#  sway_locale_id :integer          not null
#
# Indexes
#
#  index_legislators_on_external_id                     (external_id)
#  index_legislators_on_sway_locale_id                  (sway_locale_id)
#  index_legislators_on_sway_locale_id_and_external_id  (sway_locale_id,external_id) UNIQUE
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
FactoryBot.define do
  factory :legislator do
    # @lat: [[legislator-factory-district-transient-design#Why external_id uses a plain sequence, not Faker::Color.color_name]]
    sequence(:external_id) { |n| "ext-#{n}" }
    first_name { Faker::Color.color_name }
    last_name { Faker::Color.color_name }
    party { "D" }
    sway_locale { district.sway_locale }

    # @lat: [[legislator-factory-district-transient-design#district must stay transient]]
    transient do
      # @lat: [[legislator-factory-district-transient-design#Why the association names strategy: :create explicitly]]
      district { association :district, strategy: :create }
      active { true }
      title { nil }
    end

    initialize_with do
      new({
        external_id:,
        first_name:,
        last_name:,
        party:,
        sway_locale:
      })
    end
  end
end
