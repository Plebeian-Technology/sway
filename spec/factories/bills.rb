# == Schema Information
#
# Table name: bills
#
#  id                        :integer          not null, primary key
#  external_id               :string           not null
#  external_version          :string
#  title                     :string           not null
#  link                      :string
#  chamber                   :string           not null
#  introduced_date_time_utc  :datetime         not null
#  house_vote_date_time_utc  :datetime
#  senate_vote_date_time_utc :datetime
#  level                     :string           not null
#  category                  :string           not null
#  summary                   :text
#  legislator_id             :integer          not null
#  sway_locale_id            :integer          not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  status                    :string
#  active                    :boolean
#  audio_bucket_path         :string
#  audio_by_line             :string
#
FactoryBot.define do
  factory :bill do
    external_id { Faker::Color.color_name }
    title { "#{Faker::Color.color_name} - #{Time.now.utc.to_formatted_s(:number)}" }
    chamber { 'council' }
    introduced_date_time_utc { Time.now.utc }
    level { 'local' }
    category { Faker::CryptoCoin.coin_name }
    legislator
    sway_locale

    initialize_with do
      new({
            external_id:,
            title:,
            chamber:,
            introduced_date_time_utc:,
            level:,
            category:,
            legislator:,
            sway_locale:
          })
    end
  end
end
