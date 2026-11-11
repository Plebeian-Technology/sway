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
require "rails_helper"

RSpec.describe UserOrganizationMembershipInvite, type: :model do
  describe "associations" do
    it "persists with an inviter and an organization via factory" do
      record = create(:user_organization_membership_invite)
      expect(record).to be_persisted
      expect(record.inviter).to be_a(User)
      expect(record.organization).to be_a(Organization)
    end
  end

  describe "validations" do
    it "is valid with factory attributes" do
      expect(build(:user_organization_membership_invite)).to be_valid
    end

    it "requires invitee_email" do
      record = build(:user_organization_membership_invite, invitee_email: nil)
      expect(record).not_to be_valid
      expect(record.errors[:invitee_email]).to be_present
    end
  end

  describe "before_create — expires_at default" do
    it "sets expires_at = created_at + 14.days when not specified" do
      invite = create(:user_organization_membership_invite)
      expect(invite.expires_at).to be_within(5.seconds).of(invite.created_at + 14.days)
    end

    it "preserves explicit expires_at when passed" do
      explicit = 30.days.from_now
      invite = create(:user_organization_membership_invite, expires_at: explicit)
      expect(invite.expires_at).to be_within(5.seconds).of(explicit)
    end
  end

  describe "#status (derived from fact columns)" do
    it "is :pending when fresh (no accepted_at, no revoked_at, expires_at in future)" do
      invite = create(:user_organization_membership_invite)
      expect(invite.status).to eq(:pending)
    end

    it "is :accepted when accepted_at is set" do
      invite = create(:user_organization_membership_invite, :accepted)
      expect(invite.status).to eq(:accepted)
    end

    it "is :revoked when revoked_at is set (and not accepted)" do
      invite = create(:user_organization_membership_invite, :revoked)
      expect(invite.status).to eq(:revoked)
    end

    it "is :expired when expires_at is in the past (and not accepted, not revoked)" do
      invite = create(:user_organization_membership_invite, :expired)
      expect(invite.status).to eq(:expired)
    end

    it "prefers :accepted over :revoked when both columns set" do
      invite = create(:user_organization_membership_invite, accepted_at: Time.current, revoked_at: Time.current)
      expect(invite.status).to eq(:accepted)
    end

    it "prefers :revoked over :expired when both apply" do
      invite = create(:user_organization_membership_invite, revoked_at: Time.current, expires_at: 1.day.ago)
      expect(invite.status).to eq(:revoked)
    end
  end

  describe "active-duplicate validation" do
    let(:organization) { create(:organization) }
    let(:invitee_email) { "duplicate@example.com" }

    it "rejects a second active invite for same (invitee_email, organization)" do
      create(:user_organization_membership_invite, organization:, invitee_email:)
      duplicate = build(:user_organization_membership_invite, organization:, invitee_email:)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:invitee_email].join).to include("already has an active invite")
    end

    it "permits a new invite when prior is :accepted" do
      create(:user_organization_membership_invite, :accepted, organization:, invitee_email:)
      successor = build(:user_organization_membership_invite, organization:, invitee_email:)
      expect(successor).to be_valid
    end

    it "permits a new invite when prior is :revoked" do
      create(:user_organization_membership_invite, :revoked, organization:, invitee_email:)
      successor = build(:user_organization_membership_invite, organization:, invitee_email:)
      expect(successor).to be_valid
    end

    it "permits a new invite when prior is :expired" do
      create(:user_organization_membership_invite, :expired, organization:, invitee_email:)
      successor = build(:user_organization_membership_invite, organization:, invitee_email:)
      expect(successor).to be_valid
    end
  end

  describe "signed_id roundtrip" do
    it "generates a signed token bound to purpose: :accept_invite" do
      invite = create(:user_organization_membership_invite)
      token = invite.signed_id(purpose: :accept_invite, expires_at: invite.expires_at)
      expect(token).to be_a(String).and(be_present)
      found = UserOrganizationMembershipInvite.find_signed!(token, purpose: :accept_invite)
      expect(found).to eq(invite)
    end

    it "rejects a token with wrong purpose" do
      invite = create(:user_organization_membership_invite)
      token = invite.signed_id(purpose: :accept_invite, expires_at: invite.expires_at)
      expect {
        UserOrganizationMembershipInvite.find_signed!(token, purpose: :other_purpose)
      }.to raise_error(ActiveSupport::MessageVerifier::InvalidSignature)
    end

    it "rejects a tampered token" do
      invite = create(:user_organization_membership_invite)
      token = invite.signed_id(purpose: :accept_invite, expires_at: invite.expires_at)
      tampered = token[0..-3] + "ZZ"
      expect {
        UserOrganizationMembershipInvite.find_signed!(tampered, purpose: :accept_invite)
      }.to raise_error(ActiveSupport::MessageVerifier::InvalidSignature)
    end
  end

  describe "invitee_user association" do
    it "is nil on create" do
      invite = create(:user_organization_membership_invite)
      expect(invite.invitee_user_id).to be_nil
    end

    it "can be set post-create (full population happens during accept in Plan 05)" do
      user = create(:user)
      invite = create(:user_organization_membership_invite, invitee_user: user)
      expect(invite.reload.invitee_user_id).to eq(user.id)
    end
  end

  describe "User#received_organization_invites reverse association" do
    it "returns invites where invitee_user_id matches" do
      user = create(:user)
      invite = create(:user_organization_membership_invite, invitee_user: user)
      _other = create(:user_organization_membership_invite)
      expect(user.received_organization_invites).to include(invite)
      expect(user.received_organization_invites.count).to eq(1)
    end
  end
end
