# typed: strict
# == Schema Information
#
# Table name: user_districts
#
#  id          :integer          not null, primary key
#  district_id :integer          not null
#  user_id     :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
require "test_helper"

class UserDistrictTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
