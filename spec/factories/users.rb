# == Schema Information
#
# Table name: users
#
#  id                       :integer          not null, primary key
#  current_sign_in_at       :datetime
#  current_sign_in_ip       :string
#  email                    :string
#  full_name                :string
#  is_admin                 :boolean          default(FALSE)
#  is_email_verified        :boolean
#  is_phone_verified        :boolean
#  is_registered_to_vote    :boolean
#  is_registration_complete :boolean
#  last_sign_in_at          :datetime
#  last_sign_in_ip          :string
#  phone                    :string
#  sign_in_count            :integer          default(0), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  webauthn_id              :string
#
# Indexes
#
#  index_users_on_email        (email) UNIQUE
#  index_users_on_phone        (phone) UNIQUE
#  index_users_on_webauthn_id  (webauthn_id) UNIQUE
#
FactoryBot.define do
    factory :user do
        phone { Faker::PhoneNumber.cell_phone.remove_non_digits }
        is_registration_complete { true }

        initialize_with { new({ phone:, is_registration_complete: }) }
    end
end
