# typed: strict
# == Schema Information
#
# Table name: bills
#
#  id                        :bigint           not null, primary key
#  external_id               :string           not null
#  external_version          :string
#  title                     :string           not null
#  link                      :string
#  chamber                   :string           not null
#  introduced_date_time_utc  :datetime         not null
#  house_vote_date_time_utc  :datetime
#  senate_vote_date_time_utc :datetime
#  level                     :string           not null
#  category                  :string           not null
#  sponsor_id                :bigint           not null
#  sway_locale_id            :bigint           not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#
require "test_helper"

class BillTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
