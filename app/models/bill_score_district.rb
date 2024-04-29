# typed: strict
# == Schema Information
#
# Table name: bill_score_districts
#
#  id            :integer          not null, primary key
#  bill_score_id :integer          not null
#  district_id   :integer          not null
#  for           :integer
#  against       :integer
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class BillScoreDistrict < ApplicationRecord
  belongs_to :bill_score
  belongs_to :district
end
