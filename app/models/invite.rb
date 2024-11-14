# frozen_string_literal: true
# typed: true

# == Schema Information
#
# Table name: invites
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
#  index_invites_on_inviter_id                 (inviter_id)
#  index_invites_on_inviter_id_and_inviter_id  (inviter_id) UNIQUE
#
# Foreign Keys
#
#  invitee_id  (invitee_id => users.id)
#  inviter_id  (inviter_id => users.id)
#
class Invite < ApplicationRecord
  extend T::Sig

  belongs_to :inviter, class_name: "User"
  belongs_to :invitee, class_name: "User"

  sig { returns(User) }
  def inviter
    T.cast(User.find_by(id: inviter_id), User)
  end

  sig { returns(User) }
  def invitee
    T.cast(User.find_by(id: invitee_id), User)
  end
end
