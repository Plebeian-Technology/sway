# == Schema Information
#
# Table name: user_organization_membership_invites
# Database name: primary
#
#  id              :integer          not null, primary key
#  accepted_at     :datetime
#  expires_at      :datetime
#  invitee_email   :string           not null
#  revoked_at      :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  invitee_user_id :integer
#  inviter_id      :integer          not null
#  organization_id :integer          not null
#
# Indexes
#
#  index_user_organization_membership_invites_on_accepted_at      (accepted_at)
#  index_user_organization_membership_invites_on_expires_at       (expires_at)
#  index_user_organization_membership_invites_on_invitee_user_id  (invitee_user_id)
#  index_user_organization_membership_invites_on_inviter_id       (inviter_id)
#  index_user_organization_membership_invites_on_organization_id  (organization_id)
#  index_user_organization_membership_invites_on_revoked_at       (revoked_at)
#
# Foreign Keys
#
#  invitee_user_id  (invitee_user_id => users.id)
#  inviter_id       (inviter_id => users.id)
#  organization_id  (organization_id => organizations.id)
#
class UserOrganizationMembershipInvite < ApplicationRecord
  belongs_to :inviter, class_name: "User"
  belongs_to :organization
  belongs_to :invitee_user, class_name: "User", optional: true

  normalizes :invitee_email, with: ->(e) { e.to_s.strip.downcase }

  before_create :set_default_expires_at

  validate :no_active_duplicate_invite, on: :create

  validates :invitee_email, presence: true

  # @lat: [[membership-invite-accept-flow#Why UserOrganizationMembershipInvite derives status from timestamps instead of storing a state column]]
  def status
    return :accepted if accepted_at.present?
    return :revoked if revoked_at.present?
    return :expired if expires_at.present? && Time.current > expires_at

    :pending
  end

  private

  def set_default_expires_at
    self.expires_at ||= (created_at || Time.current) + 14.days
  end

  def no_active_duplicate_invite
    return if invitee_email.blank? || organization_id.blank?

    duplicate_exists = self.class
      .where(invitee_email:, organization_id:, accepted_at: nil, revoked_at: nil)
      .where("expires_at IS NULL OR expires_at > ?", Time.current)
      .where.not(id: id)
      .exists?

    if duplicate_exists
      errors.add(
        :invitee_email,
        "already has an active invite to this organization. Revoke the existing invite first."
      )
    end
  end
end
