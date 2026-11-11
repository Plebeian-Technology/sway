# frozen_string_literal: true

require "rails_helper"
require "support/query_plan_helpers"

RSpec.describe "Query plans after the redundant single-column indexes were dropped" do
  # @type var covered_by_a_composite: Array[[untyped, Symbol, String]]
  covered_by_a_composite = [
    [UserVote, :user_id, "index_user_votes_on_user_id_and_bill_id"],
    [BillScoreDistrict, :bill_score_id, "index_bill_score_districts_on_bs_and_district"],
    [UserLegislator, :user_id, "by_unique_user_and_legislator"],
    [AdminBillView, :admin_user_id, "index_admin_bill_views_on_admin_user_and_bill"],
    [BillCategory, :bill_id, "index_bill_categories_on_bill_id_and_category_id"],
    [NotificationPreference, :user_id, "index_notification_preferences_on_user_id_and_key"],
    [OrganizationFollow, :user_id, "idx_organization_follows_on_user_and_organization"],
    [PushNotificationSubscription, :user_id, "index_push_notification_subscriptions_on_user_id_and_endpoint"],
    [SendingServiceDomainBill, :sending_service_domain_id, "index_sending_service_domain_bills_on_domain_and_bill"]
  ]

  covered_by_a_composite.each do |model, column, composite_name|
    it "searches #{composite_name} for #{model.table_name} by #{column}" do
      details = query_plan_details(model.where(column => 1))

      expect(details).to include(
        a_string_including("SEARCH #{model.table_name}").and(a_string_including(composite_name))
      )
    end
  end

  # @lat: [[query-plan-indexes#Single-column indexes a composite already covers]]
  it "searches the bill lookup index when vote uniqueness indexes are partial" do
    details = query_plan_details(LegislatorVote.where(bill_id: 1))

    expect(details).to include(
      a_string_including("SEARCH legislator_votes").and(a_string_including("index_legislator_votes_on_bill_id"))
    )
    expect(details).not_to include(a_string_including("SCAN legislator_votes"))
  end

  it "searches an index for the organizations page's following filter" do
    user = create(:user)

    following = Organization.joins(:organization_follows)
      .where(organization_follows: {user_id: user.id})
      .order(:name)
      .limit(100)

    details = query_plan_details(following)

    expect(details).to include(a_string_including("SEARCH organization_follows"))
    expect(details).not_to include(a_string_including("SCAN organization_follows"))
  end
end
