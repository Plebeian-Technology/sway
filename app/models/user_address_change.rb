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
class UserAddressChange < ApplicationRecord
  ID_LIST_COLUMNS = %i[
    deactivated_legislator_ids
    activated_legislator_ids
    deactivated_district_ids
    activated_district_ids
    previous_sway_locale_ids
    new_sway_locale_ids
    prior_voted_bill_ids
    prior_voted_sway_locale_ids
  ].freeze

  belongs_to :user
  belongs_to :previous_address, class_name: "Address", optional: true
  belongs_to :new_address, class_name: "Address", optional: true

  before_validation :normalize_id_lists

  validates :previous_address_id, :new_address_id, presence: true
  validates :prior_vote_count, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  validate :addresses_must_differ

  def cross_district?
    (deactivated_district_ids.any? || activated_district_ids.any?) &&
      deactivated_district_ids.sort != activated_district_ids.sort
  end

  def cross_sway_locale?
    (previous_sway_locale_ids.any? || new_sway_locale_ids.any?) &&
      previous_sway_locale_ids.sort != new_sway_locale_ids.sort
  end

  def voted_before_switch?
    prior_vote_count.positive?
  end

  private

  def normalize_id_lists
    ID_LIST_COLUMNS.each do |column|
      raw = public_send(column)
      normalized = Array(raw).filter_map { |v| Integer(v, exception: false) }.uniq.sort
      public_send(:"#{column}=", normalized)
    end
  end

  def addresses_must_differ
    return if previous_address_id.blank? || new_address_id.blank?
    return unless previous_address_id == new_address_id

    errors.add(:new_address_id, "must be different from previous address")
  end
end
