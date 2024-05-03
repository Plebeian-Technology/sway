# == Schema Information
#
# Table name: districts
#
#  id             :integer          not null, primary key
#  name           :string           not null
#  sway_locale_id :integer          not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
FactoryBot.define do
  factory :district do
    name { "#{sway_locale.region_code}0" }
    sway_locale

    initialize_with { new({ name:, sway_locale: }) }
  end
end
