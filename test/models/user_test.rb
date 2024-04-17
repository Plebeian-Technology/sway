# == Schema Information
#
# Table name: users
#
#  id                       :bigint           not null, primary key
#  password_bcrypt          :string
#  email                    :string
#  is_email_verified        :boolean
#  phone                    :string
#  is_phone_verified        :boolean
#  is_registration_complete :boolean
#  is_registered_to_vote    :boolean
#  is_admin                 :boolean          default(FALSE)
#  last_login_utc           :datetime
#  address_id               :bigint           not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
require "test_helper"

class UserTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
