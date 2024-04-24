# typed: strict
# == Schema Information
#
# Table name: user_districts
#
#  id          :bigint           not null, primary key
#  district_id :bigint           not null
#  user_id     :bigint           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
require "test_helper"

class UserDistrictTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
