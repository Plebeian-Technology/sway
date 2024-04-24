# typed: strict
# == Schema Information
#
# Table name: passkeys
#
#  id           :bigint           not null, primary key
#  user_id      :bigint           not null
#  label        :string           not null
#  external_id  :string
#  public_key   :string
#  sign_count   :integer
#  last_used_at :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
require "test_helper"

class PasskeyTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
