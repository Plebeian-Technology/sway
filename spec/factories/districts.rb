# == Schema Information
#
# Table name: districts
#
#  id             :integer          not null, primary key
#  name           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  sway_locale_id :integer          not null
#
# Indexes
#
#  index_districts_on_name_and_sway_locale_id  (name,sway_locale_id) UNIQUE
#  index_districts_on_sway_locale_id           (sway_locale_id)
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
FactoryBot.define do
    factory :district do
        name { "#{sway_locale.region_code}0" }
        sway_locale

        initialize_with { new({ name:, sway_locale: }) }
    end
end
