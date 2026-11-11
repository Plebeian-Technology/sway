# == Schema Information
#
# Table name: legislator_terms
# Database name: primary
#
#  id              :integer          not null, primary key
#  began_on        :date
#  began_on_source :string
#  ended_on        :date
#  ended_on_source :string
#  term_end_year   :integer          not null
#  term_start_year :integer          not null
#  title           :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  district_id     :integer          not null
#  legislator_id   :integer          not null
#  seat_id         :integer
#
# Indexes
#
#  index_legislator_terms_on_district_id                        (district_id)
#  index_legislator_terms_on_legislator_id_and_term_start_year  (legislator_id,term_start_year) UNIQUE
#  index_legislator_terms_on_seat_id                            (seat_id)
#
# Foreign Keys
#
#  district_id    (district_id => districts.id)
#  legislator_id  (legislator_id => legislators.id)
#  seat_id        (seat_id => seats.id)
#
FactoryBot.define do
  factory :legislator_term do
    legislator
    district
    title { "Rep." }
    # Defaults to Congress: the 119th Congress first met in January 2025.
    term_start_year { 2025 }
    term_end_year { 2027 }

    trait :prior_term do
      term_start_year { 2023 }
      term_end_year { 2025 }
    end
  end
end
