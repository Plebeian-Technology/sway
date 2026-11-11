# == Schema Information
#
# Table name: user_districts
# Database name: primary
#
#  id          :integer          not null, primary key
#  active      :boolean          default(TRUE), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  district_id :integer          not null
#  user_id     :integer          not null
#
# Indexes
#
#  index_user_districts_on_user_id_and_district_id  (user_id,district_id) UNIQUE
#
# Foreign Keys
#
#  district_id  (district_id => districts.id)
#  user_id      (user_id => users.id)
#
FactoryBot.define do
  factory :user_district do
    user
    district
    active { true }
  end
end
