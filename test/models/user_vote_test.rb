# typed: strict
# == Schema Information
#
# Table name: user_votes
#
#  id         :integer          not null, primary key
#  user_id    :integer          not null
#  bill_id    :integer          not null
#  support    :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
require "test_helper"

class UserVoteTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
