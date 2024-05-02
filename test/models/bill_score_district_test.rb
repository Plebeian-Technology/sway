# typed: strict
# == Schema Information
#
# Table name: bill_score_districts
#
#  id            :integer          not null, primary key
#  bill_score_id :integer          not null
#  district_id   :integer          not null
#  for           :integer          default(0), not null
#  against       :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
require "test_helper"

class BillScoreDistrictTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
