# frozen_string_literal: true

# == Schema Information
#
# Table name: legislative_sessions
# Database name: primary
#
#  id             :integer          not null, primary key
#  active         :boolean          default(FALSE), not null
#  end_date       :date             not null
#  name           :string           not null
#  start_date     :date             not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  sway_locale_id :integer          not null
#
# Indexes
#
#  index_legislative_sessions_on_sway_locale_id_and_active  (sway_locale_id,active)
#  index_legislative_sessions_on_sway_locale_id_and_name    (sway_locale_id,name) UNIQUE
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
FactoryBot.define do
  factory :legislative_session do
    sway_locale
    sequence(:name) { |n| "#{n}th Legislative Session" }
    add_attribute(:start_date) { Date.new(2025, 1, 3) }
    add_attribute(:end_date) { Date.new(2027, 1, 3) }
    active { false }

    trait :active do
      active { true }
    end

    trait :prior do
      sequence(:name) { |n| "#{n}th Prior Session" }
      add_attribute(:start_date) { Date.new(2023, 1, 3) }
      add_attribute(:end_date) { Date.new(2025, 1, 3) }
      active { false }
    end
  end
end
