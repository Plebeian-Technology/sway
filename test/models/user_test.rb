# typed: strict
# == Schema Information
#
# Table name: users
#
#  id                       :integer          not null, primary key
#  email                    :string
#  is_email_verified        :boolean
#  phone                    :string
#  is_phone_verified        :boolean
#  is_registration_complete :boolean
#  is_registered_to_vote    :boolean
#  is_admin                 :boolean          default(FALSE)
#  webauthn_id              :string
#  sign_in_count            :integer          default(0), not null
#  current_sign_in_at       :datetime
#  last_sign_in_at          :datetime
#  current_sign_in_ip       :string
#  last_sign_in_ip          :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
require "test_helper"

class UserTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
