# Okay now please create tests for the spec/requests/organization/:id/positions_spec.rb spec file. The spec file should test the public methods in app/controllers/organization/:id/positions_controller.rb, which has create, update and destroy and public methods.

# Add spec/requests/user_organization_membership_invites_spec.rb for reference on how the tests should be organized. Use spec/support/setup.rb to create a user. Use spec/support/session_double.rb to sign in the user and obtain a session.

require "rails_helper"

RSpec.describe "Organization::Positions", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:organization) { create(:organization) }
  let(:bill) { create(:bill) }

  describe "POST /organization/:id/positions" do
    it "creates a new position for the user" do
      _, user = setup
      _membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization,
        )

      expect do
        post organization_positions_path(organization),
             params: {
               bill_id: bill.id,
               support: "support",
               summary: "We support this bill",
             }
      end.to change(OrganizationBillPosition, :count).by(1).and change(
              OrganizationBillPositionChange,
              :count,
            ).by(1)

      position = OrganizationBillPosition.last!
      expect(position.organization).to eq(organization)
      expect(position.bill).to eq(bill)
      expect(position.support).to eq("support")
      expect(position.summary).to eq(OrganizationBillPosition::DEFAULT_SUMMARY)
      expect(position.active).to be false

      change = OrganizationBillPositionChange.last!
      expect(change.organization_bill_position).to eq(position)
      expect(change.new_summary).to eq("We support this bill")
      expect(change.new_support).to eq("support")
      expect(change.previous_summary).to eq("")
      expect(change.previous_support).to eq("support") # new position, so previous_support is same as new

      expect(response).to have_http_status(:redirect)
    end

    it "creates a new change when reactivating a position with history" do
      _, user = setup
      _membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization,
        )

      # Create an existing inactive position with an APPROVED change
      position =
        create(
          :organization_bill_position,
          organization: organization,
          bill: bill,
          support: "oppose",
          summary: "Old summary",
          active: false,
        )

      old_change =
        create(
          :organization_bill_position_change,
          organization_bill_position: position,
          updated_by: user,
          approved_by: user, # approved
          new_support: "oppose",
          new_summary: "Old summary",
        )

      expect do
        post organization_positions_path(organization),
             params: {
               bill_id: bill.id,
               support: "support",
               summary: "New summary",
             }
      end.to change(OrganizationBillPosition, :count).by(0).and change(
              # reuses position
              OrganizationBillPositionChange,
              :count,
            ).by(1) # creates new change

      position.reload
      expect(position.support).to eq("support")
      # Active remains false until approved
      expect(position.active).to be false

      new_change = OrganizationBillPositionChange.last!
      expect(new_change.id).not_to eq(old_change.id)
      expect(new_change.approved_by_id).to be_nil
      expect(new_change.new_summary).to eq("New summary")
      expect(new_change.new_support).to eq("support")

      expect(response).to have_http_status(:redirect)
    end

    it "creates multiple pending changes if submitted multiple times (immutability)" do
      _, user = setup
      create(
        :user_organization_membership,
        user: user,
        organization: organization,
      )

      # Create inactive position
      position =
        create(
          :organization_bill_position,
          organization: organization,
          bill: bill,
          active: false,
        )

      # First submission
      expect do
        post organization_positions_path(organization),
             params: {
               bill_id: bill.id,
               support: "support",
               summary: "First draft",
             }
      end.to change(OrganizationBillPositionChange, :count).by(1)

      # Second submission
      expect do
        post organization_positions_path(organization),
             params: {
               bill_id: bill.id,
               support: "oppose",
               summary: "Second draft",
             }
      end.to change(OrganizationBillPositionChange, :count).by(1)

      changes = position.position_changes.order(:created_at)
      expect(changes.count).to eq(2)
      expect(changes.first.new_summary).to eq("First draft")
      expect(changes.last.new_summary).to eq("Second draft")
    end
  end

  describe "PUT /organzations/:organization_id/positions/:id" do
    it "updates the position" do
      _, user = setup
      _membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization,
        )
      position =
        create(
          :organization_bill_position,
          organization: organization,
          bill: bill,
          support: "oppose",
          summary: "Old summary",
        )

      expect do
        put organization_position_path(organization, position),
            params: {
              support: "support",
              summary: "Updated summary",
            }
      end.to change(OrganizationBillPositionChange, :count).by(1)

      expect(response).to have_http_status(:redirect).or have_http_status(:ok)
    end
  end

  describe "DELETE /organizations/:organization_id/positions/:id" do
    it "is forbidden from removing the position" do
      _, user = setup
      _membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization,
          role: :standard,
        )

      expect do
        create(
          :organization_bill_position,
          organization: organization,
          bill: bill,
          support: "neutral",
          summary: "summary",
        )
      end.to change(OrganizationBillPosition, :count).by(1)

      position = OrganizationBillPosition.last!

      expect do
        delete organization_position_path(organization, position)
      end.to change(OrganizationBillPosition, :count).by(0)

      expect(flash[:alert]).to eql("Forbidden")
    end

    it "removes the position" do
      _, user = setup
      _membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization,
          role: :admin,
        )

      expect do
        create(
          :organization_bill_position,
          organization: organization,
          bill: bill,
          support: "neutral",
          summary: "summary",
        )
      end.to change(OrganizationBillPosition, :count).by(1)

      position = OrganizationBillPosition.last!

      expect do
        delete organization_position_path(organization, position)
      end.to change(OrganizationBillPosition, :count).by(0)
      position.reload
      expect(position.active).to be false

      expect(response).to have_http_status(:redirect).or have_http_status(
             :no_content,
           )
    end
  end
end
