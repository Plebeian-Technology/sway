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
require "test_helper"

class BillScoreDistrictTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
