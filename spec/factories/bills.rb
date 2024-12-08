# == Schema Information
#
# Table name: bills
#
#  id                         :integer          not null, primary key
#  active                     :boolean
#  audio_bucket_path          :string
#  audio_by_line              :string
#  category                   :string           not null
#  chamber                    :string           not null
#  external_version           :string
#  house_vote_date_time_utc   :datetime
#  introduced_date_time_utc   :datetime         not null
#  level                      :string           not null
#  link                       :string
#  scheduled_release_date_utc :date
#  senate_vote_date_time_utc  :datetime
#  status                     :string
#  summary                    :text
#  title                      :string           not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  external_id                :string           not null
#  legislator_id              :integer          not null
#  sway_locale_id             :integer          not null
#
# Indexes
#
#  index_bills_on_external_id_and_sway_locale_id                 (external_id,sway_locale_id) UNIQUE
#  index_bills_on_legislator_id                                  (legislator_id)
#  index_bills_on_scheduled_release_date_utc_and_sway_locale_id  (scheduled_release_date_utc,sway_locale_id) UNIQUE
#  index_bills_on_sway_locale_id                                 (sway_locale_id)
#
# Foreign Keys
#
#  legislator_id   (legislator_id => legislators.id)
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
FactoryBot.define do
  factory :bill do
    external_id { Faker::Color.color_name }
    title { "#{Faker::Color.color_name} - #{Time.now.utc.to_formatted_s(:number)}" }
    chamber { "council" }
    introduced_date_time_utc { Time.now.utc }
    level { "local" }
    link { "https://example.com/#{Faker::Color.color_name}" }
    category { Faker::CryptoCoin.coin_name }
    active { true }
    status { Bill::Status::COMMITTEE }
    sway_locale
    legislator

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
