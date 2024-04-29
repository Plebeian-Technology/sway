# typed: strict
# == Schema Information
#
# Table name: votes
#
#  id           :integer          not null, primary key
#  voted_on_utc :datetime
#  bill_id      :integer          not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
require "test_helper"

class VoteTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
