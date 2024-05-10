# typed: true

# == Schema Information
#
# Table name: invites
#
#  id                     :integer          not null, primary key
#  inviter_id             :integer          not null
#  invitee_id             :integer
#  invitee_phone          :string           not null
#  invite_accepted_on_utc :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
class Invite < ApplicationRecord
  extend T::Sig

  belongs_to :inviter, class_name: 'user', foreign_key: 'inviter_id'
  belongs_to :invitee, class_name: 'user', foreign_key: 'invitee_id', optional: true

  validates :invitee_phone, presence: true, uniqueness: true, length: { minimum: 10, maximum: 10 }

  after_initialize do
    self.invitee_phone = invitee_phone.remove_non_digits
  end

  sig { returns(T::Boolean) }
  def expired?
    return false unless created_at.present?

    (created_at + 15.minutes).before?(Time.new)
  end

  # send invitee an SMS
  def notify_invitee
    nil
  end
end
