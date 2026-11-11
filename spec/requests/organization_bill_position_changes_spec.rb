require "rails_helper"

# These examples cover the public actions on
# app/controllers/organization_bill_position_changes_controller.rb: index and update.

# The model behind that controller is app/models/organization_bill_position_change.rb

# spec/requests/user_organization_membership_invites_spec.rb shows how these tests are
# laid out. spec/support/setup.rb creates a user, and spec/support/session_double.rb
# signs that user in and gives the example a session.

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
            role: :admin
          )
        change =
          create(
            :organization_bill_position_change,
            organization_bill_position: position,
            updated_by: admin,
            status: :pending,
            approved_by_id: nil,
            new_support: "oppose",
            new_summary: "Updated summary",
            previous_support: "support",
            previous_summary: "Old summary"
          )

        patch organization_position_change_path(organization, change)

        expect(response).to redirect_to(
          organization_membership_path(organization, membership)
        )
        expect(flash[:notice]).to eq("Change approved and position updated.")
        expect(change.reload.approved_by_id).to eq(admin.id)
        expect(position.reload.support).to eq("AGAINST")
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
            role: :standard
          )
        change =
          create(
            :organization_bill_position_change,
            organization_bill_position: position,
            updated_by: user,
            status: :pending,
            approved_by_id: nil
          )

        patch organization_position_change_path(organization, change)

        expect(response).to redirect_to(
          organization_membership_path(organization, membership)
        )
        expect(flash[:alert]).to eq("Forbidden")
        expect(change.reload.approved_by_id).to be_nil
      end
    end
  end
end
