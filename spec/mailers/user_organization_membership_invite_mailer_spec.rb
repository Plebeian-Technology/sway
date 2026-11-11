require "rails_helper"

RSpec.describe UserOrganizationMembershipInviteMailer, type: :mailer do
  let(:organization) { create(:organization) }
  let(:inviter) { create(:user, full_name: "Alice Admin") }
  let(:invite) do
    create(
      :user_organization_membership_invite,
      inviter: inviter,
      organization: organization,
      invitee_email: "invitee@example.com"
    )
  end

  describe "invite" do
    let(:mail) { described_class.invite(invite) }

    it "renders the headers" do
      expect(mail.subject).to include(organization.name)
      expect(mail.to).to eq([invite.invitee_email])
      # Checked against the literal address it inherits, since this mailer sets no
      # from: of its own. Comparing it to default_params would prove nothing.
      expect(mail.from).to eq(["outreach@sway.vote"])
    end

    it "renders the body" do
      expect(mail.body.encoded).to include(inviter.full_name)
      expect(mail.body.encoded).to include(organization.name)
    end
  end

  describe "#invite (signed-token URL helper)" do
    it "renders confirm_accept_organization_membership_invite_url with signed token" do
      mail = UserOrganizationMembershipInviteMailer.invite(invite)
      # Read body.encoded. For an email with several parts, body.to_s comes back
      # empty, while body.encoded holds every part: the separators and each
      # part's encoded content.
      body = mail.body.encoded
      # The body must contain the landing URL that carries the signed token
      expect(body).to match(%r{/organizations/#{organization.id}/membership_invites/[^/\s"]+/confirm_accept})
    end

    it "embeds a token that find_signed! verifies for purpose :accept_invite" do
      mail = UserOrganizationMembershipInviteMailer.invite(invite)
      body = mail.body.encoded
      token = body[%r{/membership_invites/([^/\s"]+)/confirm_accept}, 1]
      expect(token).to be_present
      found = UserOrganizationMembershipInvite.find_signed!(token, purpose: :accept_invite)
      expect(found).to eq(invite)
    end

    it "does NOT embed the legacy integer-id accept URL" do
      mail = UserOrganizationMembershipInviteMailer.invite(invite)
      body = mail.body.to_s
      # the old shape: /organizations/X/membership_invites/INTEGER/accept, with no /confirm_accept
      expect(body).not_to match(%r{/membership_invites/#{invite.id}/accept(?!_)})
    end
  end
end
