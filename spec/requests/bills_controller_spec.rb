require "rails_helper"

module BillsControllerSpecHelpers
  def self.seat_legislator(district, first_name, last_name, **term_dates)
    legislator = FactoryBot.create(:legislator, district:, first_name:, last_name:)
    dates = {
      began_on: Date.current - 1.year,
      ended_on: Date.current + 1.year,
      began_on_source: LegislatorTerm::DateSource::OBSERVED,
      ended_on_source: LegislatorTerm::DateSource::OBSERVED
    }.merge(term_dates)
    FactoryBot.create(:legislator_term, legislator:, district:, **dates)
    legislator
  end
end

RSpec.describe "BillsController", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:build_bill_params) do
    lambda do |sway_locale, partial_bill: {}, partial_sponsor: {}, partial_vote: {}|
      # @type var partial_bill: Hash[Symbol, untyped]
      # @type var partial_sponsor: Hash[Symbol, untyped]
      # @type var partial_vote: Hash[Symbol, untyped]
      legislator = create(:legislator)
      bill = build(:bill, legislator:, sway_locale:, summary: "Tacos are great")

      [
        bill,
        {
          external_id: bill.external_id,
          external_version: bill.external_version,
          title: bill.title,
          link: bill.link,
          chamber: bill.chamber,
          introduced_date_time_utc:
            (bill.introduced_date_time_utc - 1.day)&.to_s,
          house_vote_date_time_utc: bill.house_vote_date_time_utc&.to_s,
          senate_vote_date_time_utc: bill.senate_vote_date_time_utc&.to_s,
          summary: bill.summary,
          status: bill.status,
          active: true,
          audio_bucket_path: bill.audio_bucket_path,
          audio_by_line: bill.audio_by_line,
          sway_locale_id: sway_locale.id,
          legislator_id: legislator.id,
          house_roll_call_vote_number: 1,
          senate_roll_call_vote_number: 2,
          **partial_bill, # must be at end
          **partial_sponsor,
          **partial_vote
        }
      ]
    end
  end

  describe "GET /index" do
    it "renders the Bills component" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      get "/bills"

      expect(inertia).to render_component Pages::BILLS
    end

    it "defers the bills prop" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      get "/bills"

      expect(inertia).to have_deferred_props(:bills)
    end

    it "loads deferred bills data" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      get "/bills"
      inertia_load_deferred_props

      expect(inertia).to have_props { |p| p[:bills].is_a?(Array) }
    end

    # @lat: [[lazy-inertia-props#Mobile JSON omission is an explicit request]]
    it "keeps the deferred bills list resolved when the header names it" do
      sway_locale, user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!
      api_token = SecureRandom.hex(32)
      ApiKey.create!(bearer: user, token: api_token)

      get "/bills", headers: {
        "Authorization" => "Bearer #{api_token}",
        "X-Sway-Omit-Props" => "bills, legislators"
      }

      expect(response.parsed_body.fetch("bills").pluck("id")).to include(bill.id)
    end

    # The user_votes lookup lives inside the InertiaRails.defer block, so the
    # first /bills response runs no user_votes query at all. That query only
    # runs later, when the browser asks for the deferred `bills` prop in a
    # second request.
    it "runs no user_votes query on the initial index render" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      user_vote_queries = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        next if payload[:name].to_s == "SCHEMA"
        user_vote_queries += 1 if payload[:sql].to_s.match?(/FROM\s+["'`]?user_votes["'`]?/i)
      end
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        get "/bills"
      end

      expect(inertia).to render_component(Pages::BILLS)
      expect(user_vote_queries).to eq(0)
    end

    it "still carries user_vote on each bill in the deferred payload" do
      sway_locale, user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!
      create(:user_vote, user: user, bill: bill)

      get "/bills"
      inertia_load_deferred_props

      bills = Array(inertia.props[:bills]) #: Array[untyped]
      user_votes = bills.pluck(:user_vote)
      expect(user_votes.compact).not_to be_empty
    end

    it "includes bill_score totals for each bill in the deferred payload" do
      sway_locale, user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!
      user_vote =
        UserVote.create!(
          user: user,
          bill: bill,
          support: LegislatorVote::Support::FOR
        )
      ScoreUpdaterService.new(user_vote).call

      get "/bills"
      inertia_load_deferred_props

      bill_payload = inertia.props[:bills].find { |entry| entry["id"] == bill.id }

      expect(bill_payload.dig("bill_score", "for")).to eq(1)
      expect(bill_payload.dig("bill_score", "against")).to eq(0)
    end

    it "passes the filters prop" do
      _, _user = setup

      get "/bills", params: {search: "charter"}

      expect(inertia).to have_props(
        filters: {
          search: "charter",
          sort: nil,
          direction: nil
        }
      )
    end

    it "defaults /bills to the current active legislative session and allows browsing historical sessions" do
      sway_locale, _user = setup
      active_session = create(:legislative_session, sway_locale: sway_locale, name: "2026 Regular Session", active: true)
      historical_session = create(:legislative_session, sway_locale: sway_locale, name: "2024 Regular Session", active: false)

      current_bill, _params = build_bill_params.call(sway_locale)
      current_bill.legislative_session = active_session
      current_bill.save!

      historical_bill, _params = build_bill_params.call(sway_locale)
      historical_bill.legislative_session = historical_session
      historical_bill.archived_at = Time.current
      historical_bill.save!

      get "/bills"
      expect(inertia).to have_props(
        list_mode: "all_bills",
        selected_legislative_session_id: active_session.id,
        bills_total: 1
      )
      inertia_load_deferred_props
      expect(inertia.props[:bills].pluck("id")).to eq([current_bill.id])

      get "/bills", params: {bills_legislative_session_id: historical_session.id}
      expect(inertia).to have_props(
        list_mode: "all_bills",
        selected_legislative_session_id: historical_session.id,
        bills_total: 1
      )
      inertia_load_deferred_props
      expect(inertia.props[:bills].pluck("id")).to eq([historical_bill.id])

      other_locale = create(:sway_locale, city: "Annapolis", state: "Maryland", country: "United States")
      foreign_session = create(:legislative_session, sway_locale: other_locale, name: "Foreign Session", active: false)
      foreign_bill, _params = build_bill_params.call(other_locale)
      foreign_bill.legislative_session = foreign_session
      foreign_bill.save!

      get "/bills", params: {bills_legislative_session_id: foreign_session.id}
      expect(inertia).to have_props(
        list_mode: "all_bills",
        selected_legislative_session_id: active_session.id,
        bills_total: 1
      )
      inertia_load_deferred_props
      expect(inertia.props[:bills].pluck("id")).to eq([current_bill.id])
    end

    it "shows only past Bills of the Month on GET /past_bills_of_the_month" do
      sway_locale, _user = setup
      past_botm, _params = build_bill_params.call(sway_locale)
      past_botm.scheduled_release_date_utc = Time.zone.today - 7.days
      past_botm.save!

      current_botm, _params = build_bill_params.call(sway_locale)
      current_botm.scheduled_release_date_utc = Time.zone.today
      current_botm.save!

      unscheduled_bill, _params = build_bill_params.call(sway_locale)
      unscheduled_bill.scheduled_release_date_utc = nil
      unscheduled_bill.save!

      get "/past_bills_of_the_month"

      expect(inertia).to render_component(Pages::BILLS)
      expect(inertia).to have_props(
        list_mode: "past_bills_of_the_month",
        selected_legislative_session_id: nil,
        bills_total: 1
      )
      inertia_load_deferred_props
      expect(inertia.props[:bills].pluck("id")).to eq([past_botm.id])
    end

    # @lat: [[bills-controller-design#The web bills index grows a stable page window]]
    describe "page window" do
      before { stub_const("BillsController::BILLS_INDEX_PAGE_SIZE", 2) }

      # A plain method, not let!. Steep (the Ruby type checker) cannot see
      # names that let! defines, so this one's signature is written by hand in
      # sig-test/object_spec_methods.rbs.
      def seed_window_bills(count = 3)
        sway_locale, _user = setup
        count.times do |i|
          bill, _params = build_bill_params.call(sway_locale)
          # The database forbids two bills in the same locale from sharing a
          # scheduled_release_date_utc, so give each one a different day.
          bill.scheduled_release_date_utc = Date.current + (i + 1).days
          bill.save!
        end
        sway_locale
      end

      it "windows the deferred bills to one page by default and ships the eager total" do
        seed_window_bills

        get "/bills"
        expect(inertia).to have_props { |p| expect(p[:bills_total]).to eq(3) }

        inertia_load_deferred_props
        expect(inertia).to have_props { |p| expect(p[:bills].length).to eq(2) }
      end

      it "grows the window cumulatively with ?page=2" do
        seed_window_bills

        get "/bills", params: {page: 2}
        inertia_load_deferred_props

        expect(inertia).to have_props { |p| expect(p[:bills].length).to eq(3) }
      end

      it "treats a garbage page param as page 1" do
        seed_window_bills

        get "/bills", params: {page: "garbage"}
        inertia_load_deferred_props

        expect(inertia).to have_props { |p| expect(p[:bills].length).to eq(2) }
      end

      it "keeps the full-list contract on the JSON branch when no page is sent (mobile)" do
        seed_window_bills

        get "/bills", headers: {"Accept" => "application/json"}

        expect(response.parsed_body["bills"].length).to eq(3)
        expect(response.parsed_body["bills_total"]).to eq(3)
      end

      it "lets a JSON caller opt into the window with an explicit page param" do
        seed_window_bills

        get "/bills", params: {page: 1}, headers: {"Accept" => "application/json"}

        expect(response.parsed_body["bills"].length).to eq(2)
      end

      it "search-filters bills_total so the window and total can never disagree" do
        sway_locale = seed_window_bills
        bill, _params = build_bill_params.call(sway_locale)
        bill.title = "Windowed Charter Search Target"
        bill.scheduled_release_date_utc = Date.current + 30.days
        bill.save!

        get "/bills", params: {search: "Windowed Charter"}

        expect(inertia).to have_props { |p| expect(p[:bills_total]).to eq(1) }
      end
    end

    describe "title search" do
      def search_titles(sway_locale, titles, search)
        titles.each_with_index do |title, index|
          bill, _params = build_bill_params.call(sway_locale)
          bill.title = title
          bill.scheduled_release_date_utc = Date.current + (index + 1).days
          bill.save!
        end

        get "/bills", params: {bills_search: search}
        inertia_load_deferred_props
        inertia.props[:bills].pluck("title")
      end

      it "matches a percent sign as text" do
        sway_locale, _user = setup

        expect(search_titles(sway_locale, ["50% Rent Cap", "500 Units"], "50%")).to eq(["50% Rent Cap"])
      end

      it "matches an underscore as text" do
        sway_locale, _user = setup

        expect(search_titles(sway_locale, ["The a_b Act", "The aXb Act"], "a_b")).to eq(["The a_b Act"])
      end

      it "matches a backslash as text" do
        sway_locale, _user = setup

        expect(search_titles(sway_locale, ["Path a\\b Act", "Path ab Act"], "a\\b")).to eq(["Path a\\b Act"])
      end

      it "does not treat a backslash in the search as an escape for an underscore" do
        sway_locale, _user = setup

        expect(search_titles(sway_locale, ["Path a\\xb Act", "Path a_b Act"], "a_b")).to eq(["Path a_b Act"])
      end
    end

    # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
    describe "query parameter namespacing and dual-reading" do
      before { stub_const("BillsController::BILLS_INDEX_PAGE_SIZE", 2) }

      def seed_namespaced_bills
        sway_locale, _user = setup
        b1, _params = build_bill_params.call(sway_locale)
        b1.title = "Alpha Bill"
        b1.introduced_date_time_utc = Time.zone.parse("2026-01-01 10:00:00")
        b1.scheduled_release_date_utc = Date.current + 1.day
        b1.save!

        b2, _params = build_bill_params.call(sway_locale)
        b2.title = "Beta Bill"
        b2.introduced_date_time_utc = Time.zone.parse("2026-01-02 10:00:00")
        b2.scheduled_release_date_utc = Date.current + 2.days
        b2.save!

        b3, _params = build_bill_params.call(sway_locale)
        b3.title = "Gamma Bill"
        b3.introduced_date_time_utc = Time.zone.parse("2026-01-03 10:00:00")
        b3.scheduled_release_date_utc = Date.current + 3.days
        b3.save!

        sway_locale
      end

      it "orders, windows, and filters using canonical bills_* parameters" do
        seed_namespaced_bills

        get "/bills", params: {
          bills_sort: "title",
          bills_direction: "asc",
          bills_page: 2,
          bills_search: "Bill"
        }

        expect(inertia).to have_props(
          filters: {
            search: "Bill",
            sort: "title",
            direction: "asc"
          }
        )
        expect(inertia).to have_props { |p| expect(p[:bills_total]).to eq(3) }

        inertia_load_deferred_props
        titles = inertia.props[:bills].pluck("title")
        expect(titles).to eq(["Alpha Bill", "Beta Bill", "Gamma Bill"])
      end

      it "falls back to bare legacy parameters when canonical parameters are absent" do
        seed_namespaced_bills

        get "/bills", params: {
          sort: "title",
          direction: "asc",
          page: 2,
          search: "Bill"
        }

        expect(inertia).to have_props(
          filters: {
            search: "Bill",
            sort: "title",
            direction: "asc"
          }
        )
        expect(inertia).to have_props { |p| expect(p[:bills_total]).to eq(3) }

        inertia_load_deferred_props
        titles = inertia.props[:bills].pluck("title")
        expect(titles).to eq(["Alpha Bill", "Beta Bill", "Gamma Bill"])
      end

      it "gives precedence to canonical bills_* parameters over legacy aliases" do
        seed_namespaced_bills

        get "/bills", params: {
          bills_sort: "title",
          sort: "introduced_date_time_utc",
          bills_direction: "asc",
          direction: "desc",
          bills_page: 1,
          page: 2,
          bills_search: "Alpha",
          search: "Beta"
        }

        expect(inertia).to have_props(
          filters: {
            search: "Alpha",
            sort: "title",
            direction: "asc"
          }
        )
        expect(inertia).to have_props { |p| expect(p[:bills_total]).to eq(1) }

        inertia_load_deferred_props
        titles = inertia.props[:bills].pluck("title")
        expect(titles).to eq(["Alpha Bill"])
      end

      it "accepts a JSON request body with numbers as JSON numbers alongside form-encoded parameters" do
        seed_namespaced_bills

        get "/bills",
          params: {
            bills_sort: "title",
            bills_direction: "asc",
            bills_page: 2,
            bills_search: "Bill"
          },
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["bills_total"]).to eq(3)
        expect(response.parsed_body["bills"].length).to eq(3)
        titles = response.parsed_body["bills"].pluck("title")
        expect(titles).to eq(["Alpha Bill", "Beta Bill", "Gamma Bill"])
      end
    end

    # The all_categories prop feeds the filter chips and is sent eagerly.
    it "exposes eager all_categories prop (active category names) on first response — no defer load required" do
      _, _user = setup
      create(:category, name: "Environment", active: true)
      create(:category, name: "Housing", active: true)
      create(:category, name: "Inactive Cat", active: false)

      get "/bills"

      # all_categories sits outside InertiaRails.defer, so it rides the first response
      expect(inertia).to have_props { |p|
        expect(p[:all_categories]).to be_an(Array)
        expect(p[:all_categories]).to include("Environment", "Housing")
        expect(p[:all_categories]).not_to include("Inactive Cat")
      }
    end

    it "does NOT include inactive categories in all_categories" do
      _, _user = setup
      create(:category, name: "Active Cat", active: true)
      create(:category, name: "Inactive Cat", active: false)

      get "/bills"

      expect(inertia).to have_props { |p|
        expect(p[:all_categories]).to include("Active Cat")
        expect(p[:all_categories]).not_to include("Inactive Cat")
      }
    end

    it "includes a categories Array on each deferred bill (loaded after inertia_load_deferred_props)" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!
      cat = create(:category, name: "Finance")
      create(:bill_category, bill: bill, category: cat)

      get "/bills"
      inertia_load_deferred_props

      bill_payload = inertia.props[:bills].find { |b| b["id"] == bill.id }
      expect(bill_payload).to be_present
      expect(bill_payload["categories"]).to eq(["Finance"])
    end

    it "issues a constant number of categories-related queries regardless of bill count (no N+1 — T-60-12)" do
      sway_locale, _user = setup

      # Counts the queries that touch the categories or bill_categories tables.
      # It is a proc rather than a method so it can take a block through &blk.
      count_category_queries = lambda do |&blk|
        query_count = 0
        subscriber =
          ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
            sql = payload[:sql].to_s.downcase
            query_count += 1 if sql.include?("categories") || sql.include?("bill_categories")
          end
        blk.call
        ActiveSupport::Notifications.unsubscribe(subscriber)
        query_count
      end #: ^() { () -> untyped } -> Integer

      # First run: one bill with a category. Leave the release date blank so the unique index cannot trip.
      bill_a = create(:bill, sway_locale: sway_locale, external_id: "n1-bill-a", scheduled_release_date_utc: nil)
      cat_x = create(:category, name: "CatX")
      create(:bill_category, bill: bill_a, category: cat_x)

      count_1 = count_category_queries.call do
        get "/bills"
        inertia_load_deferred_props
      end

      # Second run: three more categorized bills, four in all, again with no release date.
      3.times do |i|
        b = create(:bill, sway_locale: sway_locale, external_id: "n1-bill-#{i + 10}", scheduled_release_date_utc: nil)
        create(:bill_category, bill: b, category: cat_x)
      end

      count_n = count_category_queries.call do
        get "/bills"
        inertia_load_deferred_props
      end

      # Preloading a has_many :through costs 2 queries (bill_categories, then categories)
      # no matter how many bills there are — assert that count stays flat.
      expect(count_n).to eq(count_1),
        "Expected constant categories query count (got #{count_1} for 1 bill, #{count_n} for 4 bills) — N+1 detected"
    end
  end

  describe "GET /show" do
    it "gets a bill when passed an id" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!
      locale_legislator_district = create(:district, sway_locale:, name: "D-1")
      locale_legislator =
        create(
          :legislator,
          district: locale_legislator_district
        )
      # The legislators prop on /bills#show keeps only legislators who are
      # currently serving, worked out from their terms — the old `active`
      # column is gone. Give this one a term so it still counts as serving.
      create(
        :legislator_term,
        legislator: locale_legislator,
        district: locale_legislator_district,
        began_on: Date.new(2025, 1, 3),
        ended_on: Date.new(2027, 1, 3),
        began_on_source: LegislatorTerm::DateSource::OBSERVED,
        ended_on_source: LegislatorTerm::DateSource::OBSERVED
      )

      get "/bills/#{bill.id}", headers: {"X-Sway-Omit-Props" => "legislators"}

      expect(inertia).to render_component Pages::BILL
      expect(response.headers.fetch("Vary", "")).not_to include("X-Sway-Omit-Props")
      empty_values = []
      # @type var empty_values: Array[untyped]
      expect(inertia).to have_props(
        {
          bill: BillResource.new(bill).serializable_hash.as_json,
          organizations: empty_values,
          user_vote: nil
        }
      )
      expect(inertia.props.keys).not_to include("legislator_votes", "districts")
      expect(inertia.props.keys).not_to include("legislators")

      inertia_versioned_reload_only("legislators")
      expect(inertia.props[:legislators]).to include(
        locale_legislator.to_sway_json.as_json
      )
    end

    it "keeps the roster in the legacy JSON response when no omission header is sent" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!
      district = create(:district, sway_locale: sway_locale, name: "D-1")
      legislator = create(:legislator, district: district)
      create(
        :legislator_term,
        legislator: legislator,
        district: district,
        began_on: Date.new(2025, 1, 3),
        ended_on: Date.new(2027, 1, 3),
        began_on_source: LegislatorTerm::DateSource::OBSERVED,
        ended_on_source: LegislatorTerm::DateSource::OBSERVED
      )

      get "/bills/#{bill.id}", headers: {
        "Accept" => "application/json"
      }

      expect(response.parsed_body["legislators"].pluck("id")).to include(legislator.id)
      expect(response.parsed_body).to have_key("legislator_votes")
      expect(response.parsed_body).to have_key("districts")
      expect(response.headers.fetch("Vary", "").split(",").map(&:strip)).to include("X-Sway-Omit-Props")
    end

    # @lat: [[lazy-inertia-props#Mobile JSON omission is an explicit request]]
    it "omits named optional bill props for a bearer request and preserves Vary tokens" do
      sway_locale, user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!
      district = create(:district, sway_locale:, name: "D-1")
      legislator = create(:legislator, district:)
      create(
        :legislator_term,
        legislator:,
        district:,
        began_on: Date.new(2025, 1, 3),
        ended_on: Date.new(2027, 1, 3),
        began_on_source: LegislatorTerm::DateSource::OBSERVED,
        ended_on_source: LegislatorTerm::DateSource::OBSERVED
      )
      api_token = SecureRandom.hex(32)
      ApiKey.create!(bearer: user, token: api_token)

      allow_any_instance_of(BillsController)
        .to receive(:render_inertia_or_json)
        .and_wrap_original do |original, **kwargs|
          original.receiver.response.headers["Vary"] = "Accept-Encoding, Origin, x-sway-omit-props"
          original.call(**kwargs)
        end

      get "/bills/#{bill.id}", headers: {
        "Authorization" => "Bearer #{api_token}",
        "X-Sway-Omit-Props" => " legislators, legislators, LEGIsLATORS, unknown, legislator_votes, districts, "
      }

      body = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(body).not_to have_key("legislators")
      expect(body).not_to have_key("legislator_votes")
      expect(body).not_to have_key("districts")
      expect(body).to have_key("bill")
      expect(body).to have_key("organizations")
      expect(body).to have_key("organization_bill_positions")
      # Rails appends Accept and X-Requested-With to Vary whenever it negotiates the format.
      expect(response.headers.fetch("Vary").split(",").map(&:strip)).to eq(
        ["Accept-Encoding", "Origin", "x-sway-omit-props", "Accept", "X-Requested-With"]
      )
    end

    # @lat: [[lazy-inertia-props#Mobile JSON omission is an explicit request]]
    it "does not treat differently cased names as allowed props" do
      sway_locale, user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!
      district = create(:district, sway_locale:, name: "D-1")
      legislator = create(:legislator, district:)
      create(
        :legislator_term,
        legislator:,
        district:,
        began_on: Date.new(2025, 1, 3),
        ended_on: Date.new(2027, 1, 3),
        began_on_source: LegislatorTerm::DateSource::OBSERVED,
        ended_on_source: LegislatorTerm::DateSource::OBSERVED
      )
      api_token = SecureRandom.hex(32)
      ApiKey.create!(bearer: user, token: api_token)

      get "/bills/#{bill.id}", headers: {
        "Authorization" => "Bearer #{api_token}",
        "X-Sway-Omit-Props" => "LEGISLATORS"
      }

      expect(response.parsed_body.fetch("legislators").pluck("id")).to include(legislator.id)
    end

    # @lat: [[district-chart-tooltip#The mobile bill JSON carries the names, the web page does not]]
    describe "legislator names on district scores" do
      it "names each scored district's serving legislators, sorted by full name, for a bearer request" do
        sway_locale, user = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.save!
        shared_district = create(:district, sway_locale:, name: "D-1")
        vacant_district = create(:district, sway_locale:, name: "D-2")
        former_district = create(:district, sway_locale:, name: "D-3")
        BillsControllerSpecHelpers.seat_legislator(shared_district, "Zed", "Zane")
        BillsControllerSpecHelpers.seat_legislator(shared_district, "Amy", "Adams")
        BillsControllerSpecHelpers.seat_legislator(
          former_district, "Gone", "Before",
          began_on: Date.current - 3.years, ended_on: Date.current - 1.year
        )
        [shared_district, vacant_district, former_district].each do |district|
          create(:bill_score_district, bill_score: bill.bill_score, district:, for: 2, against: 1)
        end
        api_token = SecureRandom.hex(32)
        ApiKey.create!(bearer: user, token: api_token)

        get "/bills/#{bill.id}", headers: {"Authorization" => "Bearer #{api_token}"}

        districts = response.parsed_body.fetch("bill_score").fetch("districts")
        expect(districts.map(&:keys).uniq).to eq([%w[bill_score_id district for against comparison_suppressed for_percent against_percent at_large legislator_names]])
        expect(districts.to_h { |entry| [entry["district"]["name"], entry["legislator_names"]] }).to eq(
          "D-1" => ["Amy Adams", "Zed Zane"],
          "D-2" => [],
          "D-3" => []
        )
      end

      it "sends the web page the district scores without legislator names" do
        sway_locale, user = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.save!
        district = create(:district, sway_locale:, name: "D-1")
        BillsControllerSpecHelpers.seat_legislator(district, "Amy", "Adams")
        score_district = create(:bill_score_district, bill_score: bill.bill_score, district:, for: 2, against: 1)
        sign_in(user)

        get "/bills/#{bill.id}"

        expect(inertia).to render_component Pages::BILL
        expect(inertia.props[:bill_score]["districts"]).to eq(
          [
            {
              "bill_score_id" => score_district.bill_score_id,
              "district" => {"name" => "D-1", "number" => 1, "region_code" => "D"},
              "for" => nil,
              "against" => nil,
              "comparison_suppressed" => true,
              "for_percent" => nil,
              "against_percent" => nil,
              "at_large" => false
            }
          ]
        )
      end

      it "reads the names in a fixed number of queries however many districts are scored" do
        sway_locale, _user = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.save!

        count_name_queries = lambda do |&request|
          query_count = 0
          subscriber =
            ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
              next if payload[:name].to_s == "SCHEMA"
              query_count += 1 if payload[:sql].to_s.match?(/FROM\s+["'`]?(legislator_terms|legislators)["'`]?(?=\s|$)/i)
            end
          request.call
          ActiveSupport::Notifications.unsubscribe(subscriber)
          query_count
        end #: ^() { () -> untyped } -> Integer

        add_scored_districts = lambda do |count, offset|
          count.times do |index|
            district = create(:district, sway_locale:, name: "D-#{offset + index}")
            BillsControllerSpecHelpers.seat_legislator(district, "First#{offset + index}", "Last#{offset + index}")
            create(:bill_score_district, bill_score: bill.bill_score, district:, for: 2, against: 1)
          end
        end #: ^(Integer, Integer) -> void

        add_scored_districts.call(2, 10)
        count_with_two = count_name_queries.call { get "/bills/#{bill.id}", headers: {"Accept" => "application/json"} }
        expect(response.parsed_body["bill_score"]["districts"].size).to eq(2)

        add_scored_districts.call(4, 20)
        count_with_six = count_name_queries.call { get "/bills/#{bill.id}", headers: {"Accept" => "application/json"} }
        expect(response.parsed_body["bill_score"]["districts"].size).to eq(6)

        expect(count_with_six).to eq(count_with_two),
          "Expected a constant legislator query count (got #{count_with_two} for 2 districts, #{count_with_six} for 6) - N+1 detected"
      end
    end

    describe "optional prop resolver boundary" do
      # @lat: [[lazy-inertia-props#Mobile JSON omission is an explicit request]]
      it "omits only an allowlisted top-level optional prop and resolves nested props and Procs" do
        subject = BillsController.new
        allow(subject).to receive(:request).and_return(
          double(headers: {"X-Sway-Omit-Props" => "legislators"})
        )
        props = {
          "legislators" => InertiaRails.optional { "top-level" },
          :legislators => -> { "symbol sibling" },
          :history => InertiaRails.optional { "unlisted" },
          :organizations => -> { "ordinary callable" },
          :nested => {legislators: InertiaRails.optional { "nested" }}
        }

        resolved = subject.resolve_inertia_props(props)

        expect(resolved).to eq(
          legislators: "symbol sibling",
          history: "unlisted",
          organizations: "ordinary callable",
          nested: {legislators: "nested"}
        )
      end

      # @lat: [[lazy-inertia-props#Mobile JSON omission is an explicit request]]
      it "ignores a non-string omission header" do
        subject = BillsController.new
        allow(subject).to receive(:request).and_return(
          double(headers: {"X-Sway-Omit-Props" => ["legislators"]})
        )

        expect(subject.send(:requested_optional_prop_names)).to eq([])
      end
    end

    it "renders legislators from the past session for a historical bill (TASK-iwxrj.28: Update UI historical roster payload)" do
      sway_locale, _user = setup
      district = create(:district, sway_locale: sway_locale, name: "D-1")

      past_session = create(
        :legislative_session,
        sway_locale: sway_locale,
        name: "118th Congress",
        start_date: Date.new(2023, 1, 3),
        end_date: Date.new(2025, 1, 2),
        active: false
      )
      _current_session = create(
        :legislative_session,
        :active,
        sway_locale: sway_locale,
        name: "119th Congress",
        start_date: Date.new(2025, 1, 3),
        end_date: Date.new(2027, 1, 3)
      )

      past_legislator = create(:legislator, district: district)
      create(
        :legislator_term,
        legislator: past_legislator,
        district: district,
        term_start_year: 2023,
        term_end_year: 2025,
        began_on: Date.new(2023, 1, 3),
        ended_on: Date.new(2025, 1, 2),
        began_on_source: LegislatorTerm::DateSource::OBSERVED,
        ended_on_source: LegislatorTerm::DateSource::OBSERVED
      )

      current_legislator = create(:legislator, district: district)
      create(
        :legislator_term,
        legislator: current_legislator,
        district: district,
        term_start_year: 2025,
        term_end_year: 2027,
        began_on: Date.new(2025, 1, 3),
        ended_on: Date.new(2027, 1, 3),
        began_on_source: LegislatorTerm::DateSource::OBSERVED,
        ended_on_source: LegislatorTerm::DateSource::OBSERVED
      )

      historical_bill, _params = build_bill_params.call(sway_locale)
      historical_bill.update!(
        legislative_session: past_session,
        introduced_date_time_utc: Time.zone.local(2024, 5, 1)
      )

      get "/bills/#{historical_bill.id}", headers: {"Accept" => "application/json"}

      legislator_ids = response.parsed_body["legislators"].pluck("id")
      expect(legislator_ids).to include(past_legislator.id)
      expect(legislator_ids).not_to include(current_legislator.id)

      get "/bills/#{historical_bill.id}"
      expect(inertia).to render_component Pages::BILL
      inertia_versioned_reload_only("legislators")
      roster_ids = inertia.props[:legislators].map { |l| l["id"] || l[:id] }
      expect(roster_ids).to include(past_legislator.id)
      expect(roster_ids).not_to include(current_legislator.id)
    end

    it "deduplicates re-elected legislators with multiple overlapping terms and includes mid-session appointees in the session roster" do
      sway_locale, _user = setup
      district = create(:district, sway_locale:)
      past_session = create(
        :legislative_session,
        sway_locale:,
        name: "2023-2025 Session",
        start_date: Date.new(2023, 1, 3),
        end_date: Date.new(2025, 1, 2),
        active: false
      )
      reelected_legislator = create(:legislator, district:, first_name: "Reelected", last_name: "Member")
      appointee = create(:legislator, district:, first_name: "MidSession", last_name: "Appointee")

      create(
        :legislator_term,
        legislator: reelected_legislator,
        district:,
        term_start_year: 2021,
        term_end_year: 2023,
        began_on: Date.new(2021, 1, 3),
        ended_on: Date.new(2023, 1, 4),
        began_on_source: LegislatorTerm::DateSource::OBSERVED,
        ended_on_source: LegislatorTerm::DateSource::OBSERVED
      )
      create(
        :legislator_term,
        legislator: reelected_legislator,
        district:,
        term_start_year: 2023,
        term_end_year: 2025,
        began_on: Date.new(2023, 1, 3),
        ended_on: Date.new(2025, 1, 2),
        began_on_source: LegislatorTerm::DateSource::OBSERVED,
        ended_on_source: LegislatorTerm::DateSource::OBSERVED
      )
      create(
        :legislator_term,
        legislator: appointee,
        district:,
        term_start_year: 2024,
        term_end_year: 2025,
        began_on: Date.new(2024, 6, 1),
        ended_on: Date.new(2025, 1, 2),
        began_on_source: LegislatorTerm::DateSource::OBSERVED,
        ended_on_source: LegislatorTerm::DateSource::OBSERVED
      )

      historical_bill, _params = build_bill_params.call(sway_locale)
      historical_bill.update!(
        legislative_session: past_session,
        introduced_date_time_utc: Time.zone.local(2024, 7, 1)
      )

      get "/bills/#{historical_bill.id}", headers: {"Accept" => "application/json"}
      legislator_ids = response.parsed_body["legislators"].pluck("id")
      expect(legislator_ids.count(reelected_legislator.id)).to eq(1)
      expect(legislator_ids).to include(appointee.id)
    end

    # @lat: [[bills-controller-design#The bill page returns active organization positions as flat rows]]
    it "renders each active org position as a flat, bill-scoped row" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!
      organization = create(:organization, sway_locale:)
      inactive_org = create(:organization, name: "Inactive Org", sway_locale:)
      obp =
        create(
          :organization_bill_position,
          organization:,
          bill:,
          support: LegislatorVote::Support::FOR,
          summary: "We support this bill."
        )
      # An inactive position on the same bill must not show up: the render
      # walks active_organization_bill_positions, not every position.
      create(
        :organization_bill_position,
        organization: inactive_org,
        bill:,
        support: LegislatorVote::Support::AGAINST,
        summary: "Hidden.",
        active: false
      )

      get "/bills/#{bill.id}"

      expect(inertia).to render_component Pages::BILL
      positions = inertia.props[:organizations]
      expect(positions.size).to eq(1)
      expect(positions.first).to include(
        id: obp.id,
        bill_id: bill.id,
        support: "FOR",
        summary: "We support this bill."
      )
      expect(positions.first[:organization]).to include(
        id: organization.id,
        name: organization.name,
        sway_locale_id: sway_locale.id
      )
    end
  end

  # @lat: [[identity-and-access#The admin gate is a lint rule#An admin affordance in the reader's page is a convenience, not a gate]]
  describe "admin edit link visibility" do
    # Two examples below point ADMIN_PHONES at a phone nobody holds. Without
    # this, that value outlives them, and any later example that reads the
    # constant without setting it first sees "nobody is an admin".
    around do |example|
      original = User::ADMIN_PHONES
      begin
        example.run
      ensure
        User.send(:remove_const, :ADMIN_PHONES)
        User.const_set(:ADMIN_PHONES, original)
      end
    end

    it "ships is_admin on the bill show page for a sway admin" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      get "/bills/#{bill.id}"

      expect(inertia.props[:user]).to include(is_admin: true)
    end

    it "omits is_admin from the bill show page for a non-admin" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!
      # setup makes its user an admin by pointing ADMIN_PHONES at their own
      # phone (spec/support/setup.rb) — point it elsewhere so this user is
      # reliably a non-admin.
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, ["+19999999999"])

      get "/bills/#{bill.id}"

      user_data = inertia.props[:user] || {}
      expect(user_data).not_to have_key(:is_admin)
      expect(user_data).not_to have_key("is_admin")
    end

    it "ships is_admin on the bills index page for a sway admin" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      get "/bills"

      expect(inertia.props[:user]).to include(is_admin: true)
    end

    it "omits is_admin from the bills index page for a non-admin" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, ["+19999999999"])

      get "/bills"

      user_data = inertia.props[:user] || {}
      expect(user_data).not_to have_key(:is_admin)
      expect(user_data).not_to have_key("is_admin")
    end
  end

  describe "GET /new" do
    it "renders the bill creator with a new bill" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      get "/admin/bill_creator/new"

      expect(inertia).to render_component Pages::BILL_CREATOR
      empty_values = []
      # @type var empty_values: Array[untyped]
      expect(inertia).to have_props(
        {
          bill: Bill.new.attributes,
          legislators: sway_locale.legislators.map(&:to_sway_json),
          organizations: empty_values,
          legislator_votes: empty_values,
          tab_key: nil
        }
      )
    end

    # @lat: [[mobile-bill-creator#The bill picker]]
    it "serves the picker bills as JSON to an admin bearer request" do
      sway_locale, user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      get "/admin/bill_creator/new", headers: authenticate_as(user).merge("Accept" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body.fetch("bills").pluck("id", "external_id")).to eq([[bill.id, bill.external_id]])
    end

    it "serves only the picker bills to a bearer request that names no tab" do
      _sway_locale, user = setup

      get "/admin/bill_creator/new", headers: authenticate_as(user).merge("Accept" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.keys).to eq(["bills"])
    end

    it "serves only the named tab's props to a bearer request for a new bill" do
      _sway_locale, user = setup

      get "/admin/bill_creator/new",
        params: {bill_creator_tab: "creator"},
        headers: authenticate_as(user).merge("Accept" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.keys).to match_array(%w[bill bill_id tab_key legislators legislator_votes organizations])
    end

    it "still gives the web page every prop when a tab is named" do
      setup

      get "/admin/bill_creator/new", params: {bill_creator_tab: "creator"}

      expect(inertia.props).to include(:bills, :pipeline_preview, :fetched_bills, :legislators)
    end
  end

  describe "GET /edit vote-entry roster" do
    it "offers a departed member, marked, so a historical vote can still be entered" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!
      district = create(:district, sway_locale: sway_locale, name: "D-9")
      departed = create(:legislator, district: district)
      create(:legislator_term, legislator: departed, district: district,
        term_start_year: 2015, term_end_year: 2019)

      get "/admin/bill_creator/#{bill.id}/creator"

      row = inertia.props[:legislators].find { |l| l["id"] == departed.id }
      expect(row).to be_present
      expect(row["active"]).to be(false)
      expect(row["district"]).to be_present
      expect(row["term_end_year"]).to eq(2019)
    end

    it "leaves out someone who never held a term in the locale" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!
      district = create(:district, sway_locale: sway_locale, name: "D-8")
      never_seated = create(:legislator, district: district)

      get "/admin/bill_creator/#{bill.id}/creator"

      expect(inertia.props[:legislators].pluck("id")).not_to include(never_seated.id)
    end

    it "keeps House members off a Congress nomination, serving or departed" do
      _sway_locale, _user = setup
      congress = create(:sway_locale, :congress)
      district = create(:district, sway_locale: congress, name: "MD1")
      departed_rep = create(:legislator, district: district)
      create(:legislator_term, legislator: departed_rep, district: district,
        title: "Rep.", term_start_year: 2015, term_end_year: 2019)
      departed_senator = create(:legislator, district: district)
      create(:legislator_term, legislator: departed_senator, district: district,
        title: "Sen.", term_start_year: 2013, term_end_year: 2019)

      bill = create(:bill, sway_locale: congress, external_id: "PN1234",
        scheduled_release_date_utc: nil)

      get "/admin/bill_creator/#{bill.id}/creator", params: {sway_locale_id: congress.id}

      ids = inertia.props[:legislators].pluck("id")
      expect(ids).to include(departed_senator.id)
      expect(ids).not_to include(departed_rep.id)
    end

    # @lat: [[current-legislator-term#Which term a legislator is serving now#The vote-entry roster is everyone who ever held the seat#The displayed term needs its own district preload]]
    it "preloads displayed-term districts in constant queries as serving legislators grow" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      # Baseline with 2 serving legislators in distinct districts
      2.times do |i|
        district = create(:district, sway_locale: sway_locale, name: "District-A-#{i + 1}")
        leg = create(:legislator, district: district)
        create(:legislator_term, legislator: leg, district: district,
          term_start_year: 2025, term_end_year: 2027)
      end

      count_roster_queries = lambda do
        queries = []
        subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          sql = payload[:sql].to_s
          if sql.match?(/FROM "(?:districts|seats|legislator_district_scores|legislator_locale_scores)"/i)
            queries << sql
          end
        end
        begin
          get "/admin/bill_creator/#{bill.id}/creator"
        ensure
          ActiveSupport::Notifications.unsubscribe(subscriber)
        end
        queries.size
      end

      baseline_queries = count_roster_queries.call

      # Add 4 more serving legislators in distinct districts (total 6)
      4.times do |i|
        district = create(:district, sway_locale: sway_locale, name: "District-B-#{i + 1}")
        leg = create(:legislator, district: district)
        create(:legislator_term, legislator: leg, district: district,
          term_start_year: 2025, term_end_year: 2027)
      end

      scaled_queries = count_roster_queries.call

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:legislators].size).to be >= 6
      expect(scaled_queries).to eq(baseline_queries)
    end
  end

  describe "GET /edit" do
    it "reads the bill's own categories once, not once per prop" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!
      create(:bill_category, bill: bill, category: create(:category, name: "Zoning"))
      create(:bill_category, bill: bill, category: create(:category, name: "Finance"))

      statements = []
      subscriber =
        ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          statements << payload[:sql].to_s
        end
      begin
        get "/admin/bill_creator/#{bill.id}/creator"
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:bill]["override_categories"].pluck("name")).to eq(%w[Finance Zoning])
      expect(statements.grep(/bill_categories/)).to contain_exactly(a_string_matching(/bill_categories/))
    end

    it "renders the bill creator with a bill from params" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      get "/admin/bill_creator/#{bill.id}/creator"

      expect(inertia).to render_component Pages::BILL_CREATOR
      empty_values = []
      # @type var empty_values: Array[untyped]
      # @lat: [[bill-interesting-score#Picker reads]]
      expect(inertia.props[:bills]).to eq([
        {
          "id" => bill.id,
          "external_id" => bill.external_id,
          "title" => bill.title,
          "scheduled_release_date_utc" => bill.scheduled_release_date_utc&.iso8601,
          "status" => bill.status,
          "chamber" => bill.chamber,
          "category" => bill.category,
          "introduced_date_time_utc" => bill.introduced_date_time_utc&.iso8601,
          "latest_action_date_time_utc" => [
            bill.introduced_date_time_utc,
            bill.house_vote_date_time_utc,
            bill.senate_vote_date_time_utc
          ].compact.max&.iso8601,
          "sponsor_name" => "#{bill.legislator.first_name} #{bill.legislator.last_name}",
          "legislator_vote_count" => 0,
          "organization_position_count" => 0,
          # This bill has never been scored, so it has no
          # bill_interesting_scores row: null score and no badges.
          "interesting_score_normalized" => nil,
          "interesting_badges" => []
        }
      ])
      expected_bill =
        bill.to_sway_json.as_json.merge(
          "organizations" => empty_values,
          "bill_llm_provisioning" => nil,
          "bill_pipeline_refresh" => nil,
          # Nil because this bill has no failed pipeline run, so the summary
          # tab's failure alert has nothing to say. The KEY is still here: the
          # controller adds it on every Bill Creator render, failure or not,
          # and this example pins the whole prop hash exactly.
          "bill_pipeline_last_failure" => nil,
          # bill_creator_props carries a per-bill category override. Repeat the
          # controller's own expression here so this stays right even if the
          # test bill gains categories later — do not hardcode [].
          "override_categories" => bill.categories.sort_by(&:name).map { |c| {"id" => c.id, "name" => c.name, "active" => c.active} }
        )
      expect(inertia.props[:bill]).to eq(expected_bill)
      expect(inertia.props[:legislators]).to eq(
        LegislatorResource.new(
          sway_locale.legislators(false).joins(:legislator_terms).distinct.to_a
        ).serializable_hash.as_json
      )
      expect(inertia.props[:organizations]).to eq(empty_values)
      expect(inertia.props[:legislator_votes]).to eq(empty_values)
      # @lat: [[bill-creator-shell#Why onBillChange puts both the bill id and the tab in the address]]
      expect(inertia.props[:tab_key]).to eq("creator")
    end

    # @lat: [[bill-interesting-score#Picker reads]]
    it "clamps interesting_score_normalized to at most 1.0 when a stale full-signal score row exceeds the locale's theoretical max (review WR-01)" do
      sway_locale, _user = setup
      # The Setup locale is local (a random city and state, not congress and
      # not regional), so the picker divides by LOCAL_THEORETICAL_MAX (50).
      expect(sway_locale.local?).to be(true)

      bill, _params = build_bill_params.call(sway_locale)
      bill.save!
      create(
        :bill_interesting_score,
        bill: bill,
        signals: {
          "vote_defection_score" => 60.0,
          "vote_abstention_score" => 10.0,
          "org_split_score" => 50.0,
          "timeliness_score" => 10.0,
          "real_for" => 30,
          "real_against" => 28,
          "real_abstain" => 2,
          "org_for" => 2,
          "org_against" => 2
        }
      )

      get "/admin/bill_creator/#{bill.id}/creator"

      picker_row = inertia.props[:bills].find { |b| b["id"] == bill.id }
      expect(picker_row).to be_present
      # 120.0 raw (plus fresh timeliness) / 100.0 is over 1.2 unclamped — must render 1.0.
      expect(picker_row["interesting_score_normalized"]).to eq(1.0)
    end

    # picker_bills reads the raw `signals` text column through a subquery, so
    # ActiveRecord never decodes it. One row of broken JSON therefore used to
    # raise JSON::ParserError and 500 every #new and #edit render for the whole
    # locale. Now only that one bill degrades, to a nil score and no badges.
    it "renders the picker with a nil score instead of 500ing when a stored signals JSON row is corrupt (review IN-01)" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!
      score = create(:bill_interesting_score, bill: bill)
      # Raw SQL is needed here: update_all or update_column would push the
      # value back through the JSON coder and store VALID JSON.
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql(
          ["UPDATE bill_interesting_scores SET signals = '{not json' WHERE id = ?", score.id]
        )
      )

      allow(Rails.logger).to receive(:warn).and_call_original
      expect(Rails.logger).to receive(:warn)
        .with(/corrupt bill_interesting_scores\.signals JSON for bill #{bill.id}/)
        .and_call_original

      get "/admin/bill_creator/#{bill.id}/creator"

      expect(response).to have_http_status(:ok)
      picker_row = inertia.props[:bills].find { |b| b["id"] == bill.id }
      expect(picker_row).to be_present
      expect(picker_row["interesting_score_normalized"]).to be_nil
      expect(picker_row["interesting_badges"]).to eq([])
    end

    describe "one tab's props for a bearer request" do
      def get_tab_as_json(bill, user, tab)
        get "/admin/bill_creator/#{bill.id}/#{tab}", headers: authenticate_as(user).merge("Accept" => "application/json")
      end

      # @lat: [[mobile-bill-creator#Each tab gets only its own props]]
      it "serves the schedule tab only the bill and the picker bills" do
        sway_locale, user = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.save!

        get_tab_as_json(bill, user, "schedule")

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.keys).to match_array(%w[bill bill_id bills])
        expect(response.parsed_body.fetch("bill").fetch("id")).to eq(bill.id)
      end

      # @lat: [[mobile-bill-creator#Sections#The schedule section]]
      it "gives the schedule tab each picker bill's id, external id, title and release date" do
        sway_locale, user = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.scheduled_release_date_utc = Date.new(2026, 9, 8)
        bill.save!

        get_tab_as_json(bill, user, "schedule")

        row = response.parsed_body.fetch("bills").find { |b| b["id"] == bill.id }
        expect(row).to include(
          "external_id" => bill.external_id,
          "title" => bill.title,
          "scheduled_release_date_utc" => "2026-09-08"
        )
      end

      it "serves the creator tab the vote-entry legislators" do
        sway_locale, user = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.save!

        get_tab_as_json(bill, user, "creator")

        expect(response.parsed_body.keys).to include("legislators", "legislator_votes", "organizations")
        expect(response.parsed_body.keys).not_to include("bills", "pipeline_preview", "summary_sources")
      end

      it "serves each tab exactly the keys its list names" do
        sway_locale, user = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.save!

        BillsController::BILL_CREATOR_TAB_PROPS.each do |tab, keys|
          get_tab_as_json(bill, user, tab)

          expect(response.parsed_body.keys).to match_array(keys.map(&:to_s)), "tab #{tab}"
        end
      end

      it "still gives the web page every tab's props" do
        sway_locale, _user = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.save!

        get "/admin/bill_creator/#{bill.id}/schedule"

        every_key = BillsController::BILL_CREATOR_TAB_PROPS.values.flatten.uniq
        expect(inertia.props).to include(*every_key)
      end
    end
  end

  describe "POST /create" do
    let(:spec_create_failure) do
      lambda do |key|
        sway_locale, _user = setup
        count_bills = Bill.count

        partial_bill = {}
        # @type var partial_bill: Hash[Symbol, untyped]
        partial_bill[key] = nil
        _bill, params = build_bill_params.call(sway_locale, partial_bill:)

        post "/bills", params: params

        expect(response).to have_http_status(302)
        expect(Bill.count).to eql(count_bills)
        follow_redirect!
        expect(inertia.props[:errors][key].first).to include("can't be blank")
      end
    end

    it "creates a new bill" do
      sway_locale, _user = setup

      count_bills = Bill.count
      count_roll_calls = RollCall.count

      bill, params = build_bill_params.call(sway_locale)

      post "/bills", params: params

      expect(response).to have_http_status(:redirect)
      created_bill = Bill.last!
      # The success message travels in the Rails flash, and registerFlashToasts
      # shows it once as a toast. It is no longer a ?saved= query param.
      # event_key stays in the URL so the right tab gets focus.
      expect(response).to redirect_to(
        creator_bill_creator_path(
          created_bill.id,
          {event_key: "legislator_votes"}
        )
      )
      expect(flash[:notice]).to eq("Bill Created")

      expect(Bill.count).to eql(count_bills + 1)
      expect(created_bill.external_id).to eql(bill.external_id)
      expect(RollCall.count).to eql(count_roll_calls + 1)
      expect(RollCall.last!.senate_roll_call_vote_number).to eql(2)
    end

    # @lat: [[bills-controller-roll-calls#In-place roll-call update and purging]]
    it "converges to a single RollCall row when a roll-call number is corrected" do
      sway_locale, _user = setup
      _bill, params = build_bill_params.call(sway_locale)

      post "/bills", params: params
      created = Bill.last!
      expect(created.roll_calls.count).to eq(1)
      expect(created.vote.house_roll_call_vote_number).to eq(1)

      put "/bills/#{created.id}", params: params.merge(house_roll_call_vote_number: 102)

      created.reload
      expect(created.roll_calls.count).to eq(1)
      expect(created.vote.house_roll_call_vote_number).to eq(102)
      expect(created.vote.senate_roll_call_vote_number).to eq(2)
    end

    # @lat: [[bills-controller-roll-calls#Re-fetching legislator votes after roll-call correction]]
    it "re-fetches legislator votes when a roll-call number is corrected in place" do
      sway_locale, _user = setup
      _bill, params = build_bill_params.call(sway_locale)
      post "/bills", params: params
      created = Bill.last!

      expect {
        put "/bills/#{created.id}", params: params.merge(house_roll_call_vote_number: 102)
      }.to have_enqueued_job(LegislatorVoteFetchJob).with(created.id)
    end

    it "does NOT re-fetch legislator votes when the roll-call numbers are unchanged" do
      sway_locale, _user = setup
      _bill, params = build_bill_params.call(sway_locale)
      post "/bills", params: params
      created = Bill.last!

      expect {
        put "/bills/#{created.id}", params: params # identical roll-call numbers
      }.not_to have_enqueued_job(LegislatorVoteFetchJob)
    end

    it "does not create a new bill, because the external_id is missing" do
      spec_create_failure.call(:external_id)
    end

    # @lat: [[bills-category-filter#The single-subject category column is retired]]

    it "does not create a new bill, because the chamber is missing" do
      spec_create_failure.call(:chamber)
    end

    it "does not create a new bill, because the introduced_date_time_utc is missing" do
      spec_create_failure.call(:introduced_date_time_utc)
    end

    # @lat: [[unlinked-bill-presentation#The absent shape eliminates sentinel leakage]]
    it "creates a new bill when the link is missing, storing nil" do
      sway_locale, _user = setup
      count_bills = Bill.count

      _bill, params = build_bill_params.call(sway_locale, partial_bill: {link: nil})

      post "/bills", params: params

      expect(response).to have_http_status(:redirect)
      expect(Bill.count).to eql(count_bills + 1)
      expect(Bill.last!.link).to be_nil
    end

    it "does not create a new bill, because the status is missing" do
      spec_create_failure.call(:status)
    end

    it "does not create a new bill, because the summary is missing" do
      spec_create_failure.call(:summary)
    end

    it "does not create a new bill, because the title is missing" do
      spec_create_failure.call(:title)
    end

    it "does not create a new bill, because the sway_locale_id is missing" do
      spec_create_failure.call(:sway_locale_id)
    end

    describe "for a bearer request" do
      # @lat: [[mobile-bill-creator#Sections#The bill fields section]]
      it "answers with the created bill as JSON" do
        sway_locale, user = setup
        bill, params = build_bill_params.call(sway_locale)

        post "/bills", params: params.to_json,
          headers: authenticate_as(user).merge("Accept" => "application/json", "Content-Type" => "application/json")

        expect(response).to have_http_status(:ok)
        created_bill = Bill.last!
        expect(response.parsed_body).to include("id" => created_bill.id, "external_id" => bill.external_id)
      end

      it "answers an invalid bill with 422 and the field errors" do
        sway_locale, user = setup
        _bill, params = build_bill_params.call(sway_locale, partial_bill: {title: nil})

        expect {
          post "/bills", params: params.to_json,
            headers: authenticate_as(user).merge("Accept" => "application/json", "Content-Type" => "application/json")
        }.not_to change(Bill, :count)

        expect(response).to have_http_status(:unprocessable_content)
        error = response.parsed_body.fetch("error")
        expect(error.fetch("code")).to eq("validation_failed")
        expect(error.dig("details", "title").first).to include("can't be blank")
      end

      it "refuses a non-admin with a forbidden JSON error" do
        sway_locale, _admin = setup
        _bill, params = build_bill_params.call(sway_locale)
        non_admin = create(:user)
        create(:user_legislator, user: non_admin)
        non_admin.complete!

        post "/bills", params: params.to_json,
          headers: authenticate_as(non_admin).merge("Accept" => "application/json", "Content-Type" => "application/json")

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
      end
    end
  end

  describe "PUT /update" do
    it "updates a bill" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      put "/bills/#{bill.id}", params: {summary: "Tacos are super great!", news_usage: "none"}

      expect(response).to have_http_status(:redirect)
      redirect_location = response.location
      expect(redirect_location).to include(creator_bill_creator_path(bill.id))

      follow_redirect!

      expect(inertia).to render_component Pages::BILL_CREATOR
      empty_values = []
      # @type var empty_values: Array[untyped]
      bill.reload
      actual = inertia.props[:bill].deep_symbolize_keys
      expect(actual[:summary]).to eq("Tacos are super great!")
      expect(actual[:organizations]).to eq(empty_values)
      expect(actual[:id]).to eq(bill.id)
    end

    # @lat: [[bill-creator-shell#Why onBillChange puts both the bill id and the tab in the address]]
    it "redirects to the Creator tab path with the bill id in the path segment" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      put "/bills/#{bill.id}", params: {summary: "Tacos", news_usage: "none"}

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("/admin/bill_creator/#{bill.id}/creator")
    end

    it "does not append tab_key or bill_id query params to the post-save redirect" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      # Even when the request URL still carries the old query params, they are
      # NOT copied onto the redirect, which keeps the ids in the path instead.
      put "/bills/#{bill.id}?tab_key=summary&bill_id=#{bill.id}", params: {summary: "No echo", news_usage: "none"}

      expect(response).to have_http_status(:redirect)
      expect(response.location).not_to include("tab_key")
      expect(response.location).not_to include("bill_id=")
    end

    it "records an operator_edit revision when the summary changes" do
      sway_locale, user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.summary = "Original bill text"
      bill.save!

      expect {
        put "/bills/#{bill.id}", params: {summary: "Operator edited this summary", news_usage: "none"}
      }.to change { bill.bill_summary_revisions.count }.by(2) # 1 baseline + 1 edit

      revisions = bill.bill_summary_revisions.order(:id)
      baseline = revisions.first
      expect(baseline.origin).to eq("initial_baseline")
      expect(baseline.summary_markdown).to eq("Original bill text")

      edit_rev = revisions.last
      expect(edit_rev.origin).to eq("operator_edit")
      expect(edit_rev.summary_markdown).to eq("Operator edited this summary")
      expect(edit_rev.actor).to eq(user)
      expect(edit_rev.publication_role).to eq("published")
      expect(edit_rev.review_state).to eq("reviewed")
    end

    it "creates no revision when an update does not change summary" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.summary = "Same summary text"
      bill.save!

      expect {
        put "/bills/#{bill.id}", params: {title: "Brand New Title"}
      }.not_to change { bill.bill_summary_revisions.count }
    end

    it "rolls back summary update atomically if revision creation raises RecordInvalid" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.summary = "Original bill text before failure"
      bill.save!

      allow(BillSummaryRevision).to receive(:record_revision!).and_raise(
        ActiveRecord::RecordInvalid.new(BillSummaryRevision.new)
      )

      put "/bills/#{bill.id}", params: {summary: "Failed replacement summary", news_usage: "none"}

      expect(bill.reload.summary).to eq("Original bill text before failure")
    end

    it "redirects an invalid web update to the Creator tab with the field errors" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      put "/bills/#{bill.id}", params: {title: ""}

      expect(response).to redirect_to(creator_bill_creator_path(bill.id, {event_key: "legislator_votes"}))
      follow_redirect!
      expect(inertia.props[:errors][:title].first).to include("can't be blank")
    end

    it "does not serialize the bill for a web update" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      expect(BillResource).not_to receive(:new)

      put "/bills/#{bill.id}", params: {title: "Brand New Title"}

      expect(response).to have_http_status(:found)
    end

    describe "for a bearer request" do
      # @lat: [[mobile-bill-creator#Sections#The bill fields section]]
      it "answers with the updated bill as JSON" do
        sway_locale, user = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.save!

        patch "/bills/#{bill.id}", params: {title: "Brand New Title", news_usage: "none"}.to_json,
          headers: authenticate_as(user).merge("Accept" => "application/json", "Content-Type" => "application/json")

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to include("id" => bill.id, "title" => "Brand New Title")
        expect(bill.reload.title).to eq("Brand New Title")
      end

      it "answers an invalid update with 422 and the field errors" do
        sway_locale, user = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.save!

        patch "/bills/#{bill.id}", params: {title: "", news_usage: "none"}.to_json,
          headers: authenticate_as(user).merge("Accept" => "application/json", "Content-Type" => "application/json")

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig("error", "details", "title").first).to include("can't be blank")
      end

      it "refuses a non-admin with a forbidden JSON error" do
        sway_locale, _admin = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.save!
        non_admin = create(:user)
        create(:user_legislator, user: non_admin)
        non_admin.complete!

        patch "/bills/#{bill.id}", params: {title: "Brand New Title"}.to_json,
          headers: authenticate_as(non_admin).merge("Accept" => "application/json", "Content-Type" => "application/json")

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
        expect(bill.reload.title).not_to eq("Brand New Title")
      end
    end

    describe "Validate manual news summary publication" do
      let(:news_article) { create(:news_article, canonical_url: "https://baltimorebanner.com/transit-plan") }
      let(:text_version) { create(:news_article_text_version, :extracted, news_article: news_article, text: "Council approved 100 new electric buses for city routes.") }

      it "editing a supported claim into an unsupported one cannot replace public content; the submitted text survives as a draft" do
        grounding_adapter = double("news claim grounding adapter")
        allow(Llm::Client).to receive(:build).and_return(grounding_adapter)
        expect(grounding_adapter).to receive(:generate_news_claim_grounding).at_least(:once).and_return({"verdict" => "unsupported", "reason" => "The evidence approves buses; the claim rejects them"})
        sway_locale, _user = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.summary = "Original public summary"
        bill.save!
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)

        put "/bills/#{bill.id}", params: {
          summary: "Council unanimously rejected all buses [Source](https://baltimorebanner.com/transit-plan).",
          news_usage: "cited",
          source_uses: [
            {
              bill_news_article_id: approved_bna.id,
              text_version_id: text_version.id,
              claim_text: "Council unanimously rejected all buses",
              evidence_excerpt: "Council approved 100 new electric buses for city routes.",
              citation_url: "https://baltimorebanner.com/transit-plan"
            }
          ]
        }

        expect(bill.reload.summary).to eq("Original public summary")
        latest_rev = bill.bill_summary_revisions.order(:id).last
        expect(latest_rev.publication_role).to eq("draft")
        expect(latest_rev.summary_markdown).to include("Council unanimously rejected all buses")
      end

      it "rejects news_usage: 'none' when external news URLs are present, preserving public summary and saving draft" do
        sway_locale, _user = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.summary = "Original public summary"
        bill.save!

        put "/bills/#{bill.id}", params: {
          summary: "City policy updated as reported by [Banner](https://baltimorebanner.com/transit-plan).",
          news_usage: "none"
        }

        expect(bill.reload.summary).to eq("Original public summary")
        latest_rev = bill.bill_summary_revisions.order(:id).last
        expect(latest_rev.publication_role).to eq("draft")
      end

      it "fails closed when summary is modified without a news_usage declaration" do
        sway_locale, _user = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.summary = "Original public summary"
        bill.save!

        put "/bills/#{bill.id}", params: {
          summary: "New summary text without declaration"
        }

        expect(bill.reload.summary).to eq("Original public summary")
        latest_rev = bill.bill_summary_revisions.order(:id).last
        expect(latest_rev.publication_role).to eq("draft")
      end

      it "does not leak unapproved summary into bills.summary when commit publish fails under lock" do
        sway_locale, _user = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.summary = "Pristine original public summary"
        bill.save!
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)

        valid_summary = "Council approved 100 new electric buses [Source](https://baltimorebanner.com/transit-plan)."

        allow(ManualNewsSummaryPublicationService).to receive(:publish!).and_wrap_original do |original_method, **kwargs|
          if kwargs[:dry_run] == true
            original_method.call(**kwargs)
          else
            draft_rev = BillSummaryRevision.record_revision!(
              bill: bill,
              summary_markdown: kwargs[:summary_markdown],
              origin: "operator_edit",
              publication_role: "draft",
              review_state: "reviewed"
            )
            ManualNewsSummaryPublicationService::Result.new(
              status: :stale_version_lock,
              errors: ["Concurrent stale version lock detected"],
              reasons: ["Text version changed during lock acquisition"],
              revision: draft_rev
            )
          end
        end

        expect_any_instance_of(BillsController).not_to receive(:create_vote)

        put "/bills/#{bill.id}", params: {
          summary: valid_summary,
          news_usage: "cited",
          source_uses: [
            {
              bill_news_article_id: approved_bna.id,
              text_version_id: text_version.id,
              claim_text: "Council approved 100 new electric buses",
              evidence_excerpt: "Council approved 100 new electric buses for city routes.",
              citation_url: "https://baltimorebanner.com/transit-plan"
            }
          ]
        }

        expect(bill.reload.summary).to eq("Pristine original public summary")
        latest_rev = bill.bill_summary_revisions.order(:id).last
        expect(latest_rev.publication_role).to eq("draft")
        expect(latest_rev.summary_markdown).to eq(valid_summary)
        expect(flash[:notice]).not_to eq("Bill Updated")
      end

      it "returns 422 unprocessable_content for mobile API when commit publish fails" do
        sway_locale, _user = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.summary = "Pristine original public summary"
        bill.save!
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)

        valid_summary = "Council approved 100 new electric buses [Source](https://baltimorebanner.com/transit-plan)."

        allow(ManualNewsSummaryPublicationService).to receive(:publish!).and_wrap_original do |original_method, **kwargs|
          if kwargs[:dry_run] == true
            original_method.call(**kwargs)
          else
            draft_rev = BillSummaryRevision.record_revision!(
              bill: bill,
              summary_markdown: kwargs[:summary_markdown],
              origin: "operator_edit",
              publication_role: "draft",
              review_state: "reviewed"
            )
            ManualNewsSummaryPublicationService::Result.new(
              status: :stale_version_lock,
              errors: ["Concurrent stale version lock detected"],
              reasons: ["Text version changed during lock acquisition"],
              revision: draft_rev
            )
          end
        end

        put "/bills/#{bill.id}.json", params: {
          summary: valid_summary,
          news_usage: "cited",
          source_uses: [
            {
              bill_news_article_id: approved_bna.id,
              text_version_id: text_version.id,
              claim_text: "Council approved 100 new electric buses",
              evidence_excerpt: "Council approved 100 new electric buses for city routes.",
              citation_url: "https://baltimorebanner.com/transit-plan"
            }
          ]
        }

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json.dig("error", "code")).to eq("validation_failed")
        expect(bill.reload.summary).to eq("Pristine original public summary")
      end

      it "never passes :summary to @bill.update when summary_changed is true" do
        sway_locale, _user = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.summary = "Pristine original public summary"
        bill.save!

        expect_any_instance_of(Bill).to receive(:update) do |_instance, update_attrs|
          expect(update_attrs).not_to have_key(:summary)
          expect(update_attrs).not_to have_key("summary")
          true
        end

        put "/bills/#{bill.id}", params: {
          summary: "New clean summary text without news links",
          news_usage: "none",
          title: "New Title Here"
        }

        expect(response).to have_http_status(:redirect)
      end

      it "preserves pristine public summary and records draft when commit publish fails post-rollback under adversarial conflict" do
        grounding_adapter = double("news claim grounding adapter", generate_news_claim_grounding: {"verdict" => "supported", "reason" => "Fixture grounding response"})
        allow(Llm::Client).to receive(:build).and_return(grounding_adapter)
        sway_locale, admin = setup
        bill, _params = build_bill_params.call(sway_locale)
        bill.summary = "Pristine original public summary"
        bill.save!
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)

        valid_claim_text = "Council approved 100 new electric buses"
        valid_excerpt = "Council approved 100 new electric buses for city routes."
        valid_citation_url = "https://baltimorebanner.com/transit-plan"
        valid_summary = "#{valid_claim_text} [Source](#{valid_citation_url})."

        expect(approved_bna).to receive(:withdraw_approval!).with(by: admin).and_call_original
        allow(ManualNewsSummaryPublicationService).to receive(:publish!).and_wrap_original do |original_method, **kwargs|
          approved_bna.withdraw_approval!(by: admin) unless kwargs[:dry_run] == true
          original_method.call(**kwargs)
        end

        vote_count_before = bill.legislator_votes.count

        put "/bills/#{bill.id}", params: {
          summary: valid_summary,
          news_usage: "cited",
          source_uses: [
            {
              bill_news_article_id: approved_bna.id,
              text_version_id: text_version.id,
              claim_text: valid_claim_text,
              evidence_excerpt: valid_excerpt,
              citation_url: valid_citation_url
            }
          ]
        }

        expect(response).to be_redirect
        expect(flash[:notice]).not_to eq("Bill Updated")
        expect(bill.reload.summary).to eq("Pristine original public summary")
        expect(bill.legislator_votes.count).to eq(vote_count_before)

        draft_rev = bill.bill_summary_revisions.order(:id).last
        expect(draft_rev).to be_present
        expect(draft_rev.publication_role).to eq("draft")
        expect(draft_rev.summary_markdown).to eq(valid_summary)
      end
    end
  end

  describe "DELETE /bills/:id" do
    it "destroys the bill and its dependent sending-service-domain and testimony-coverage rows" do
      _sway_locale, admin = setup
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, [admin.phone])
      complete_registration_with_active_link(admin)
      sign_in(admin)
      bill = create(:bill)
      campaign = create(:campaign, bill: bill)
      sending_service_domain_bill = create(:sending_service_domain_bill, bill: bill)
      testimony_coverage_acknowledgement = create(:testimony_coverage_acknowledgement, bill: bill)

      delete "/bills/#{bill.id}"

      expect(response).to have_http_status(:redirect)
      expect(Bill.exists?(bill.id)).to be false
      expect(Campaign.exists?(campaign.id)).to be false
      expect(SendingServiceDomainBill.exists?(sending_service_domain_bill.id)).to be false
      expect(TestimonyCoverageAcknowledgement.exists?(testimony_coverage_acknowledgement.id)).to be false
    end
  end

  describe "DELETE /bills/legislation_pipeline_runs/:id" do
    # Cancelling happens entirely inside Rails: it flips the local state
    # machine to cancelled. Nothing is sent to an outside service.
    it "marks the run cancelled and redirects with notice" do
      _sway_locale, admin = setup
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, [admin.phone])
      complete_registration_with_active_link(admin)
      sign_in(admin)
      run = create(:legislation_pipeline_run, :running)
      delete cancel_pipeline_run_bill_path(run.id)
      expect(response).to redirect_to(new_bill_creator_path(bill_creator_tab: :pipeline))
      expect(flash[:notice]).to match(/cancelled/i)
      expect(run.reload.status).to eq("cancelled")
      follow_redirect!
      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props[:tab_key]).to eq("pipeline")
    end

    it "redirects to the Pipeline & LLM tab of a per-bill run" do
      _sway_locale, admin = setup
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, [admin.phone])
      complete_registration_with_active_link(admin)
      sign_in(admin)
      bill = create(:bill)
      run = create(:legislation_pipeline_run, :running, bill: bill)
      delete cancel_pipeline_run_bill_path(run.id)
      expect(response).to redirect_to(pipeline_bill_creator_path(id: bill.id))
      expect(run.reload.status).to eq("cancelled")
    end

    it "sets flash alert when the run is already in a terminal status" do
      _sway_locale, admin = setup
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, [admin.phone])
      complete_registration_with_active_link(admin)
      sign_in(admin)
      run = create(:legislation_pipeline_run)
      run.start_running!
      run.mark_completed!
      delete cancel_pipeline_run_bill_path(run.id)
      expect(flash[:alert]).to be_present
    end
  end

  # @lat: [[identity-and-access#The admin gate is a lint rule]]
  describe "admin gate on the pipeline-run lifecycle routes" do
    include_examples "requires sway admin",
      verb: :delete,
      path: "/bills/legislation_pipeline_runs/1"

    include_examples "requires sway admin",
      verb: :post,
      path: "/bills/legislation_pipeline_runs/1/resume"

    include_examples "requires sway admin",
      verb: :post,
      path: "/bills/legislation_pipeline_runs/1/restart"
  end

  # @lat: [[identity-and-access#The admin gate is a lint rule]]
  describe "admin gate on the remaining guarded actions" do
    include_examples "requires sway admin",
      verb: :get,
      path: "/admin/bill_creator/new"

    # The canonical edit URL a signed-in admin's new "Edit bill" link points at
    # Covered separately from /admin/bill_creator/new above:
    # that route hits BillsController#new, this one hits #edit.
    include_examples "requires sway admin",
      verb: :get,
      path: "/admin/bill_creator/1/creator"

    include_examples "requires sway admin",
      verb: :patch,
      path: "/bills/1"

    include_examples "requires sway admin",
      verb: :delete,
      path: "/bills/1"

    include_examples "requires sway admin",
      verb: :post,
      path: "/bills/1/generate_summary"

    include_examples "requires sway admin",
      verb: :post,
      path: "/bills/1/approve_org_position"

    include_examples "requires sway admin",
      verb: :post,
      path: "/bills/1/restore_summary_revision"
  end

  describe "POST /bills/:id/restore_summary_revision" do
    it "restores previous revision text and records a restoration revision with provenance" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale: sway_locale, summary: "Current active summary")
      old_rev = BillSummaryRevision.create!(
        bill: bill,
        summary_markdown: "Old historical summary markdown",
        origin: "model_generation",
        llm_provider: "claude",
        llm_model: "claude-3-5-sonnet",
        publication_role: "published",
        review_state: "reviewed"
      )

      expect {
        post "/bills/#{bill.id}/restore_summary_revision", params: {revision_id: old_rev.id, news_usage: "none"}
      }.to change { bill.bill_summary_revisions.count }.by(1)

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include(summary_bill_creator_path(bill))

      expect(bill.reload.summary).to eq("Old historical summary markdown")

      restore_rev = bill.bill_summary_revisions.order(:id).last
      expect(restore_rev.origin).to eq("restoration")
      expect(restore_rev.restored_from_id).to eq(old_rev.id)
      expect(restore_rev.summary_markdown).to eq("Old historical summary markdown")
      expect(restore_rev.actor).to eq(user)
      expect(restore_rev.publication_role).to eq("published")
      expect(restore_rev.review_state).to eq("reviewed")
      expect(restore_rev.llm_provider).to eq("claude")
      expect(restore_rev.llm_model).to eq("claude-3-5-sonnet")
    end

    it "restoring a legacy clean snapshotless revision without news_usage declaration restores as draft" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale: sway_locale, summary: "Current active summary")
      clean_rev = BillSummaryRevision.create!(
        bill: bill,
        summary_markdown: "Clean historical summary without news links",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed",
        news_source_snapshot: nil
      )

      post "/bills/#{bill.id}/restore_summary_revision", params: {revision_id: clean_rev.id}

      expect(bill.reload.summary).to eq("Current active summary")
      latest_rev = bill.bill_summary_revisions.order(:id).last
      expect(latest_rev.publication_role).to eq("draft")
      expect(response).to redirect_to(summary_bill_creator_path(bill, draft_revision_id: latest_rev.id))
      expect(flash[:notice]).to eq("Legacy revision restored as draft. Please review and declare news usage before publishing.")

      get summary_bill_creator_path(bill, draft_revision_id: latest_rev.id)
      expect(response).to have_http_status(:ok)
      review_draft = inertia.props[:review_draft_revision]
      expect(review_draft).to be_present
      expect(review_draft[:id]).to eq(latest_rev.id)
      expect(review_draft[:summary_markdown]).to eq("Clean historical summary without news links")
      expect(bill.reload.summary).to eq("Current active summary")

      patch "/bills/#{bill.id}", params: {
        summary: latest_rev.summary_markdown,
        return_tab: "summary",
        news_usage: "none"
      }
      expect(response).to redirect_to(summary_bill_creator_path(bill))
      expect(bill.reload.summary).to eq("Clean historical summary without news links")
      published_rev = bill.bill_summary_revisions.order(:id).last
      expect(published_rev.publication_role).to eq("published")
    end

    it "refuses to restore a revision from another bill with 404" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale: sway_locale)
      other_bill = create(:bill, sway_locale: sway_locale, scheduled_release_date_utc: 3.weeks.from_now)
      other_rev = BillSummaryRevision.create!(
        bill: other_bill,
        summary_markdown: "Other bill summary",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed"
      )

      post "/bills/#{bill.id}/restore_summary_revision", params: {revision_id: other_rev.id}

      expect(response).to have_http_status(:not_found)
    end

    it "rejects stale restoration cleanly without altering text when expected_summary does not match" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale: sway_locale, summary: "Current active summary")
      old_rev = BillSummaryRevision.create!(
        bill: bill,
        summary_markdown: "Old historical summary markdown",
        origin: "model_generation",
        publication_role: "published",
        review_state: "reviewed"
      )

      expect {
        post "/bills/#{bill.id}/restore_summary_revision", params: {
          revision_id: old_rev.id,
          expected_summary: "Stale summary which does not match"
        }
      }.not_to change { bill.bill_summary_revisions.count }

      expect(bill.reload.summary).to eq("Current active summary")
      expect(response).to redirect_to(summary_bill_creator_path(bill))
      expect(flash[:alert]).to eq("The bill summary was modified by another operator. Please review before restoring.")
    end

    it "restoring a legacy snapshotless news revision cannot replace public content; the submitted text survives as a draft" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale: sway_locale, summary: "Current active summary")
      legacy_news_rev = BillSummaryRevision.create!(
        bill: bill,
        summary_markdown: "Legacy summary with news link [Banner](https://baltimorebanner.com/story)",
        origin: "model_generation",
        publication_role: "published",
        review_state: "reviewed",
        news_source_snapshot: nil
      )

      post "/bills/#{bill.id}/restore_summary_revision", params: {revision_id: legacy_news_rev.id}

      expect(bill.reload.summary).to eq("Current active summary")
      latest_rev = bill.bill_summary_revisions.order(:id).last
      expect(latest_rev.publication_role).to eq("draft")
      expect(latest_rev.origin).to eq("restoration")
    end

    it "restoring a revision with a stale snapshot cannot replace public content; the submitted text survives as a draft" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale: sway_locale, summary: "Current active summary")
      article = create(:news_article, canonical_url: "https://baltimorebanner.com/transit")
      tv = create(:news_article_text_version, :extracted, news_article: article, text: "Some article text")
      bna = create(:bill_news_article, :approved, bill: bill, news_article: article, current_text_version: tv)
      snapshot = NewsArticleSourceSnapshotService.capture!(bill: bill, purpose: "summary", actor: user, sources: [bna])

      news_rev = BillSummaryRevision.create!(
        bill: bill,
        summary_markdown: "News summary text citing [Banner](https://baltimorebanner.com/transit)",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed",
        news_source_snapshot: snapshot
      )

      bna.withdraw_approval!(by: user)

      post "/bills/#{bill.id}/restore_summary_revision", params: {revision_id: news_rev.id}

      expect(bill.reload.summary).to eq("Current active summary")
      latest_rev = bill.bill_summary_revisions.order(:id).last
      expect(latest_rev.publication_role).to eq("draft")
    end
  end
end
