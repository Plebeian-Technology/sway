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

      it "returns 401 JSON for an unauthenticated JSON request" do
        get "/feed", headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:unauthorized)
        expect(response.content_type).to include("application/json")
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

      it "omits newest_keys on initial load and returns first-page keys on partial reload ignoring feed_cursor" do
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

        get "/feed"
        expect(response).to have_http_status(:ok)
        expect(inertia.props).not_to have_key(:newest_keys)
        expect(inertia.props).not_to have_key("newest_keys")

        expected_first_page = FeedQuery.new(user: user)
        cursor = expected_first_page.next_cursor
        expect(cursor).to be_present

        get "/feed",
          params: {feed_cursor: cursor},
          headers: {
            "X-Inertia" => "true",
            "X-Inertia-Version" => InertiaRails.configuration.version,
            "X-Inertia-Partial-Component" => Pages::FEED,
            "X-Inertia-Partial-Data" => "newest_keys"
          }

        expect(response).to have_http_status(:ok)
        newest_keys = inertia.props[:newest_keys] || inertia.props["newest_keys"]
        expect(newest_keys).to eq(expected_first_page.items.map(&:key))
      end

      it "filters newest_keys by feed_search on partial reload" do
        _sway_locale, user = setup
        user.complete!
        create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
        baltimore = user.sway_locales.find(&:declared?)
        district = create(:district, sway_locale: baltimore)
        legislator = create(:legislator, district:, sway_locale: baltimore)
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

        get "/feed",
          params: {feed_search: "Solar"},
          headers: {
            "X-Inertia" => "true",
            "X-Inertia-Version" => InertiaRails.configuration.version,
            "X-Inertia-Partial-Component" => Pages::FEED,
            "X-Inertia-Partial-Data" => "newest_keys"
          }

        expect(response).to have_http_status(:ok)
        newest_keys = inertia.props[:newest_keys] || inertia.props["newest_keys"]
        expect(newest_keys).to include("bill_of_the_month_released:#{matching_bill.id}")
        expect(newest_keys).not_to include("bill_of_the_month_released:#{other_bill.id}")
      end

      it "includes bulk-loaded vote_count, view_count, and share_count on bills with constant count queries" do
        _sway_locale, user = setup
        user.complete!
        create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
        baltimore = user.sway_locales.find(&:declared?)
        district = create(:district, sway_locale: baltimore)
        legislator = create(:legislator, district:, sway_locale: baltimore)
        create(:user_legislator, user: user, legislator: legislator, active: true)
        sharer_one = create(:user)
        sharer_two = create(:user)

        create_counted_bill = lambda do |idx, with_counts:|
          bill = create(
            :bill,
            sway_locale: baltimore,
            legislator: legislator,
            title: "Counted Bill #{idx}",
            house_vote_date_time_utc: idx.hours.ago
          )
          create(:legislator_vote, legislator: legislator, bill: bill, inferred: false, support: "FOR")
          if with_counts
            create(:bill_score, bill: bill, for: 4, against: 3)
            BillView.record_for(user: sharer_one, bill: bill)
            BillView.record_for(user: sharer_two, bill: bill)
            create(:user_bill_share, bill: bill, user: sharer_one)
            create(:user_bill_share, bill: bill, user: sharer_two)
          end
          bill
        end

        count_queries_for_request = lambda do
          count_queries = 0
          counter = lambda do |*, payload|
            sql = payload[:sql].to_s
            next if %w[SCHEMA TRANSACTION].include?(payload[:name])

            count_queries += 1 if sql.match?(/FROM\s+"(?:bill_scores|bill_views|user_bill_shares)"/i)
          end
          ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
            get "/feed"
          end
          count_queries
        end

        counted_bill = create_counted_bill.call(1, with_counts: true)
        uncounted_bill = create_counted_bill.call(2, with_counts: false)

        two_bill_count_queries = count_queries_for_request.call
        expect(response).to have_http_status(:ok)

        items = inertia.props[:items] || inertia.props["items"]
        counted_item = items.find { |item| (item.dig(:bill, :id) || item.dig("bill", "id")) == counted_bill.id }
        uncounted_item = items.find { |item| (item.dig(:bill, :id) || item.dig("bill", "id")) == uncounted_bill.id }

        expect(counted_item.dig(:bill, :vote_count) || counted_item.dig("bill", "vote_count")).to eq(7)
        expect(counted_item.dig(:bill, :view_count) || counted_item.dig("bill", "view_count")).to eq(2)
        expect(counted_item.dig(:bill, :share_count) || counted_item.dig("bill", "share_count")).to eq(2)
        expect(uncounted_item.dig(:bill, :vote_count) || uncounted_item.dig("bill", "vote_count")).to eq(0)
        expect(uncounted_item.dig(:bill, :view_count) || uncounted_item.dig("bill", "view_count")).to eq(0)
        expect(uncounted_item.dig(:bill, :share_count) || uncounted_item.dig("bill", "share_count")).to eq(0)

        4.times { |i| create_counted_bill.call(i + 3, with_counts: true) }
        six_bill_count_queries = count_queries_for_request.call

        expect(two_bill_count_queries).to eq(3)
        expect(six_bill_count_queries).to eq(two_bill_count_queries)
      end
    end

    context "when signed in via bearer token (mobile JSON)" do
      it "returns items with counts, feed_cursor, and feed_search without newest_keys" do
        _sway_locale, user = setup
        user.complete!
        create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
        baltimore = user.sway_locales.find(&:declared?)
        district = create(:district, sway_locale: baltimore)
        legislator = create(:legislator, district:, sway_locale: baltimore)
        create(:user_legislator, user: user, legislator: legislator, active: true)
        bill = create(
          :bill,
          sway_locale: baltimore,
          legislator: legislator,
          title: "Transit Access Act",
          scheduled_release_date_utc: Date.current
        )
        create(:bill_score, bill: bill, for: 3, against: 2)
        BillView.record_for(user: user, bill: bill)
        create(:user_bill_share, bill: bill, user: user)

        raw_token = "feed-mobile-#{SecureRandom.hex(8)}"
        ApiKey.create!(bearer: user, token: raw_token)

        get "/feed", headers: {"Authorization" => "Bearer #{raw_token}", "Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/json")

        body = response.parsed_body
        expect(body.keys).to match_array(%w[items feed_cursor feed_search])
        expect(body).not_to have_key("newest_keys")
        expect(body["feed_cursor"]).to be_nil
        expect(body["feed_search"]).to be_nil

        bill_item = body["items"].find { |item| item.dig("bill", "id") == bill.id }
        expect(bill_item["bill"]).to include(
          "vote_count" => 5,
          "view_count" => 1,
          "share_count" => 1
        )
      end

      it "filters with feed_search and pages with feed_cursor" do
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
            title: "Solar Bill #{i}",
            house_vote_date_time_utc: (i + 1).hours.ago
          )
          create(:legislator_vote, legislator: legislator, bill: bill, inferred: false, support: "FOR")
        end
        other_bill = create(
          :bill,
          sway_locale: baltimore,
          legislator: legislator,
          title: "Highway Bill",
          house_vote_date_time_utc: 1.minute.ago
        )
        create(:legislator_vote, legislator: legislator, bill: other_bill, inferred: false, support: "FOR")

        raw_token = "feed-mobile-#{SecureRandom.hex(8)}"
        ApiKey.create!(bearer: user, token: raw_token)
        headers = {"Authorization" => "Bearer #{raw_token}", "Accept" => "application/json"}

        get "/feed", params: {feed_search: "Solar"}, headers: headers

        expect(response).to have_http_status(:ok)
        search_body = response.parsed_body
        expect(search_body["feed_search"]).to eq("Solar")
        expect(search_body["items"].map { |item| item.dig("bill", "id") }).not_to include(other_bill.id)

        get "/feed", headers: headers

        expect(response).to have_http_status(:ok)
        page_one = response.parsed_body
        next_cursor = page_one["feed_cursor"]
        expect(next_cursor).to be_present

        get "/feed", params: {feed_cursor: next_cursor}, headers: headers

        expect(response).to have_http_status(:ok)
        page_two = response.parsed_body
        expected_second_page = FeedQuery.new(user: user, cursor: next_cursor)
        expect(page_two["items"].pluck("key")).to eq(expected_second_page.items.map(&:key))
      end
    end
  end
end
