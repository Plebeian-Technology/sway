# typed: strict
# == Schema Information
#
# Table name: sway_locales
#
#  id         :bigint           not null, primary key
#  city       :string
#  state      :string
#  country    :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
require "test_helper"

class SwayLocaleTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
