require "rails_helper"

RSpec.describe "UserOrganizationMemberships", type: :request, inertia: true do
    include_context "SessionDouble"
    include_context "Setup"

    let(:organization) { create(:organization) }

    describe "GET user_organization_memberships" do
        it "renders the memberships index" do
            _, user = setup
            create(:user_organization_membership, user: user, organization: organization)

            get user_organization_memberships_path
            expect(response).to have_http_status(:ok)
        end
    end

    describe "GET user_organization_memberships/:id" do
        it "shows the membership details" do
            _, user = setup
            membership = create(:user_organization_membership, user: user, organization: organization)

            get user_organization_membership_path(membership)
            expect(response).to have_http_status(:ok)
            expect(inertia.props.deep_symbolize_keys.dig(:membership, :id)).to eql(membership.id)
        end
    end

    describe "PATCH user_organization_memberships/:id" do
        context "as an admin" do
            it "updates the member's role" do
                _, admin = setup
                admin_membership = create(:user_organization_membership, user: admin, organization: organization, 
role: :admin)
                member = create(:user)
                member_membership =
                    create(:user_organization_membership, user: member, organization: organization, role: :standard)

                patch user_organization_membership_path(admin_membership),
                            params: {
                                membership_id: member_membership.id,
                                role: "admin",
                            }

                expect(response).to redirect_to(user_organization_membership_path(admin_membership))
                expect(member_membership.reload.role).to eq("admin")
            end
        end

        context "as a non-admin" do
            it "does not allow updating the member's role" do
                _, user = setup
                membership = create(:user_organization_membership, user: user, organization: organization, 
role: :standard)
                other = create(:user)
                other_membership =
                    create(:user_organization_membership, user: other, organization: organization, role: :standard)

                patch user_organization_membership_path(membership),
                            params: {
                                membership_id: other_membership.id,
                                role: "admin",
                            }

                expect(response).to redirect_to(user_organization_membership_path(membership))
                expect(flash[:alert]).to eq("Forbidden")
                expect(other_membership.reload.role).to eq("standard")
            end
        end
    end

    describe "DELETE user_organization_memberships/:id" do
        context "as an admin" do
            it "removes the membership" do
                _, admin = setup
                admin_membership = create(:user_organization_membership, user: admin, organization: organization, 
role: :admin)
                member = create(:user)
                member_membership =
                    create(:user_organization_membership, user: member, organization: organization, role: :standard)

                expect do
                    delete user_organization_membership_path(admin_membership), 
params: { membership_id: member_membership.id }
                end.to change(UserOrganizationMembership, :count).by(-1)

                expect(response).to redirect_to(user_organization_membership_path(admin_membership))
                expect(flash[:notice]).to eq("Member removed")
            end
        end

        context "as a non-admin" do
            it "does not allow removing the membership" do
                _, user = setup
                membership = create(:user_organization_membership, user: user, organization: organization, 
role: :standard)
                other = create(:user)
                other_membership =
                    create(:user_organization_membership, user: other, organization: organization, role: :standard)

                expect do
                    delete user_organization_membership_path(membership), params: { membership_id: other_membership.id }
                end.not_to change(UserOrganizationMembership, :count)

                expect(response).to redirect_to(user_organization_membership_path(membership))
                expect(flash[:alert]).to eq("Forbidden")
            end
        end

        context "when removing own membership" do
            it "redirects to memberships index" do
                _, user = setup
                membership = create(:user_organization_membership, user: user, organization: organization, role: :admin)

                expect do
                    delete user_organization_membership_path(membership), params: { membership_id: membership.id }
                end.to change(UserOrganizationMembership, :count).by(-1)

                expect(response).to redirect_to(user_organization_memberships_path)
            end
        end
    end
end
