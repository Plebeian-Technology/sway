require "rails_helper"

# Okay now please create tests for the spec/requests/organization_bill_position_changes_spec.rb spec file. The spec file should test the public methods in app/controllers/organization_bill_position_changes_controller.rb, which has index and update public methods.

# The model that this controller provides api routes for is located at app/models/organization_bill_position_change.rb

# Check spec/requests/user_organization_membership_invites_spec.rb for reference on how the tests should be organized. Use spec/support/setup.rb to create a user. Use spec/support/session_double.rb to sign in the user and obtain a session.

RSpec.describe "OrganizationBillPositionChanges", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:organization) { create(:organization) }
  let(:bill) { create(:bill) }
  let(:position) do
    create(:organization_bill_position, organization: organization, bill: bill)
  end

  describe "PATCH /organization_bill_position_changes/:id" do
    context "as an admin" do
      it "approves the change and updates the position" do
        _, admin = setup
        membership =
          create(
            :user_organization_membership,
            user: admin,
            organization: organization,
            role: :admin,
          )
        change =
          create(
            :organization_bill_position_change,
            organization_bill_position: position,
            updated_by: admin,
            approved_by_id: nil,
            new_support: "oppose",
            new_summary: "Updated summary",
            previous_support: "support",
            previous_summary: "Old summary",
          )

        patch organization_bill_position_change_path(change)

        expect(response).to redirect_to(
          user_organization_membership_path(membership),
        )
        expect(flash[:notice]).to eq("Change approved and position updated.")
        expect(change.reload.approved_by_id).to eq(admin.id)
        expect(position.reload.support).to eq("oppose")
        expect(position.reload.summary).to eq("Updated summary")
      end
    end

    context "as a non-admin" do
      it "is forbidden from approving the change" do
        _, user = setup
        membership =
          create(
            :user_organization_membership,
            user: user,
            organization: organization,
            role: :standard,
          )
        change =
          create(
            :organization_bill_position_change,
            organization_bill_position: position,
            updated_by: user,
            approved_by_id: nil,
          )

        patch organization_bill_position_change_path(change)

        expect(response).to redirect_to(
          user_organization_membership_path(membership),
        )
        expect(flash[:alert]).to eq("Forbidden")
        expect(change.reload.approved_by_id).to be_nil
      end
    end
  end
end
