# == Schema Information
#
# Table name: sway_locales
#
#  id                         :integer          not null, primary key
#  city                       :string           not null
#  state                      :string           not null
#  country                    :string           default("United States"), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  current_session_start_date :date
#  time_zone                  :string
#  icon_path                  :string
#
FactoryBot.define do
  factory :sway_locale do
    city { Faker::Address.city }
    state { Faker::Address.state_abbr }
    country { Faker::Address.country }
    current_session_start_date { Date.today - 1.year }
    time_zone { 'Etc/UTC' }
    icon_path { 'logo.svg' }

    initialize_with { new({ city:, state:, country: }) }
  end
end
