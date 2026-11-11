# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Archived bill visibility", type: :request do
  # @type self: ArchivedBillsRequestSpecContext
  include_context "SessionDouble"
  include_context "Setup"

  let!(:locale_and_user) { setup }
  let(:locale) { locale_and_user.first }
  let!(:visible_bill) { create(:bill, sway_locale: locale, scheduled_release_date_utc: nil) }
  let!(:archived_bill) do
    create(:bill, sway_locale: locale, scheduled_release_date_utc: nil, archived_at: Time.current)
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Public list visibility]]
  it "omits archived bills from public counts and deferred list rows" do
    get bills_path
    expect(inertia).to render_component(Pages::BILLS)
    expect(inertia).to have_props(bills_total: 1)
    inertia_load_deferred_props
    expect(inertia).to have_props { |props| props[:bills].pluck(:id) == [visible_bill.id] }
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Admin picker and direct access]]
  it "omits archives from the picker and rejects admin edits while allowing read-only public bill view" do
    get new_bill_creator_path
    expect(inertia).to render_component(Pages::BILL_CREATOR)
    expect(inertia).to have_props { |props| props[:bills].pluck(:id) == [visible_bill.id] }

    get creator_bill_creator_path(archived_bill)
    expect(response).to have_http_status(:not_found)
    get bill_path(archived_bill)
    expect(response).to have_http_status(:ok)
    expect(inertia).to render_component(Pages::BILL)
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Report visibility]]
  it "omits archived summary reports and their counts and rejects their detail routes" do
    visible_report = create(:bill_summary_report, bill: visible_bill)
    archived_report = create(:bill_summary_report, bill: archived_bill)

    get admin_bill_summary_reports_path
    expect(response).to have_http_status(:ok)
    expect(inertia).to render_component(Pages::ADMIN_BILL_SUMMARY_REPORTS)
    expect(inertia).to have_props { |props|
      props[:reports].pluck(:id) == [visible_report.id] && props[:status_counts][:all] == 1
    }
    get admin_bill_summary_report_path(archived_report)
    expect(response).to have_http_status(:not_found)
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Organization visibility]]
  it "hides archived positions and changes and rejects edits and approvals" do
    organization = create(:organization, sway_locale: locale)
    user = locale_and_user.last
    membership = create(:user_organization_membership, :admin, user: user, organization: organization)
    visible_position = create(:organization_bill_position, organization: organization, bill: visible_bill, active: true)
    archived_position = create(:organization_bill_position, organization: organization, bill: archived_bill, active: true)
    change = create(:organization_bill_position_change, organization_bill_position: archived_position, updated_by: user)

    get organization_membership_path(organization, membership)
    expect(response).to have_http_status(:ok)
    expect(inertia).to render_component(Pages::USER_ORGANIZATION_MEMBERSHIP)
    expect(inertia).to have_props { |props|
      props[:membership][:positions].pluck(:id) == [visible_position.id] && props[:membership][:pending_changes].empty?
    }
    get "/public/organizations/#{organization.id}.json"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["organization_bill_positions"].pluck("id")).to eq([visible_position.id])

    get organizations_path(format: :json)
    expect(response.parsed_body.find { |row| row["id"] == organization.id }["positions"].pluck("id")).to eq([visible_position.id])
    get "/organizations/#{organization.id}.json"
    expect(response.parsed_body["positions"].pluck("id")).to eq([visible_position.id])

    delete organization_position_path(organization, archived_position)
    expect(response).to have_http_status(:not_found)
    delete organization_bill_position_path(archived_position)
    expect(response).to have_http_status(:not_found)
    put organization_position_change_path(organization, change)
    expect(response).to have_http_status(:not_found)
    post organization_positions_path(organization), params: {bill_id: archived_bill.id, support: "support"}
    expect(response).to have_http_status(:not_found)
    expect(archived_position.reload.active).to eq(true)
    expect(change.reload.status).to eq("pending")
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Vote visibility]]
  it "omits archived user votes and cannot cast a vote on an archive" do
    user = locale_and_user.last
    visible_vote = create(:user_vote, user: user, bill: visible_bill)
    create(:user_vote, user: user, bill: archived_bill)

    get user_votes_path(format: :json)
    expect(response.parsed_body.pluck("id")).to eq([visible_vote.id])
    get "/user_votes/#{archived_bill.id}.json"
    expect(response).to have_http_status(:no_content)
    expect {
      post user_votes_path, params: {bill_id: archived_bill.id, support: "PRO"}
    }.not_to change(UserVote, :count)
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Queued organization notifications skip archives]]
  it "stands down for a retained organization position after its bill is archived" do
    position = create(:organization_bill_position, bill: archived_bill, active: true)
    allow(NotifyOrganizationFollowersService).to receive(:new)

    NotifyOrganizationFollowersJob.new.perform(position.organization_id, archived_bill.id, ["support"])

    expect(NotifyOrganizationFollowersService).not_to have_received(:new)
  end
end
