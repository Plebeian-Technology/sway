# typed: strict
# == Schema Information
#
# Table name: user_legislator_scores
#
#  id                         :integer          not null, primary key
#  user_legislator_id         :integer          not null
#  count_agreed               :integer          default(0), not null
#  count_disagreed            :integer          default(0), not null
#  count_no_legislator_vote   :integer          default(0), not null
#  count_legislator_abstained :integer          default(0), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#
require "test_helper"

class UserLegislatorScoreTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
