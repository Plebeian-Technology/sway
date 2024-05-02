# typed: strict
# == Schema Information
#
# Table name: legislator_votes
#
#  id            :integer          not null, primary key
#  legislator_id :integer          not null
#  bill_id       :integer          not null
#  support       :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
require "test_helper"

class LegislatorVoteTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
