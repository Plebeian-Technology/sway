# frozen_string_literal: true

# == Schema Information
#
# Table name: invites
# Database name: primary
#
#  id         :integer          not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  invitee_id :integer          not null
#  inviter_id :integer          not null
#
# Indexes
#
#  index_invites_on_invitee_id                 (invitee_id)
#  index_invites_on_inviter_id_and_invitee_id  (inviter_id,invitee_id) UNIQUE
#
# Foreign Keys
#
#  invitee_id  (invitee_id => users.id)
#  inviter_id  (inviter_id => users.id)
#
# Invite URLs are short URLs served at /s/<unique_key>; visiting one redirects
# to /<user_id>/<invite_uuid>. Completing registration from that link creates
# an Invite whose inviter_id is the <user_id> from the long URL and whose
# invitee_id is the new user's id.
class Invite < ApplicationRecord
  belongs_to :inviter, class_name: "User", inverse_of: :sent_invites
  belongs_to :invitee, class_name: "User", inverse_of: :received_invites

  validate :prevent_self_invite

  private

  def prevent_self_invite
    return unless inviter_id.present? && inviter_id == invitee_id

    errors.add(:invitee_id, "cannot be the same as inviter")
  end
end
