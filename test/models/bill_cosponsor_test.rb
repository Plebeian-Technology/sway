# typed: strict
# == Schema Information
#
# Table name: bill_cosponsors
#
#  id            :integer          not null, primary key
#  legislator_id :integer          not null
#  bill_id       :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
require "test_helper"

class BillCosponsorTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
