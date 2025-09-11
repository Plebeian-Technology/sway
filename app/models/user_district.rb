# frozen_string_literal: true
# typed: strict

# == Schema Information
#
# Table name: user_districts
#
#  id          :integer          not null, primary key
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  district_id :integer          not null
#  user_id     :integer          not null
#
# Indexes
#
#  index_user_districts_on_district_id  (district_id)
#  index_user_districts_on_user_id      (user_id)
#
# Foreign Keys
#
#  district_id  (district_id => districts.id)
#  user_id      (user_id => users.id)
#
class UserDistrict < ApplicationRecord
  belongs_to :district
  belongs_to :user
end
