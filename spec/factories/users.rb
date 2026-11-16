# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id                                      :integer          not null, primary key
#  current_sign_in_at                      :datetime
#  current_sign_in_ip                      :string
#  email                                   :string
#  full_name                               :string
#  is_email_verified                       :boolean
#  is_phone_verified                       :boolean
#  is_registered_to_vote                   :boolean
#  is_registration_complete                :boolean
#  is_voter_registration_address_confirmed :boolean          default(FALSE), not null
#  last_sign_in_at                         :datetime
#  last_sign_in_ip                         :string
#  notify_on_new_position_default          :boolean          default(TRUE), not null
#  notify_on_summary_change_default        :boolean          default(TRUE), not null
#  notify_on_support_change_default        :boolean          default(TRUE), not null
#  org_position_cadence_default            :integer          default("every_change"), not null
#  pending_representative_locale_ids       :json             not null
#  phone                                   :string
#  registration_status                     :string           default("pending")
#  sign_in_count                           :integer          default(0), not null
#  sms_notifications_enabled               :boolean          default(FALSE)
#  theme                                   :string           default("neutral"), not null
#  theme_mode                              :string           default("light"), not null
#  created_at                              :datetime         not null
#  updated_at                              :datetime         not null
#  webauthn_id                             :string
#
# Indexes
#
#  index_users_on_email        (email) UNIQUE
#  index_users_on_phone        (phone) UNIQUE
#  index_users_on_webauthn_id  (webauthn_id) UNIQUE
#
FactoryBot.define do
  factory :user do
    # @lat: [[seeded-development-users#Factory users draw from the same unroutable range]]
    sequence(:phone) { |n| format("%010d", 333_555_0000 + n) }
    is_registration_complete { true }
    is_phone_verified { false }
    sms_notifications_enabled { false }

    initialize_with { new({phone:, is_registration_complete:}) }

    trait :registered do
      after(:create) do |user|
        create(:user_legislator, user: user)
        user.complete!
      end
    end

    trait :sway_admin do
      after(:create) do |user|
        # @lat: [[admin-gate-shared-examples#Admin phone overrides keep array semantics]]
        User.send(:remove_const, :ADMIN_PHONES)
        User.const_set(:ADMIN_PHONES, [user.phone])
        create(:user_legislator, user: user)
        user.complete!
      end
    end
  end
end
