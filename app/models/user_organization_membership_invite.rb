# == Schema Information
#
# Table name: user_organization_membership_invites
#
#  id              :integer          not null, primary key
#  invitee_email   :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  inviter_id      :integer          not null
#  organization_id :integer          not null
#
# Indexes
#
#  index_user_organization_membership_invites_on_inviter_id       (inviter_id)
#  index_user_organization_membership_invites_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  inviter_id       (inviter_id => users.id)
#  organization_id  (organization_id => organizations.id)
#
class UserOrganizationMembershipInvite < ApplicationRecord
    belongs_to :inviter, class_name: "User"
    belongs_to :organization

    validates :invitee_email, presence: true
end
