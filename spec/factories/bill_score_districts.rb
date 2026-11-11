# == Schema Information
#
# Table name: bill_score_districts
# Database name: primary
#
#  id            :integer          not null, primary key
#  against       :integer          default(0), not null
#  for           :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  bill_score_id :integer          not null
#  district_id   :integer          not null
#
# Indexes
#
#  index_bill_score_districts_on_bs_and_district  (bill_score_id,district_id) UNIQUE
#  index_bill_score_districts_on_district_id      (district_id)
#
# Foreign Keys
#
#  bill_score_id  (bill_score_id => bill_scores.id)
#  district_id    (district_id => districts.id)
#
FactoryBot.define do
  factory :bill_score_district do
    bill_score
    district
    against { 0 }
    add_attribute(:for) { 0 }
  end
end
