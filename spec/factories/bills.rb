# == Schema Information
#
# Table name: bills
# Database name: primary
#
#  id                         :integer          not null, primary key
#  active                     :boolean
#  amendment_source           :string
#  archived_at                :datetime
#  audio_bucket_path          :string
#  audio_by_line              :string
#  category                   :string           default(""), not null
#  chamber                    :string           not null
#  external_version           :string
#  extracted_text             :text
#  house_vote_date_time_utc   :datetime
#  introduced_date_time_utc   :datetime         not null
#  last_seeded_at             :datetime
#  link                       :string
#  parsed_at                  :datetime
#  parsing_target             :string
#  parsing_target_log         :string
#  scheduled_release_date_utc :date
#  senate_vote_date_time_utc  :datetime
#  status                     :string
#  summary                    :text
#  title                      :string           not null
#  vote_import_state          :string           default("unimported"), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  external_id                :string           not null
#  legislative_session_id     :integer
#  legislator_id              :integer          not null
#  sway_locale_id             :integer          not null
#
# Indexes
#
#  idx_bills_on_amendment_source                                 (amendment_source)
#  idx_bills_on_parsing_target                                   (parsing_target)
#  index_bills_on_external_id_and_sway_locale_id                 (external_id,sway_locale_id) UNIQUE
#  index_bills_on_legislative_session_id                         (legislative_session_id)
#  index_bills_on_legislator_id                                  (legislator_id)
#  index_bills_on_locale_and_release_date                        (sway_locale_id,scheduled_release_date_utc)
#  index_bills_on_scheduled_release_date_utc_and_sway_locale_id  (scheduled_release_date_utc,sway_locale_id) UNIQUE
#  index_bills_on_sway_locale_id                                 (sway_locale_id)
#  index_bills_on_sway_locale_id_and_archived_at                 (sway_locale_id,archived_at)
#  index_bills_on_vote_import_state                              (vote_import_state)
#
# Foreign Keys
#
#  legislative_session_id  (legislative_session_id => legislative_sessions.id) ON DELETE => nullify
#  legislator_id           (legislator_id => legislators.id)
#  sway_locale_id          (sway_locale_id => sway_locales.id)
#
FactoryBot.define do
  factory :bill do
    # @lat: [[bill-external-id-validation#The bill factory's external_id fixture]]
    sequence(:external_id) { |n| "bill-#{n}-#{Faker::Color.color_name.parameterize}" }
    title do
      "#{Faker::Color.color_name} - #{Time.zone.now.to_fs(:number)}"
    end
    chamber { "council" }
    introduced_date_time_utc { 1.month.ago }
    sequence(:scheduled_release_date_utc) { |n| n.days.ago.to_date }
    sequence(:link) { |n| "https://example.com/bills/#{n}" }
    category { Faker::CryptoCoin.coin_name }
    active { true }
    status { Bill::Status::COMMITTEE }
    summary { Faker::Lorem.paragraph }
    sway_locale
    legislator
    add_attribute(:legislative_session) do
      sway_locale&.current_legislative_session ||
        association(:legislative_session, :active, sway_locale:)
    end

    initialize_with do
      new(
        {
          external_id:,
          title:,
          chamber:,
          introduced_date_time_utc:,
          category:,
          legislator:,
          sway_locale:
        }
      )
    end

    trait :bill_of_the_month do
      scheduled_release_date_utc { Time.zone.today }
    end

    trait :in_active_session do
      add_attribute(:legislative_session) do
        sway_locale&.current_legislative_session ||
          association(:legislative_session, :active, sway_locale:)
      end
    end

    trait :without_session do
      add_attribute(:legislative_session) { nil }
    end
  end
end
