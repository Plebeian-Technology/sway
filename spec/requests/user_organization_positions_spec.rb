# Okay now please create tests for the spec/requests/user_organization_positions_spec.rb spec file. The spec file should test the public methods in app/controllers/user_organization_positions_controller.rb, which has create, update and destroy and public methods.

# Add spec/requests/user_organization_membership_invites_spec.rb for reference on how the tests should be organized. Use spec/support/setup.rb to create a user. Use spec/support/session_double.rb to sign in the user and obtain a session.

require "rails_helper"

RSpec.describe "UserOrganizationPositions", type: :request do
    include_context "SessionDouble"
    include_context "Setup"

    let(:organization) { create(:organization) }
    let(:bill) { create(:bill) }

    describe "POST /user_organization_positions" do
        it "creates a new position for the user" do
            skip "Skipping until implemented"

            _, user = setup
            _membership = create(:user_organization_membership, user: user, organization: organization)

            expect do
                post user_organization_positions_path,
                          params: {
                              position: {
                                  bill_id: bill.id,
                                  support: true,
                                  summary: "We support this bill",
                              },
                          }
            end.to change(OrganizationBillPosition, :count).by(1)

            position = OrganizationBillPosition.last
            expect(position.organization).to eq(organization)
            expect(position.bill).to eq(bill)
            expect(position.support).to be true
            expect(position.summary).to eq("We support this bill")
            expect(response).to have_http_status(:redirect).or have_http_status(:created)
        end
    end

    describe "PUT user_organization_positions/:id" do
        it "updates the position" do
            _, user = setup
            _membership = create(:user_organization_membership, user: user, organization: organization)
            position =
                create(
                    :organization_bill_position,
                    organization: organization,
                    bill: bill,
                    support: false,
                    summary: "Old summary",
                )

            expect do
                put user_organization_position_path(position), params: { support: true, summary: "Updated summary" }
            end.to change(OrganizationBillPositionChange, :count).by(1)

            expect(response).to have_http_status(:redirect).or have_http_status(:ok)
        end
    end

    describe "DELETE /organizations/:organization_id/user_organization_positions/:id" do
        it "is forbidden from removing the position" do
            _, user = setup
            _membership = create(:user_organization_membership, user: user, organization: organization, role: :standard)

            position = nil
            expect { position = create(:organization_bill_position, organization: organization, bill: bill) }.to change(
                OrganizationBillPosition,
                :count,
            ).by(1)

            expect do
 delete user_organization_position_path(position) end.to change(OrganizationBillPosition, :count).by(0)

            expect(flash[:alert]).to eql("Forbidden")
        end

        it "removes the position" do
            _, user = setup
            _membership = create(:user_organization_membership, user: user, organization: organization, role: :admin)

            position = nil
            expect { position = create(:organization_bill_position, organization: organization, bill: bill) }.to change(
                OrganizationBillPosition,
                :count,
            ).by(1)

            expect do
 delete user_organization_position_path(position) end.to change(OrganizationBillPosition, :count).by(-1)

            expect(response).to have_http_status(:redirect).or have_http_status(:no_content)
        end
    end
end
