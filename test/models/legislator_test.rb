# == Schema Information
#
# Table name: legislators
#
#  id          :bigint           not null, primary key
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
#  address_id  :bigint           not null
#  district_id :bigint           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
require "test_helper"

class LegislatorTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
