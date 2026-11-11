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
require "rails_helper"

RSpec.describe Invite, type: :model do
  describe "associations" do
    it "persists with inviter + invitee Users via factory" do
      inviter = create(:user)
      invitee = create(:user)
      record = Invite.create!(inviter: inviter, invitee: invitee)

      expect(record).to be_persisted
      expect(record.inviter).to eq(inviter)
      expect(record.invitee).to eq(invitee)
    end

    it "requires both inviter and invitee presence" do
      record = Invite.new
      expect(record).not_to be_valid
      expect(record.errors[:inviter]).to be_present
      expect(record.errors[:invitee]).to be_present
    end
  end

  # The unique index now covers the pair (inviter_id, invitee_id). It replaces a
  # bad migration that made inviter_id unique on its own, which limited every
  # inviter to one invite and made the second person they invited fail to
  # register.
  describe "invites uniqueness" do
    it "rejects a duplicate (inviter, invitee) pair" do
      inviter = create(:user)
      invitee = create(:user)
      Invite.create!(inviter: inviter, invitee: invitee)

      expect {
        Invite.create!(inviter: inviter, invitee: invitee)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "lets one inviter invite multiple distinct invitees" do
      inviter = create(:user)
      first = create(:user)
      second = create(:user)
      Invite.create!(inviter: inviter, invitee: first)

      expect {
        Invite.create!(inviter: inviter, invitee: second)
      }.to change(Invite, :count).by(1)
    end

    it "rejects self-invitation when inviter_id equals invitee_id" do
      user = create(:user)
      invite = Invite.new(inviter: user, invitee: user)

      expect(invite).not_to be_valid
      expect(invite.errors[:invitee_id]).to be_present
      expect {
        Invite.find_or_create_by(inviter: user, invitee: user)
      }.not_to change(Invite, :count)
    end
  end
end
