require "rails_helper"

RSpec.describe UserOrganizationMembershipInviteMailer, type: :mailer do
    let(:organization) { create(:organization) }
    let(:inviter) { create(:user, full_name: "Alice Admin") }
    let(:invite) do
        create(
            :user_organization_membership_invite,
            inviter: inviter,
            organization: organization,
            invitee_email: "invitee@example.com",
        )
    end

    describe "invite" do
        let(:mail) { described_class.invite(invite) }

        it "renders the headers" do
            expect(mail.subject).to include(organization.name)
            expect(mail.to).to eq([invite.invitee_email])
            expect(mail.from).to eq([UserOrganizationMembershipInviteMailer.default[:from]])
        end

        it "renders the body" do
            expect(mail.body.encoded).to include(inviter.full_name)
            expect(mail.body.encoded).to include(organization.name)
        end
    end
end
