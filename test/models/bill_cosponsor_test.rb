# typed: strict
# == Schema Information
#
# Table name: bill_cosponsors
#
#  id            :bigint           not null, primary key
#  legislator_id :bigint           not null
#  bill_id       :bigint           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
require "test_helper"

class BillCosponsorTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
