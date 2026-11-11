# frozen_string_literal: true

require "rails_helper"

# @lat: [[bills-deferred-reload-diagnostic-suite#Why the nil-locale example fires the reload by hand instead of using inertia_load_deferred_props]]
RSpec.describe "Bills deferred `bills` reload (diagnostic)", type: :request do
  let!(:sway_locale) do
    SwayLocale.find_by(city: "baltimore", state: "MD", country: "United States") ||
      create(:sway_locale, city: "baltimore", state: "MD", country: "United States")
  end
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }

  let!(:housing) { create(:category, name: "Housing", active: true) }
  let!(:public_safety) { create(:category, name: "Public Safety", active: true) }

  let!(:housing_bill) do
    create(:bill, sway_locale: sway_locale, legislator: legislator, title: "Housing Act One",
      scheduled_release_date_utc: 3.days.ago).tap do |b|
      create(:bill_category, bill: b, category: housing)
    end
  end
  let!(:safety_bill) do
    create(:bill, sway_locale: sway_locale, legislator: legislator, title: "Safety Act Two",
      scheduled_release_date_utc: 5.days.ago).tap do |b|
      create(:bill_category, bill: b, category: public_safety)
    end
  end

  # @lat: [[steep-typed-spec-helpers#let and def inside a describe block#Accepting the gap with steep:ignore instead of moving the helper out]]
  # steep:ignore:start
  def bill_titles(props)
    Array(props[:bills]).map { |b| b["title"] || b[:title] }
  end
  # steep:ignore:end

  describe "1. baseline — bare /bills" do
    it "marks bills as a deferred prop (so the client <Deferred> will fire)" do
      get "/bills", params: {sway_locale_id: sway_locale.id}

      expect(inertia).to render_component(Pages::BILLS)
      expect(inertia).to have_deferred_props(:bills)
    end

    it "returns both bills on the deferred reload" do
      get "/bills", params: {sway_locale_id: sway_locale.id}
      inertia_load_deferred_props

      expect(bill_titles(inertia.props)).to contain_exactly("Housing Act One", "Safety Act Two") # steep:ignore
    end
  end

  describe "2. with the ?categories=Housing param (filtering is client-side, so the server still returns ALL bills)" do
    it "still marks bills deferred with the categories param present" do
      get "/bills", params: {sway_locale_id: sway_locale.id, categories: "Housing"}

      expect(inertia).to have_deferred_props(:bills)
    end

    it "returns both bills on the deferred reload of the filtered URL" do
      get "/bills", params: {sway_locale_id: sway_locale.id, categories: "Housing"}
      inertia_load_deferred_props

      # The server does NOT filter by category. The chips filter in the browser
      # over the deferred list, so both bills come back. What matters is that
      # the payload is not empty, so the browser has something to filter.
      expect(bill_titles(inertia.props)).to contain_exactly("Housing Act One", "Safety Act Two") # steep:ignore
    end
  end

  describe "3. navigate away to a bill detail, then BACK to the filtered URL (the exact sequence)" do
    it "still returns bills on the deferred reload after the round-trip" do
      # First /bills visit plus its deferred load — the page the browser test
      # starts on.
      get "/bills", params: {sway_locale_id: sway_locale.id}
      inertia_load_deferred_props
      expect(bill_titles(inertia.props)).to include("Housing Act One") # steep:ignore

      # Leave the list entirely for the bill-detail page, as `visit "/bills/:id"` does.
      get "/bills/#{housing_bill.id}"
      expect(response).to have_http_status(:ok)

      # Navigate back to the filtered URL exactly as the browser would.
      get "/bills", params: {sway_locale_id: sway_locale.id, categories: "Housing"}
      expect(inertia).to render_component(Pages::BILLS)
      expect(inertia).to have_deferred_props(:bills)

      # The assertion that matters: after the detour through the bill detail,
      # the deferred bills reload at the filtered URL still returns the bills.
      # If this passes, the stall is not in the server.
      inertia_load_deferred_props
      expect(bill_titles(inertia.props)).to contain_exactly("Housing Act One", "Safety Act Two") # steep:ignore
    end
  end

  describe "4. asset-version handling on the partial `bills` reload" do
    # @lat: [[bills-deferred-reload-diagnostic-suite#The stale-asset-version hypothesis]]
    it "returns 409 Conflict when the partial reload carries a STALE asset version (candidate stall mechanism)" do
      get "/bills", params: {sway_locale_id: sway_locale.id, categories: "Housing"}

      # A <Deferred> reload whose asset version no longer matches the server's.
      get "/bills",
        params: {sway_locale_id: sway_locale.id, categories: "Housing"},
        headers: {
          "X-Inertia" => "true",
          "X-Inertia-Version" => "stale-version-from-a-prior-asset-build",
          "X-Inertia-Partial-Component" => "Bills",
          "X-Inertia-Partial-Data" => "bills"
        }

      # @lat: [[bills-deferred-reload-diagnostic-suite#The stale-asset-version hypothesis]]
      expect(response).to have_http_status(:conflict)
    end
  end

  # @lat: [[bill-score-builder-variants#Why BillsController.index preloads bill_score_districts]]
  describe "5. bill_score_districts preload (no per-bill N+1)" do
    before do
      3.times do |i|
        # Give each bill its own scheduled_release_date_utc: that column plus
        # sway_locale_id is a unique index, and 3 and 5 days ago are already
        # used above.
        scored = create(:bill, sway_locale: sway_locale, legislator: legislator,
          title: "Scored Bill #{i}", scheduled_release_date_utc: (100 + i).days.ago)
        score = create(:bill_score, bill: scored)
        create(:bill_score_district, bill_score: score, district: district)
      end
    end

    it "loads bill_score_districts in one batched query, not once per bill" do
      get "/bills", params: {sway_locale_id: sway_locale.id}

      bsd_queries = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        sql = payload[:sql].to_s
        next if payload[:name].to_s == "SCHEMA"
        bsd_queries += 1 if sql.match?(/FROM\s+["'`]?bill_score_districts["'`]?/i)
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        inertia_load_deferred_props
      end

      # One query with WHERE bill_score_id IN (...) — it used to be 3, one per scored bill.
      expect(bsd_queries).to eq(1)
    end
  end

  # The hoisted user_districts line calls current_sway_locale.at_large_district.
  # current_sway_locale is nil when no locale can be worked out — logged out, no
  # param, no cookie, no congress fallback — and the older per-bill code never
  # touched it. The deferred reload must not 500 in that case.
  describe "6. nil current_sway_locale (no locale resolvable)" do
    it "serves the deferred bills reload without a NoMethodError" do
      # Force the last fallback, SwayLocale.default_locale, to nil. With no
      # param, no cookie and no signed-in user, current_sway_locale is then nil.
      allow(SwayLocale).to receive(:default_locale).and_return(nil)

      get "/bills" # no sway_locale_id param
      expect(inertia).to render_component(Pages::BILLS)

      # @lat: [[bills-deferred-reload-diagnostic-suite#Why the nil-locale example fires the reload by hand instead of using inertia_load_deferred_props]]
      asset_version = InertiaRails.configuration.version.to_s
      get "/bills", headers: {
        "X-Inertia" => "true",
        "X-Inertia-Version" => asset_version,
        "X-Inertia-Partial-Component" => inertia.component,
        "X-Inertia-Partial-Data" => "bills"
      }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("props", "bills")).to eq([]) # nil locale -> no bills, no crash
    end
  end
end
