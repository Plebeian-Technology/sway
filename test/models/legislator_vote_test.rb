# typed: strict
# == Schema Information
#
# Table name: legislator_votes
#
#  id            :bigint           not null, primary key
#  legislator_id :bigint           not null
#  bill_id       :bigint           not null
#  support       :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
require "test_helper"

class LegislatorVoteTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
