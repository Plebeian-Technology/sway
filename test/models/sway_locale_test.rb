# typed: strict
# == Schema Information
#
# Table name: sway_locales
#
#  id         :integer          not null, primary key
#  city       :string           not null
#  state      :string           not null
#  country    :string           default("United States"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
require "test_helper"

class SwayLocaleTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
