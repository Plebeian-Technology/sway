# typed: strict
# == Schema Information
#
# Table name: bill_score_districts
#
#  id            :bigint           not null, primary key
#  bill_score_id :bigint           not null
#  district_id   :bigint           not null
#  for           :integer
#  against       :integer
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class BillScoreDistrict < ApplicationRecord
  belongs_to :bill_score
  belongs_to :district
end
