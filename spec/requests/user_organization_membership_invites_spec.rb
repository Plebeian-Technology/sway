require "rails_helper"

RSpec.describe "UserOrganizationMembershipInvites", type: :request do
    include_context "SessionDouble"
    include_context "Setup"

    let(:organization) { create(:organization) }

    describe "POST /organizations/:organization_id/user_organization_membership_invites" do
        it "creates an invite and sends an email" do
            _, admin = setup

            _membership = create(:user_organization_membership, user: admin, organization: organization, role: :admin)

            expect do
                post organization_user_organization_membership_invites_path(organization),
                          params: {
                              invite: {
                                  invitee_email: "invitee@example.com",
                              },
                          }
            end.to change(UserOrganizationMembershipInvite, :count).by(1).and change {
                            ActionMailer::Base.deliveries.count
                        }.by(1)

            invite = UserOrganizationMembershipInvite.last
            mail = ActionMailer::Base.deliveries.last
            expect(mail.to).to include("invitee@example.com")
            expect(invite.organization).to eq(organization)
            expect(invite.inviter).to eq(admin)
        end
    end
end
