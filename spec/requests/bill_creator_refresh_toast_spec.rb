# frozen_string_literal: true

require "rails_helper"

# @lat: [[admin-bill-view-cookie-replacement#Why AdminBillView is a row, not a cookie]]
RSpec.describe "BillsController#edit — refresh toast (server-side)", type: :request do
  # /admin/bill_creator/:id/edit only redirects now, so the admin check happens at the
  # real URL it lands on.
  include_examples "requires sway admin",
    verb: :get,
    path: "/admin/bill_creator/1/creator",
    params: {}

  describe "as a Sway admin" do
    include_context "SessionDouble"

    let(:sway_locale) do
      create(:sway_locale, city: "baltimore", state: "maryland",
        country: "united_states")
    end
    let(:district) { create(:district, sway_locale: sway_locale) }
    let(:legislator) { create(:legislator, district: district) }
    let(:bill) { create(:bill, sway_locale: sway_locale, legislator: legislator) }
    let(:admin) { create(:user, :sway_admin) }

    before do
      session_hash[:user_id] = admin.id
      cookies_hash[:sway_locale_id] = sway_locale.id
    end

    it "returns no toast props on first visit (no prior AdminBillView record)" do
      get creator_bill_creator_path(bill)
      expect(inertia).to have_props { |p|
        p[:legislator_votes_refreshed_at].nil? &&
          p[:legislator_votes_source].nil?
      }
    end

    it "persists an AdminBillView row on first visit" do
      expect {
        get creator_bill_creator_path(bill)
      }.to change {
        AdminBillView.where(admin_user_id: admin.id, bill_id: bill.id).count
      }.from(0).to(1)
    end

    # @lat: [[bills-controller-design#legislator_votes_refresh_toast_for]]
    it "does not touch last_seen_at on a repeat visit with nothing new" do
      get creator_bill_creator_path(bill)
      view = AdminBillView.find_by(admin_user_id: admin.id, bill_id: bill.id) #: AdminBillView
      pinned = 1.hour.ago.change(usec: 0)
      view.update_columns(last_seen_at: pinned)

      get creator_bill_creator_path(bill)

      expect(view.reload.last_seen_at).to eq(pinned)
    end

    it "returns toast props when non-manual legislator_votes were updated since last visit" do
      get creator_bill_creator_path(bill) # establish AdminBillView.last_seen_at
      vote = create(:legislator_vote, bill: bill, legislator: legislator, source: "legistar")
      vote.update_columns(updated_at: 5.minutes.from_now)
      get creator_bill_creator_path(bill)
      expect(inertia).to have_props { |p|
        p[:legislator_votes_refreshed_at].present? &&
          p[:legislator_votes_source] == "legistar"
      }
    end

    it "returns no toast props on a follow-up visit when nothing has changed" do
      vote = create(:legislator_vote, bill: bill, legislator: legislator, source: "legistar")
      vote.update_columns(updated_at: 1.minute.ago)
      get creator_bill_creator_path(bill) # first visit — last_seen now
      get creator_bill_creator_path(bill) # second visit — last_seen still in future of vote
      expect(inertia).to have_props { |p|
        p[:legislator_votes_refreshed_at].nil? &&
          p[:legislator_votes_source].nil?
      }
    end

    it "EXCLUDES manual rows from the refresh-detection (admin's own edits don't toast)" do
      get creator_bill_creator_path(bill) # establish AdminBillView
      vote = create(:legislator_vote, bill: bill, legislator: legislator, source: "manual")
      vote.update_columns(updated_at: 5.minutes.from_now)
      get creator_bill_creator_path(bill)
      expect(inertia).to have_props { |p|
        p[:legislator_votes_refreshed_at].nil? &&
          p[:legislator_votes_source].nil?
      }
    end

    # The time in the pop-up is shown in the bill locale's own timezone, taken from
    # sway_locales.time_zone, rather than always Eastern.
    it "renders the refresh-toast time in the bill locale's timezone, not hardcoded Eastern" do
      central_locale = create(:sway_locale, city: "chicago", state: "illinois",
        country: "united_states", time_zone: "America/Chicago")
      central_district = create(:district, sway_locale: central_locale)
      central_legislator = create(:legislator, district: central_district)
      central_bill = create(:bill, sway_locale: central_locale, legislator: central_legislator)
      cookies_hash[:sway_locale_id] = central_locale.id

      get creator_bill_creator_path(central_bill) # establish AdminBillView.last_seen_at
      vote = create(:legislator_vote, bill: central_bill, legislator: central_legislator, source: "legistar")
      vote.update_columns(updated_at: Time.utc(2030, 1, 15, 18, 0, 0))
      get creator_bill_creator_path(central_bill)

      # 18:00 UTC on 2030-01-15 is 12:00 in America/Chicago (CST, no DST);
      # the old hardcoded Eastern would render 13:00.
      expect(inertia).to have_props { |p|
        p[:legislator_votes_refreshed_at] == "12:00"
      }
    end

    # @lat: [[jurisdiction-rules-design#Why the Bill Creator still draws for an undeclared jurisdiction]]
    it "still draws the bill picker for a jurisdiction nobody has declared" do
      undeclared_locale = create(:sway_locale, city: "chicago", state: "illinois",
        country: "united_states", time_zone: "America/Chicago")
      undeclared_district = create(:district, sway_locale: undeclared_locale)
      undeclared_legislator = create(:legislator, district: undeclared_district)
      undeclared_bill = create(:bill, sway_locale: undeclared_locale, legislator: undeclared_legislator)
      cookies_hash[:sway_locale_id] = undeclared_locale.id

      get creator_bill_creator_path(undeclared_bill)

      expect(response).to have_http_status(:ok)
      expect(inertia).to have_props { |p|
        row = p[:bills].find { |b| b[:id] == undeclared_bill.id }
        !row.nil? && row[:interesting_score_normalized].nil? && row[:interesting_badges] == []
      }
    end
  end
end
