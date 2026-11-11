# frozen_string_literal: true

# == Schema Information
#
# Table name: organization_follows
# Database name: primary
#
#  id                       :integer          not null, primary key
#  notification_cadence     :integer          default("every_change"), not null
#  notify_on_new_position   :boolean          default(TRUE), not null
#  notify_on_summary_change :boolean          default(TRUE), not null
#  notify_on_support_change :boolean          default(TRUE), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  organization_id          :integer          not null
#  user_id                  :integer          not null
#
# Indexes
#
#  idx_organization_follows_on_user_and_organization  (user_id,organization_id) UNIQUE
#  index_organization_follows_on_organization_id      (organization_id)
#
# Foreign Keys
#
#  organization_id  (organization_id => organizations.id)
#  user_id          (user_id => users.id)
#
# @lat: [[organization-follow-notification-design#Why seeding preferences lives on the model, not the controller]]
class OrganizationFollow < ApplicationRecord
  belongs_to :user
  belongs_to :organization

  validates :user_id, uniqueness: {scope: :organization_id}

  # @lat: [[organization-follow-notification-design#Why the cadence integers are locked]]
  enum :notification_cadence,
    {every_change: 0, daily: 1, weekly: 2},
    default: :every_change

  alias_attribute :organization_position_notification_cadence, :notification_cadence

  # @lat: [[organization-follow-notification-design#Why an unknown change type fails closed]]
  def muted_for?(change_type)
    case change_type
    when :new_position then !notify_on_new_position
    when :support_change then !notify_on_support_change
    when :summary_change then !notify_on_summary_change
    else true
    end
  end

  # @lat: [[organization-follow-notification-design#Why seeding preferences lives on the model, not the controller]]
  def self.seed_attrs_from(user)
    {
      notification_cadence: user.org_position_cadence_default,
      notify_on_new_position: user.notify_on_new_position_default,
      notify_on_support_change: user.notify_on_support_change_default,
      notify_on_summary_change: user.notify_on_summary_change_default
    }
  end
end
