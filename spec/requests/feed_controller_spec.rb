# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FeedController", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "GET /feed" do
    context "when signed out" do
      it "redirects to root_path with a sign-in notice" do
        get "/feed"

        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("Sign up or sign in to view this page.")
      end
    end

    context "when signed in" do
      it "renders Pages::FEED with serialized items, scroll metadata, and feed_search" do
        sway_locale, user = setup
        user.complete!
        district = create(:district, sway_locale:)
        legislator = create(:legislator, district:)
        create(:user_legislator, user: user, legislator: legislator, active: true)
        create(:bill, sway_locale: sway_locale, legislator: legislator, title: "Clean Water Act")

        get "/feed"

        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component Pages::FEED

        props = inertia.props
        feed_search = props.key?(:feed_search) ? props[:feed_search] : props["feed_search"]
        expect(feed_search).to be_nil
        expect(props).not_to have_key(:next_cursor)
        expect(props).not_to have_key("next_cursor")

        items = props[:items] || props["items"]
        expect(items).to be_an(Array)
        expect(items.map { |item| item[:kind] || item["kind"] }).to include("user_joined", "representatives_found")
        first_item = items.first
        expect(first_item.keys.map(&:to_sym)).to include(:key, :kind, :occurred_at)

        scroll_meta = props.dig(:scrollProps, :items) ||
          props.dig("scrollProps", "items") ||
          inertia.instance_variable_get(:@scroll_props)&.dig(:items) ||
          inertia.instance_variable_get(:@scroll_props)&.dig("items")
        if scroll_meta
          expect(scroll_meta[:pageName] || scroll_meta["pageName"]).to eq("feed_cursor")
          expect(scroll_meta[:previousPage] || scroll_meta["previousPage"]).to be_nil
        end
      end

      it "filters items when feed_search is provided" do
        _sway_locale, user = setup
        user.complete!
        create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
        baltimore = user.sway_locales.find(&:declared?)
        district = create(:district, sway_locale: baltimore)
        legislator = create(:legislator, district:, sway_locale: baltimore, first_name: "Ada", last_name: "Lovelace")
        create(:user_legislator, user: user, legislator: legislator, active: true)
        matching_bill = create(
          :bill,
          sway_locale: baltimore,
          legislator: legislator,
          title: "Solar Energy Expansion",
          scheduled_release_date_utc: Date.current
        )
        other_bill = create(
          :bill,
          sway_locale: baltimore,
          legislator: legislator,
          title: "Highway Maintenance",
          scheduled_release_date_utc: 1.day.ago.to_date
        )

        get "/feed", params: {feed_search: "Solar"}

        expect(response).to have_http_status(:ok)
        props = inertia.props
        expect(props[:feed_search] || props["feed_search"]).to eq("Solar")
        items = props[:items] || props["items"]
        keys = items.map { |item| item[:key] || item["key"] }
        expect(keys).to include("bill_of_the_month_released:#{matching_bill.id}")
        expect(keys).not_to include("bill_of_the_month_released:#{other_bill.id}")
      end

      it "paginates with feed_cursor and returns the next page" do
        _sway_locale, user = setup
        user.complete!
        create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
        baltimore = user.sway_locales.find(&:declared?)
        district = create(:district, sway_locale: baltimore)
        legislator = create(:legislator, district:, sway_locale: baltimore)
        create(:user_legislator, user: user, legislator: legislator, active: true)
        FeedQuery::DEFAULT_PER_PAGE.times do |i|
          bill = create(
            :bill,
            sway_locale: baltimore,
            legislator: legislator,
            title: "Bill #{i}",
            house_vote_date_time_utc: (i + 1).hours.ago
          )
          create(:legislator_vote, legislator: legislator, bill: bill, inferred: false, support: "FOR")
        end

        expected_first_page = FeedQuery.new(user: user)
        cursor = expected_first_page.next_cursor
        expect(cursor).to be_present

        get "/feed", params: {feed_cursor: cursor}

        expect(response).to have_http_status(:ok)
        props = inertia.props
        expected_second_page = FeedQuery.new(user: user, cursor: cursor)
        items = props[:items] || props["items"]
        expect(items.map { |item| item[:key] || item["key"] }).to eq(expected_second_page.items.map(&:key))
      end
    end
  end
end
