# == Schema Information
#
# Table name: sway_locales
#
#  id                         :integer          not null, primary key
#  city                       :string           not null
#  country                    :string           default("United States"), not null
#  current_session_start_date :date
#  icon_path                  :string
#  latest_election_year       :integer          default(2024), not null
#  state                      :string           not null
#  time_zone                  :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#
# Indexes
#
#  index_sway_locales_on_city_and_state_and_country  (city,state,country) UNIQUE
#
FactoryBot.define do
    factory :sway_locale do
        city { Faker::Address.city }
        state { Faker::Address.state_abbr }
        country { Faker::Address.country }
        current_session_start_date { Time.zone.today - 1.year }
        time_zone { "Etc/UTC" }
        icon_path { "logo.svg" }

        initialize_with { new({ city:, state:, country: }) }
    end
end
