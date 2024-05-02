# typed: strict
# == Schema Information
#
# Table name: bill_scores
#
#  id         :integer          not null, primary key
#  bill_id    :integer          not null
#  for        :integer          default(0), not null
#  against    :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
require "test_helper"

class BillScoreTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
