# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Organization::Positions", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:organization) { create(:organization) }
  let(:bill) { create(:bill, sway_locale: organization.sway_locale) }

  describe "POST /organization/:id/positions" do
    it "creates a new position for the user" do
      _, user = setup
      _membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization
        )

      expect do
        post organization_positions_path(organization),
          params: {
            bill_id: bill.id,
            support: "support",
            summary: "We support this bill"
          }
      end.to change(OrganizationBillPosition, :count).by(1).and change(
        OrganizationBillPositionChange,
        :count
      ).by(1)

      position = OrganizationBillPosition.last!
      expect(position.organization).to eq(organization)
      expect(position.bill).to eq(bill)
      expect(position.support).to eq("FOR")
      expect(position.summary).to eq(OrganizationBillPosition::DEFAULT_SUMMARY)
      expect(position.active).to be false

      change = OrganizationBillPositionChange.last!
      expect(change.organization_bill_position).to eq(position)
      expect(change.new_summary).to eq("We support this bill")
      expect(change.new_support).to eq("FOR")
      expect(change.previous_summary).to eq("")
      expect(change.previous_support).to eq("FOR")

      expect(response).to have_http_status(:redirect)
    end

    it "creates a new change when reactivating a position with history" do
      _, user = setup
      _membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization
        )

      position =
        create(
          :organization_bill_position,
          organization: organization,
          bill: bill,
          support: "oppose",
          summary: "Old summary",
          active: false
        )

      old_change =
        create(
          :organization_bill_position_change,
          organization_bill_position: position,
          updated_by: user,
          approved_by: user, # approved
          status: :approved, # the validator requires status to match approved_by
          new_support: "oppose",
          new_summary: "Old summary"
        )

      expect do
        post organization_positions_path(organization),
          params: {
            bill_id: bill.id,
            support: "support",
            summary: "New summary"
          }
      end.to change(OrganizationBillPosition, :count).by(0).and change(
        # reuses position
        OrganizationBillPositionChange,
        :count
      ).by(1) # creates new change

      position.reload
      expect(position.support).to eq("AGAINST")
      expect(position.summary).to eq("Old summary")
      # Active remains false until approved
      expect(position.active).to be false

      new_change = OrganizationBillPositionChange.last!
      expect(new_change.id).not_to eq(old_change.id)
      expect(new_change.approved_by_id).to be_nil
      expect(new_change.new_summary).to eq("New summary")
      expect(new_change.new_support).to eq("FOR")

      expect(response).to have_http_status(:redirect)
    end

    it "rolls back the new OrganizationBillPosition when change validation fails" do
      _, user = setup
      create(:user_organization_membership, user: user, organization: organization)

      expect do
        post organization_positions_path(organization),
          params: {
            bill_id: bill.id,
            support: "support",
            summary: ""
          }
      end.to change(OrganizationBillPosition, :count).by(0)
        .and change(OrganizationBillPositionChange, :count).by(0)

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to be_present
    end

    it "creates multiple pending changes if submitted multiple times (immutability)" do
      _, user = setup
      create(
        :user_organization_membership,
        user: user,
        organization: organization
      )

      position =
        create(
          :organization_bill_position,
          organization: organization,
          bill: bill,
          active: false
        )

      # First submission
      expect do
        post organization_positions_path(organization),
          params: {
            bill_id: bill.id,
            support: "support",
            summary: "First draft"
          }
      end.to change(OrganizationBillPositionChange, :count).by(1)

      # Second submission
      expect do
        post organization_positions_path(organization),
          params: {
            bill_id: bill.id,
            support: "oppose",
            summary: "Second draft"
          }
      end.to change(OrganizationBillPositionChange, :count).by(1)

      changes = position.position_changes.order(:created_at)
      expect(changes.count).to eq(2)
      expect(changes.first.new_summary).to eq("First draft")
      expect(changes.last.new_summary).to eq("Second draft")
    end

    it "rejects creating a position for a bill from a different sway_locale" do
      _, user = setup
      create(
        :user_organization_membership,
        user: user,
        organization: organization
      )
      other_locale = create(:sway_locale, city: "OtherCity", state: "Maryland", country: "United States")
      foreign_bill = create(:bill, sway_locale: other_locale)

      expect do
        post organization_positions_path(organization),
          params: {
            bill_id: foreign_bill.id,
            support: "support",
            summary: "Cross-locale position attempt"
          }
      end.to change(OrganizationBillPosition, :count).by(0).and change(
        OrganizationBillPositionChange,
        :count
      ).by(0)

      expect(response).to redirect_to("/organizations/#{organization.id}")
      expect(flash[:alert]).to eq("Bill does not belong to this organization's locale.")

      expect do
        post organization_positions_path(organization),
          params: {
            bill_id: foreign_bill.id,
            support: "support",
            summary: "Cross-locale position attempt JSON"
          },
          as: :json
      end.to change(OrganizationBillPosition, :count).by(0).and change(
        OrganizationBillPositionChange,
        :count
      ).by(0)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PUT /organzations/:organization_id/positions/:id" do
    it "updates the position" do
      _, user = setup
      _membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization
        )
      position =
        create(
          :organization_bill_position,
          organization: organization,
          bill: bill,
          support: "oppose",
          summary: "Old summary"
        )

      expect do
        put organization_position_path(organization, position),
          params: {
            support: "support",
            summary: "Updated summary"
          }
      end.to change(OrganizationBillPositionChange, :count).by(1)

      expect(response).to have_http_status(:redirect).or have_http_status(:ok)
    end

    # @lat: [[organization-bill-position-change-design#The stance-validation bug: why new_support validates against a shared list]]
    it "rejects a blank support value sent as JSON instead of saving a change that later 500s an admin" do
      _, user = setup
      _membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization
        )
      position =
        create(
          :organization_bill_position,
          organization: organization,
          bill: bill,
          support: "oppose",
          summary: "Old summary"
        )

      expect do
        put organization_position_path(organization, position),
          params: {
            support: "",
            summary: "Updated summary"
          },
          as: :json
      end.not_to change(OrganizationBillPositionChange, :count)

      expect(response).not_to have_http_status(:internal_server_error)
      expect(flash[:alert]).to be_present
    end

    # @lat: [[org-positions-membership-idor-security#Why set_change reuses a still-pending change instead of always creating a new one]]
    it "creates a new pending change (does not mutate the rejected row) when proposer revises after rejection (WR-05)" do
      _, user = setup
      _membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization
        )
      position =
        create(
          :organization_bill_position,
          organization: organization,
          bill: bill,
          support: "oppose",
          summary: "Old summary"
        )

      admin_user = create(:user)
      rejected_change =
        create(
          :organization_bill_position_change,
          organization_bill_position: position,
          updated_by: user,
          new_support: "support",
          new_summary: "First revision",
          previous_support: "oppose",
          previous_summary: "Old summary"
        )
      rejected_change.update!(
        status: :rejected,
        rejected_by: admin_user,
        rejected_at: Time.current
      )

      expect do
        put organization_position_path(organization, position),
          params: {
            support: "support",
            summary: "Second revision (after rejection)"
          }
      end.to change(OrganizationBillPositionChange, :count).by(1)

      # The rejected row is left untouched (status, content, rejected_by).
      rejected_change.reload
      expect(rejected_change.status).to eq("rejected")
      expect(rejected_change.new_summary).to eq("First revision")
      expect(rejected_change.rejected_by_id).to eq(admin_user.id)

      # The new row is pending and carries the new content.
      new_change = OrganizationBillPositionChange.order(:created_at).last!
      expect(new_change.id).not_to eq(rejected_change.id)
      expect(new_change.status).to eq("pending")
      expect(new_change.approved_by_id).to be_nil
      expect(new_change.rejected_by_id).to be_nil
      expect(new_change.new_summary).to eq("Second revision (after rejection)")
      expect(new_change.updated_by_id).to eq(user.id)
    end
  end

  describe "DELETE /organizations/:organization_id/positions/:id" do
    describe "org-admin gate on #destroy" do
      include_examples "requires organization admin",
        verb: :delete,
        path: -> {
          bill = create(:bill)
          position = create(:organization_bill_position, organization: organization, bill: bill)
          "/organizations/#{organization.id}/positions/#{position.id}"
        }
    end

    it "is forbidden from removing the position" do
      _, user = setup
      _membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization,
          role: :standard
        )

      expect do
        create(
          :organization_bill_position,
          organization: organization,
          bill: bill,
          support: "neutral",
          summary: "summary"
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
          status: :active
        )

      expect do
        create(
          :organization_bill_position,
          organization: organization,
          bill: bill,
          support: "neutral",
          summary: "summary"
        )
      end.to change(OrganizationBillPosition, :count).by(1)

      position = OrganizationBillPosition.last!

      expect do
        delete organization_position_path(organization, position)
      end.to change(OrganizationBillPosition, :count).by(0)
      position.reload
      expect(position.active).to be false

      expect(response).to have_http_status(:redirect).or have_http_status(
             :no_content
           )
    end
  end

  describe "GET /organizations/:id/positions/new" do
    it "renders the new-position Inertia component with its prop shape" do
      _, user = setup
      create(:user_organization_membership, user: user, organization: organization)

      get new_organization_position_path(organization)

      expect(inertia).to render_component(Pages::NEW_USER_ORGANIZATION_POSITION)
      expect(inertia.props.keys).to include("membership", "bills")
    end

    it "offers the current session's unclaimed bills, newest first, up to the index page size" do
      _, user = setup
      create(:user_organization_membership, user: user, organization: organization)
      sway_locale = organization.sway_locale
      older = create(:bill, sway_locale: sway_locale, legislative_session: nil, introduced_date_time_utc: 5.years.ago, scheduled_release_date_utc: nil)
      recent = create(:bill, sway_locale: sway_locale, introduced_date_time_utc: 2.days.ago, scheduled_release_date_utc: nil)
      claimed = create(:bill, sway_locale: sway_locale, introduced_date_time_utc: 3.days.ago, scheduled_release_date_utc: nil)
      create(:organization_bill_position, organization: organization, bill: claimed, active: true)

      get new_organization_position_path(organization)

      ids = inertia.props[:bills].pluck("id")
      expect(ids).to include(recent.id)
      expect(ids).not_to include(older.id)
      expect(ids).not_to include(claimed.id)
      expect(ids.size).to be <= BillsController::BILLS_INDEX_PAGE_SIZE
    end

    it "issues the same number of queries however many bills the locale holds" do
      _, user = setup
      create(:user_organization_membership, user: user, organization: organization)
      sway_locale = organization.sway_locale

      count_queries = lambda do |&blk|
        query_count = 0
        subscriber =
          ActiveSupport::Notifications.subscribe("sql.active_record") { query_count += 1 }
        blk.call
        ActiveSupport::Notifications.unsubscribe(subscriber)
        query_count
      end #: ^() { () -> untyped } -> Integer

      create_list(:bill, 3, sway_locale: sway_locale, scheduled_release_date_utc: nil)
      # First render loads the column metadata every later one reuses.
      get new_organization_position_path(organization)
      count_few = count_queries.call { get new_organization_position_path(organization) }

      2.times { create_list(:bill, 6, sway_locale: sway_locale, scheduled_release_date_utc: nil) }
      count_many = count_queries.call { get new_organization_position_path(organization) }

      expect(count_many).to eq(count_few),
        "Expected a flat query count (got #{count_few} for 3 bills, #{count_many} for 15) — N+1 detected"
    end
  end
end
