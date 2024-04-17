# == Schema Information
#
# Table name: user_districts
#
#  id          :bigint           not null, primary key
#  district_id :bigint           not null
#  user_id     :bigint           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class UserDistrict < ApplicationRecord
  belongs_to :district
  belongs_to :user
end
