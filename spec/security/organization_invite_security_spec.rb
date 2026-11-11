# frozen_string_literal: true

# @lat: [[organization-invite-authorization#Organization invite authorization]]

require "rails_helper"

RSpec.describe "Organizations::MembershipInvitesController security", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  context "id-enumeration impersonation" do
    it "(A4.1) blocks id-enumeration impersonation via signed-token + email binding" do
      organization = create(:organization)
      real_invitee = create(:user, email: "real@example.com").tap { |u| complete_registration_with_active_link(u) }
      attacker = create(:user, email: "attacker@example.com").tap { |u| complete_registration_with_active_link(u) }
      invite = create(:user_organization_membership_invite,
        organization: organization, invitee_email: "real@example.com")

      # An attacker cannot guess a valid signed token for someone else's invite,
      # and even if they got hold of one, the email comparison stops them.
      token = invite.signed_id(purpose: :accept_invite, expires_at: invite.expires_at)
      session_hash[:user_id] = attacker.id

      # Browser callers get a 303 redirect plus a flash message, while JSON
      # callers still get the older 403 body. Ask for JSON here so the test can
      # check the 403 status directly.
      post "/organizations/#{organization.id}/membership_invites/#{token}/accept",
        headers: {"Accept" => "application/json"}

      expect(response.status).to eq(403)
      expect(UserOrganizationMembership.where(user: attacker, organization: organization)).to be_empty
      # Ensure real_invitee is referenced so RSpec doesn't warn.
      expect(real_invitee).to be_persisted
    end
  end

  context "replay after accept" do
    it "(A4.2) blocks replay after accept (accepted_at non-null guard inside transaction)" do
      organization = create(:organization)
      invitee = create(:user, email: "invitee@example.com").tap { |u| complete_registration_with_active_link(u) }
      invite = create(:user_organization_membership_invite,
        organization: organization, invitee_email: "invitee@example.com")
      session_hash[:user_id] = invitee.id
      token = invite.signed_id(purpose: :accept_invite, expires_at: invite.expires_at)

      post "/organizations/#{organization.id}/membership_invites/#{token}/accept"
      post "/organizations/#{organization.id}/membership_invites/#{token}/accept",
        headers: {"Accept" => "application/json"}

      expect(response.status).to eq(422)
      expect(invitee.user_organization_memberships.where(organization: organization).count).to eq(1)
    end
  end

  context "expired token" do
    it "(expired) blocks acceptance after expiry (defense-in-depth: token expiry + column expiry)" do
      # Expiry is caught in two places: the signed token expires on its own
      # (InvalidSignature), and the invite row has its own expires_at column
      # (InviteExpired). Both answer 410 Gone, so the status is the same
      # whichever guard trips first.
      organization = create(:organization)
      invitee = create(:user, email: "invitee@example.com").tap { |u| complete_registration_with_active_link(u) }
      invite = create(:user_organization_membership_invite,
        organization: organization, invitee_email: "invitee@example.com")
      invite.update_columns(expires_at: 1.day.ago)
      token = invite.signed_id(purpose: :accept_invite, expires_at: 1.day.ago)
      session_hash[:user_id] = invitee.id

      post "/organizations/#{organization.id}/membership_invites/#{token}/accept",
        headers: {"Accept" => "application/json"}

      expect(response.status).to eq(410)
    end
  end
end
