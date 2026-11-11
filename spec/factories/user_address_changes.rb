# frozen_string_literal: true

# == Schema Information
#
# Table name: user_address_changes
# Database name: primary
#
#  id                          :integer          not null, primary key
#  activated_district_ids      :json             not null
#  activated_legislator_ids    :json             not null
#  deactivated_district_ids    :json             not null
#  deactivated_legislator_ids  :json             not null
#  new_sway_locale_ids         :json             not null
#  previous_sway_locale_ids    :json             not null
#  prior_vote_count            :integer          default(0), not null
#  prior_voted_bill_ids        :json             not null
#  prior_voted_sway_locale_ids :json             not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  new_address_id              :integer          not null
#  previous_address_id         :integer          not null
#  user_id                     :integer          not null
#
# Indexes
#
#  index_user_address_changes_on_created_at              (created_at)
#  index_user_address_changes_on_new_address_id          (new_address_id)
#  index_user_address_changes_on_previous_address_id     (previous_address_id)
#  index_user_address_changes_on_user_id                 (user_id)
#  index_user_address_changes_on_user_id_and_created_at  (user_id,created_at)
#
# Foreign Keys
#
#  user_id  (user_id => users.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :user_address_change do
    user
    add_attribute(:previous_address) { association(:address) }
    add_attribute(:new_address) { association(:address) }
    add_attribute(:deactivated_legislator_ids) { [] }
    add_attribute(:activated_legislator_ids) { [] }
    add_attribute(:deactivated_district_ids) { [] }
    add_attribute(:activated_district_ids) { [] }
    add_attribute(:previous_sway_locale_ids) { [] }
    add_attribute(:new_sway_locale_ids) { [] }
    add_attribute(:prior_vote_count) { 0 }
    add_attribute(:prior_voted_bill_ids) { [] }
    add_attribute(:prior_voted_sway_locale_ids) { [] }
  end
end
