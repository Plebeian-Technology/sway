# frozen_string_literal: true

# == Schema Information
#
# Table name: user_organization_memberships
# Database name: primary
#
#  id              :integer          not null, primary key
#  role            :integer          not null
#  status          :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :integer          not null
#  user_id         :integer          not null
#
# Indexes
#
#  idx_on_user_id_organization_id_7cc0c85071               (user_id,organization_id) UNIQUE
#  index_user_organization_memberships_on_organization_id  (organization_id)
#  index_user_organization_memberships_on_user_id          (user_id)
#
# Foreign Keys
#
#  organization_id  (organization_id => organizations.id)
#  user_id          (user_id => users.id)
#
class UserOrganizationMembership < ApplicationRecord
  belongs_to :user
  belongs_to :organization

  enum :role, {standard: 0, admin: 1}, default: :standard

  validates :role, presence: true

  state_machine :status, initial: :pending do
    state :pending
    state :active
    state :removed

    event :activate do
      transition pending: :active
      # @lat: [[user-organization-membership-admin-orphan-guard#__only_active_admin?: the shared check both guards call]]
      transition removed: :active
    end

    event :remove do
      transition active: :removed
    end

    # @lat: [[organization-invite-authorization#Reaccepting an invite restores the existing membership]]
    after_transition any => :removed do |membership, _transition|
      membership.update!(role: :standard) unless membership.standard?
    end
  end

  # @lat: [[user-organization-membership-admin-orphan-guard#__only_active_admin?: the shared check both guards call]]
  validate :must_not_orphan_org_admin_on_update, on: :update

  # @lat: [[user-organization-membership-admin-orphan-guard#The destroy-time guard]]
  before_destroy :must_not_orphan_org_admin_on_destroy, prepend: true

  def to_builder
    Jbuilder.new do |m|
      m.id id
      m.user_id user_id
      m.organization organization.to_simple_builder.attributes!
      m.role admin? ? "admin" : "standard"
    end
  end

  private

  # @lat: [[user-organization-membership-admin-orphan-guard#__only_active_admin?: the shared check both guards call]]
  def must_not_orphan_org_admin_on_update
    return unless __only_active_admin?
    errors.add(:base, "Cannot remove or demote the only admin in this organization")
  end

  # @lat: [[user-organization-membership-admin-orphan-guard#The destroy-time guard]]
  def must_not_orphan_org_admin_on_destroy
    throw :abort if __only_active_admin?
  end

  # @lat: [[user-organization-membership-admin-orphan-guard#__only_active_admin?: the shared check both guards call]]
  def __only_active_admin?
    was_admin = role_was == self.class.roles["admin"] || role_was == "admin"
    return false unless was_admin
    return false if status_was == "removed"

    organization.with_lock do
      organization.user_organization_memberships
        .where(role: :admin, status: :active)
        .count == 1
    end
  end
end
