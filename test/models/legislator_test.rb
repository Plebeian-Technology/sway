# typed: strict
# == Schema Information
#
# Table name: legislators
#
#  id          :integer          not null, primary key
#  external_id :string           not null
#  active      :boolean          not null
#  link        :string
#  email       :string
#  title       :string
#  first_name  :string           not null
#  last_name   :string           not null
#  phone       :string
#  fax         :string
#  party       :string           not null
#  photo_url   :string
#  address_id  :integer          not null
#  district_id :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  twitter     :string
#
require "test_helper"

class LegislatorTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
