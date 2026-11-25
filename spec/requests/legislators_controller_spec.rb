require "rails_helper"
require Rails.root.join("db", "seeds", "models", "legislator")

RSpec.describe "LegislatorsController", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "GET /index" do
    # @lat: [[lat.md/reference/official-service-evidence-tests#Official service evidence tests#A presidential row without the curated marker creates no person]]
    it "does not turn a legacy presidential roster row into a reader representative" do
      _home_locale, = setup
      congress = create(:sway_locale, city: "congress", state: "congress", country: "United States")
      allow(SeedLegislator).to receive(:read_legislators).and_return([{
        "bioguideId" => "POTUS",
        "name" => "Test, President",
        "partyName" => "Independent",
        "state" => "US",
        "currentMember" => true,
        "terms" => {"item" => [{"chamber" => "White House", "startYear" => 2025}]}
      }])

      SeedLegislator.run([congress])
      get "/legislators", params: {sway_locale_id: congress.id}, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch("legislators")).to be_empty
      expect(Legislator.find_by(sway_locale: congress, external_id: "POTUS")).to be_nil
    end

    it "shows a supported President on the standard score path and preserves legislative scores" do
      _home_locale, user = setup
      congress = create(:sway_locale, city: "congress", state: "congress", country: "United States")
      create(:district, sway_locale: congress, name: "US0")
      legislative_district = create(:district, sway_locale: congress, name: "MD1")
      profile = {
        capability: "supported",
        publisher: "records.example.gov",
        jurisdiction: "fixture_executive",
        source_url: "https://records.example.gov/service",
        identity_source: "us_executive",
        office_identity: "us-president",
        fact_type: "executive_service",
        records_path: "records",
        date_semantics: {start: "inclusive", end: "exclusive"},
        fields: %i[id office_identity first_name last_name party title chamber district start_date end_date presence]
          .to_h { |key| [key, key.to_s] }
      }
      record = {
        id: "request-president",
        office_identity: "us-president",
        first_name: "Fixture",
        last_name: "President",
        party: "Independent",
        title: "President",
        chamber: "Executive",
        district: "US0",
        start_date: "2025-01-20",
        end_date: "2029-01-20",
        presence: "present"
      }
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/service") { [200, {"Content-Type" => "application/json"}, {records: [record]}.to_json] }
      end
      connection = Faraday.new { |faraday| faraday.adapter :test, stubs }
      service_result = Legislation::Adapters::GenericRosterAdapter
        .new({roster_rules: {official_service: profile}}, connection:)
        .fetch_official_service(sway_locale: congress)
      OfficialEvidence::SeedService.new(sway_locale: congress, result: service_result).call
      president_identity = service_result.facts.fetch(0).person_identity || raise("President fixture must have an identity")
      president = LegislatorIdentifier.legislator_for(
        sway_locale: congress,
        identity: president_identity
      ) || raise("Supported President should be seeded")
      president_link = create(:user_legislator, user:, legislator: president)

      house_seat = Seat.find_or_create_by_identity!(
        district: legislative_district,
        office_identity: "us-house-md1",
        title: "Representative",
        chamber: "House"
      )
      representative = create(:legislator, sway_locale: congress, district: legislative_district)
      representative_term = create(
        :legislator_term,
        legislator: representative,
        district: legislative_district,
        seat: house_seat
      )
      user_legislator = create(:user_legislator, user:, legislator: representative)
      create(
        :user_legislator_term_score,
        user_legislator:,
        legislator_term: representative_term,
        count_agreed: 3,
        count_disagreed: 1
      )
      unrelated_termless = create(:legislator, sway_locale: congress)
      create(:user_legislator, user:, legislator: unrelated_termless, active: false)

      get "/legislators", params: {sway_locale_id: congress.id}, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      rows = response.parsed_body.fetch("legislators")
      president_row = rows.find { |row| row.fetch("id") == president.id }
      representative_row = rows.find { |row| row.fetch("id") == representative.id }
      expect(rows.map { |row| row.fetch("id") }).not_to include(unrelated_termless.id)
      expect(president_row.fetch("user_legislator_score")).to be_nil
      expect(president_row.fetch("lifetime_score")).to eq(
        UserLegislatorTermScoreResource.lifetime_hash_for(president_link).as_json
      )
      expect(representative_row.fetch("user_legislator_score").fetch("count_agreed")).to eq(3)
      expect(representative_row.fetch("lifetime_score").fetch("count_agreed")).to eq(3)
      expect(president.legislator_votes).to be_empty
      expect(UserLegislatorTermScore.where(user_legislator: president_link)).to be_empty

      president_term = president.active_term || president.legislator_terms.first!
      create(
        :user_legislator_term_score,
        user_legislator: president_link,
        legislator_term: president_term,
        count_agreed: 2,
        count_disagreed: 1
      )

      get "/legislators", params: {sway_locale_id: congress.id}, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      updated_rows = response.parsed_body.fetch("legislators")
      updated_president_row = updated_rows.find { |row| row.fetch("id") == president.id }
      expect(updated_president_row.fetch("user_legislator_score").fetch("count_agreed")).to eq(2)
      expect(updated_president_row.fetch("lifetime_score").fetch("count_agreed")).to eq(2)
    end

    it "renders the Legislators component" do
      _sway_locale, _user = setup

      get "/legislators"

      expect(inertia).to render_component Pages::LEGISLATORS
    end

    it "renders the legislators prop inline (not deferred) so prefetch warms the JSON" do
      sway_locale, _ = setup
      legislator = sway_locale.legislators.first
      expect(legislator).to_not be_nil

      get "/legislators"

      expect(inertia).not_to have_deferred_props(:legislators)
      expect(inertia).to have_props { |p| p[:legislators].is_a?(Array) }
    end

    # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
    it "passes the filters prop using canonical ?legislators_search=" do
      _sway_locale, _user = setup

      get "/legislators", params: {legislators_search: "smith"}

      expect(inertia).to have_props(filters: {search: "smith"})
    end

    # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
    it "falls back to legacy ?search= when ?legislators_search= is absent" do
      _sway_locale, _user = setup

      get "/legislators", params: {search: "smith"}

      expect(inertia).to have_props(filters: {search: "smith"})
    end

    # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
    it "gives precedence to ?legislators_search= over legacy ?search= when both are provided" do
      _sway_locale, _user = setup

      get "/legislators", params: {legislators_search: "smith", search: "jones"}

      expect(inertia).to have_props(filters: {search: "smith"})
    end

    it "skips historical_score_explanations queries when the table is absent" do
      _sway_locale, _user = setup
      allow(HistoricalScoreExplanation).to receive(:table_exists?).and_return(false)

      statements = [] #: Array[String]
      ActiveSupport::Notifications.subscribed(->(*, payload) { statements << payload[:sql].to_s }, "sql.active_record") do
        get "/legislators", headers: {"Accept" => "application/json"}
      end

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch("legislators")).not_to be_empty
      expect(statements.grep(/historical_score_explanations/i)).to be_empty
    end
  end

  # @lat: [[legislators-controller-design#Why waiting_for_new_term distinguishes empty list causes]]
  describe "GET /index when nobody is serving" do
    it "says the term has ended when the reader's representatives have all left office" do
      sway_locale, _user = setup
      legislator = sway_locale.legislators.first #: Legislator
      legislator.legislator_terms.update_all(term_start_year: 2019, term_end_year: 2021)

      get "/legislators"

      expect(inertia).to render_component Pages::LEGISLATORS
      expect(inertia.props[:legislators]).to be_empty
      expect(inertia.props[:waiting_for_new_term]).to be(true)
    end

    # Viewing a place the reader has no representatives in at all — the case
    # "Search again" exists for. Nothing has ended here; Sway simply has nobody
    # for them in this jurisdiction.
    it "does not say the term has ended in a place the reader has nobody in" do
      _sway_locale, _user = setup
      elsewhere = create(:sway_locale, city: "congress", state: "congress", country: "United States")

      get "/legislators", params: {sway_locale_id: elsewhere.id}

      expect(inertia).to render_component Pages::LEGISLATORS
      expect(inertia.props[:legislators]).to be_empty
      expect(inertia.props[:waiting_for_new_term]).to be(false)
    end

    it "does not say the term has ended while somebody is still serving" do
      _sway_locale, _user = setup

      get "/legislators"

      expect(inertia.props[:legislators]).not_to be_empty
      expect(inertia.props[:waiting_for_new_term]).to be(false)
    end
  end

  describe "GET /legislators/:id" do
    it "renders the dedicated Legislator detail page (not the list)" do
      sway_locale, _user = setup
      legislator = sway_locale.legislators.first
      expect(legislator).to_not be_nil

      get "/legislators/#{legislator.id}"

      expect(inertia).to render_component Pages::LEGISLATOR
    end

    it "passes a single legislator prop with the user_legislator_score and lifetime_score keys" do
      sway_locale, _user = setup
      legislator = sway_locale.legislators.first
      expect(legislator).to_not be_nil

      get "/legislators/#{legislator.id}"

      expect(inertia).to have_props { |p|
        p[:legislator].is_a?(Hash) &&
          p[:legislator].key?(:user_legislator_score) &&
          p[:legislator].key?(:lifetime_score)
      }
    end

    # @lat: [[legislators-controller-design#Score props retain their established shape]]
    it "resolves the frozen most-recent-term score + lifetime through a DEACTIVATED link" do
      sway_locale, user = setup
      district = create(:district, sway_locale:, name: "#{sway_locale.region_code}8")
      former_rep = create(:legislator, district:)
      prior_term = create(:legislator_term, :prior_term, legislator: former_rep, district:)
      user_legislator = create(:user_legislator, user:, legislator: former_rep)
      create(:user_legislator_term_score, user_legislator:, legislator_term: prior_term,
        count_agreed: 7, count_disagreed: 2, count_no_legislator_vote: 1, count_legislator_abstained: 0)
      user_legislator.update!(active: false)

      get "/legislators/#{former_rep.id}", headers: {"Accept" => "application/json"}

      legislator_payload = response.parsed_body["legislator"]
      # The payload carries the term's start and end years, so the first tab on
      # the detail page can relabel itself "2023–2025".
      expect(legislator_payload["term_start_year"]).to eq(2023)
      expect(legislator_payload["term_end_year"]).to eq(2025)

      current_score = legislator_payload["user_legislator_score"]
      expect(current_score).not_to be_nil
      expect(current_score["count_agreed"]).to eq(7)
      expect(current_score["count_disagreed"]).to eq(2)

      lifetime = legislator_payload["lifetime_score"]
      expect(lifetime).not_to be_nil
      expect(lifetime["count_agreed"]).to eq(7)
      expect(lifetime["count_no_legislator_vote"]).to eq(1)
    end

    it "renders for an UNAUTHENTICATED visitor — skip_before_action keeps #show public (IN-C3)" do
      # Nobody is signed in: session_hash[:user_id] is never set, so
      # current_user is nil. Take away the skip_before_action
      # :authenticate_sway_user! and this would redirect or 401 instead of
      # rendering the detail page.
      legislator = create(:legislator)

      get "/legislators/#{legislator.id}"

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component Pages::LEGISLATOR
    end

    it "skips historical_score_explanations lookup for both linked and unlinked legislators when the table is absent" do
      sway_locale, _user = setup
      linked_legislator = sway_locale.legislators.first
      expect(linked_legislator).to_not be_nil
      other_district = create(:district, sway_locale:, name: "#{sway_locale.region_code}9")
      unlinked_sponsor = create(:legislator, sway_locale:, district: other_district)
      create(:legislator_term, legislator: unlinked_sponsor, district: other_district)

      allow(HistoricalScoreExplanation).to receive(:table_exists?).and_return(false)

      statements = [] #: Array[String]
      ActiveSupport::Notifications.subscribed(->(*, payload) { statements << payload[:sql].to_s }, "sql.active_record") do
        get "/legislators/#{linked_legislator.id}"
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component Pages::LEGISLATOR

        get "/legislators/#{unlinked_sponsor.id}", headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("legislator", "id")).to eq(unlinked_sponsor.id)
        expect(response.parsed_body.dig("legislator", "user_legislator_score")).to be_nil
        expect(response.parsed_body.dig("legislator", "terms", 0, "correction_explanation")).to be_nil

        expect { unlinked_sponsor.destroy! }.not_to raise_error
      end

      expect(statements.grep(/historical_score_explanations/i)).to be_empty
    end

    it "returns released Bills of the Month in the legislator's locale newest-first and excludes future, non-BOTM, and other-locale bills" do
      sway_locale, user = setup
      legislator = sway_locale.legislators.first
      term = legislator.active_term
      other_locale = create(:sway_locale, city: "congress", state: "congress", country: "United States")
      other_district = create(:district, sway_locale: other_locale, name: "US1")
      other_legislator = create(:legislator, sway_locale: other_locale, district: other_district)
      same_locale_peer = create(:legislator, sway_locale:, district: legislator.district)
      same_locale_peer_term = create(:legislator_term, legislator: same_locale_peer, district: legislator.district)

      older_bill = create(
        :bill,
        sway_locale:,
        legislator:,
        external_id: "BILL-OLDER",
        title: "Older Released Bill",
        scheduled_release_date_utc: 10.days.ago.to_date,
        status: Bill::Status::PASSED
      )
      newer_bill = create(
        :bill,
        sway_locale:,
        legislator:,
        external_id: "BILL-NEWER",
        title: "Newer Released Bill",
        scheduled_release_date_utc: Time.zone.today,
        status: Bill::Status::COMMITTEE
      )
      create(
        :bill,
        sway_locale:,
        legislator:,
        external_id: "BILL-FUTURE",
        title: "Future Scheduled Bill",
        scheduled_release_date_utc: 5.days.from_now.to_date
      )
      non_botm_bill = create(
        :bill,
        sway_locale:,
        legislator:,
        external_id: "BILL-NON-BOTM",
        title: "Unscheduled Bill"
      )
      non_botm_bill.update!(scheduled_release_date_utc: nil)
      create(
        :bill,
        sway_locale: other_locale,
        legislator: other_legislator,
        external_id: "BILL-OTHER-LOCALE",
        title: "Other Locale Bill",
        scheduled_release_date_utc: Time.zone.today
      )

      create(:legislator_vote, :for, bill: newer_bill, legislator:, legislator_term: term)
      create(:legislator_vote, :against, bill: newer_bill, legislator: same_locale_peer, legislator_term: same_locale_peer_term)
      create(:legislator_vote, :against, bill: older_bill, legislator:, legislator_term: term)
      create(:legislator_vote, :for, bill: older_bill, legislator: same_locale_peer, legislator_term: same_locale_peer_term)
      create(:user_vote, bill: newer_bill, user:, support: LegislatorVote::Support::FOR)
      create(:user_vote, bill: older_bill, user:, support: LegislatorVote::Support::FOR)

      get "/legislators/#{legislator.id}", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      votes = response.parsed_body.dig("legislator", "bill_of_the_month_votes")
      expect(votes).to eq(
        [
          {
            "bill_id" => newer_bill.id,
            "external_id" => "BILL-NEWER",
            "title" => "Newer Released Bill",
            "scheduled_release_date_utc" => Time.zone.today.iso8601,
            "status" => Bill::Status::COMMITTEE,
            "legislator_vote" => "FOR",
            "user_vote" => "FOR",
            "alignment" => "agreed"
          },
          {
            "bill_id" => older_bill.id,
            "external_id" => "BILL-OLDER",
            "title" => "Older Released Bill",
            "scheduled_release_date_utc" => 10.days.ago.to_date.iso8601,
            "status" => Bill::Status::PASSED,
            "legislator_vote" => "AGAINST",
            "user_vote" => "FOR",
            "alignment" => "disagreed"
          }
        ]
      )
    end

    it "populates user_vote and alignment for signed-in users and returns nil for both to anonymous visitors" do
      sway_locale, user = setup
      other_user = create(:user)
      legislator = sway_locale.legislators.first
      term = legislator.active_term
      bill = create(
        :bill,
        sway_locale:,
        legislator:,
        external_id: "BILL-AUTH-CHECK",
        title: "Auth Check Bill",
        scheduled_release_date_utc: Time.zone.today
      )
      create(:legislator_vote, :for, bill:, legislator:, legislator_term: term)
      create(:user_vote, bill:, user:, support: LegislatorVote::Support::FOR)
      create(:user_vote, bill:, user: other_user, support: LegislatorVote::Support::AGAINST)

      get "/legislators/#{legislator.id}", headers: {"Accept" => "application/json"}
      signed_in_vote = response.parsed_body.dig("legislator", "bill_of_the_month_votes", 0)
      expect(signed_in_vote).to include(
        "bill_id" => bill.id,
        "legislator_vote" => "FOR",
        "user_vote" => "FOR",
        "alignment" => "agreed"
      )

      session_hash.clear
      get "/legislators/#{legislator.id}", headers: {"Accept" => "application/json"}
      anonymous_vote = response.parsed_body.dig("legislator", "bill_of_the_month_votes", 0)
      expect(anonymous_vote).to include(
        "bill_id" => bill.id,
        "legislator_vote" => "FOR",
        "user_vote" => nil,
        "alignment" => nil
      )
    end

    it "returns bill_of_the_month_votes on an Inertia partial reload of only legislator" do
      sway_locale, user = setup
      legislator = sway_locale.legislators.first
      term = legislator.active_term
      bill = create(
        :bill,
        sway_locale:,
        legislator:,
        external_id: "BILL-PARTIAL-RELOAD",
        title: "Partial Reload Bill",
        scheduled_release_date_utc: Time.zone.today
      )
      create(:legislator_vote, :for, bill:, legislator:, legislator_term: term)
      create(:user_vote, bill:, user:, support: LegislatorVote::Support::FOR)

      get "/legislators/#{legislator.id}",
        headers: {
          "X-Inertia" => "true",
          "X-Inertia-Version" => InertiaRails.configuration.version.to_s,
          "X-Inertia-Partial-Component" => Pages::LEGISLATOR,
          "X-Inertia-Partial-Data" => "legislator"
        }

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::LEGISLATOR)
      votes = response.parsed_body.dig("props", "legislator", "bill_of_the_month_votes")
      expect(votes).to eq(
        [
          {
            "bill_id" => bill.id,
            "external_id" => "BILL-PARTIAL-RELOAD",
            "title" => "Partial Reload Bill",
            "scheduled_release_date_utc" => Time.zone.today.iso8601,
            "status" => bill.status,
            "legislator_vote" => "FOR",
            "user_vote" => "FOR",
            "alignment" => "agreed"
          }
        ]
      )
    end

    it "executes an identical SQL query count with 1 vs multiple released Bills of the Month" do
      sway_locale, user = setup
      legislator = sway_locale.legislators.first
      term = legislator.active_term

      first_bill = create(:bill, sway_locale:, legislator:, scheduled_release_date_utc: 1.day.ago.to_date)
      create(:legislator_vote, :for, bill: first_bill, legislator:, legislator_term: term)
      create(:user_vote, bill: first_bill, user:, support: LegislatorVote::Support::FOR)

      get "/legislators/#{legislator.id}", headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:ok)

      queries_one_bill = [] #: Array[String]
      sub_one = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        sql = payload[:sql].to_s
        next if payload[:name] == "SCHEMA" || payload[:cached] || sql.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|PRAGMA|SAVEPOINT|RELEASE)\b/i)

        queries_one_bill << sql
      end
      begin
        get "/legislators/#{legislator.id}", headers: {"Accept" => "application/json"}
      ensure
        ActiveSupport::Notifications.unsubscribe(sub_one)
      end

      (2..5).each do |days_ago|
        extra_bill = create(:bill, sway_locale:, legislator:, scheduled_release_date_utc: days_ago.days.ago.to_date)
        create(:legislator_vote, :against, bill: extra_bill, legislator:, legislator_term: term)
        create(:user_vote, bill: extra_bill, user:, support: LegislatorVote::Support::FOR)
      end

      queries_five_bills = [] #: Array[String]
      sub_five = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        sql = payload[:sql].to_s
        next if payload[:name] == "SCHEMA" || payload[:cached] || sql.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|PRAGMA|SAVEPOINT|RELEASE)\b/i)

        queries_five_bills << sql
      end
      begin
        get "/legislators/#{legislator.id}", headers: {"Accept" => "application/json"}
      ensure
        ActiveSupport::Notifications.unsubscribe(sub_five)
      end

      expect(response.parsed_body.dig("legislator", "bill_of_the_month_votes").length).to eq(5)
      expect(queries_one_bill.size).to eq(queries_five_bills.size)
    end

    it "serializes in-term Bills of the Month and recorded votes for executive seats including prior legislative terms" do
      sway_locale, user = setup
      district = create(:district, sway_locale:, name: "EXEC0")
      exec_seat = Seat.find_or_create_by_identity!(
        district:,
        office_identity: "mayor-exec",
        title: "Mayor",
        chamber: "Executive"
      )
      council_seat = Seat.find_or_create_by_identity!(
        district:,
        office_identity: "council-seat",
        title: "Councilmember",
        chamber: "Council"
      )
      mayor = create(:legislator, sway_locale:, district:)
      prior_term = create(
        :legislator_term,
        legislator: mayor,
        district:,
        seat: council_seat,
        title: "Councilmember",
        term_start_year: 2020,
        term_end_year: 2024,
        began_on: Date.new(2020, 1, 1),
        ended_on: Date.new(2024, 1, 1),
        began_on_source: LegislatorTerm::DateSource::PUBLISHED,
        ended_on_source: LegislatorTerm::DateSource::PUBLISHED
      )
      exec_term = create(
        :legislator_term,
        legislator: mayor,
        district:,
        seat: exec_seat,
        title: "Mayor",
        term_start_year: 2024,
        term_end_year: 2028,
        began_on: Date.new(2024, 1, 1),
        ended_on: Date.new(2028, 1, 1),
        began_on_source: LegislatorTerm::DateSource::PUBLISHED,
        ended_on_source: LegislatorTerm::DateSource::PUBLISHED
      )

      in_term_bill = create(
        :bill,
        sway_locale:,
        legislator: mayor,
        chamber: "council",
        scheduled_release_date_utc: Date.new(2024, 6, 1),
        house_vote_date_time_utc: Time.utc(2024, 5, 1, 12, 0, 0)
      )
      create(
        :legislator_vote,
        :for,
        bill: in_term_bill,
        legislator: mayor,
        legislator_term: exec_term
      )
      create(:user_vote, bill: in_term_bill, user:, support: LegislatorVote::Support::FOR)

      unvoted_in_term_bill = create(
        :bill,
        sway_locale:,
        legislator: mayor,
        chamber: "council",
        scheduled_release_date_utc: Date.new(2024, 7, 1),
        house_vote_date_time_utc: Time.utc(2024, 6, 15, 12, 0, 0)
      )

      unvoted_out_of_term_bill = create(
        :bill,
        sway_locale:,
        legislator: mayor,
        chamber: "council",
        scheduled_release_date_utc: Date.new(2018, 6, 1),
        house_vote_date_time_utc: Time.utc(2018, 5, 1, 12, 0, 0)
      )

      prior_term_bill = create(
        :bill,
        sway_locale:,
        legislator: mayor,
        chamber: "council",
        scheduled_release_date_utc: Date.new(2022, 6, 1),
        house_vote_date_time_utc: Time.utc(2022, 5, 1, 12, 0, 0)
      )
      create(
        :legislator_vote,
        :against,
        bill: prior_term_bill,
        legislator: mayor,
        legislator_term: prior_term
      )
      create(:user_vote, bill: prior_term_bill, user:, support: LegislatorVote::Support::FOR)

      get "/legislators/#{mayor.id}", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      votes = response.parsed_body.dig("legislator", "bill_of_the_month_votes")
      expect(votes).to be_an(Array)
      expect(votes.length).to eq(3)
      expect(votes).to contain_exactly(
        include(
          "bill_id" => in_term_bill.id,
          "legislator_vote" => "FOR",
          "user_vote" => "FOR",
          "alignment" => "agreed"
        ),
        include(
          "bill_id" => prior_term_bill.id,
          "legislator_vote" => "AGAINST",
          "user_vote" => "FOR",
          "alignment" => "disagreed"
        ),
        include(
          "bill_id" => unvoted_in_term_bill.id,
          "legislator_vote" => nil
        )
      )
      expect(votes.pluck("bill_id")).not_to include(unvoted_out_of_term_bill.id)
    end

    it "excludes Bills of the Month from before a legislator took office or after a former legislator left office, unless they have a recorded vote" do
      congress = create(:sway_locale, city: "congress", state: "congress", country: "United States")
      district = create(:district, sway_locale: congress, name: "MD1")
      house_seat = Seat.find_or_create_by_identity!(
        district:,
        office_identity: "md-house-district-1",
        title: "Rep.",
        chamber: "House of Representatives"
      )
      former_rep = create(:legislator, sway_locale: congress, district:)
      create(
        :legislator_term,
        legislator: former_rep,
        district:,
        seat: house_seat,
        title: "Rep.",
        term_start_year: 2023,
        term_end_year: 2025
      )

      before_term_bill = create(
        :bill,
        sway_locale: congress,
        legislator: former_rep,
        chamber: "house",
        scheduled_release_date_utc: Date.new(2022, 6, 1),
        house_vote_date_time_utc: Time.utc(2022, 6, 1, 12, 0, 0)
      )
      in_term_unvoted_bill = create(
        :bill,
        sway_locale: congress,
        legislator: former_rep,
        chamber: "house",
        scheduled_release_date_utc: Date.new(2024, 5, 1),
        house_vote_date_time_utc: Time.utc(2024, 5, 1, 12, 0, 0)
      )
      after_term_bill = create(
        :bill,
        sway_locale: congress,
        legislator: former_rep,
        chamber: "house",
        scheduled_release_date_utc: Date.new(2026, 2, 1),
        house_vote_date_time_utc: Time.utc(2026, 2, 1, 12, 0, 0)
      )
      voted_outside_window_bill = create(
        :bill,
        sway_locale: congress,
        legislator: former_rep,
        chamber: "house",
        scheduled_release_date_utc: Date.new(2021, 9, 1),
        house_vote_date_time_utc: Time.utc(2021, 9, 1, 12, 0, 0)
      )
      create(
        :legislator_vote,
        :for,
        bill: voted_outside_window_bill,
        legislator: former_rep,
        legislator_term: former_rep.legislator_terms.first
      )

      get "/legislators/#{former_rep.id}", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      votes = response.parsed_body.dig("legislator", "bill_of_the_month_votes")
      expect(votes.pluck("bill_id")).to eq([in_term_unvoted_bill.id, voted_outside_window_bill.id])
      expect(votes.pluck("bill_id")).not_to include(before_term_bill.id, after_term_bill.id)
      expect(votes.first["legislator_vote"]).to be_nil
      expect(votes.second["legislator_vote"]).to eq("FOR")
    end

    it "filters bicameral Bills of the Month by the chamber the legislator sat in across terms" do
      congress = create(:sway_locale, city: "congress", state: "congress", country: "United States")
      house_district = create(:district, sway_locale: congress, name: "MD3")
      senate_district = create(:district, sway_locale: congress, name: "MD0")
      house_seat = Seat.find_or_create_by_identity!(
        district: house_district,
        office_identity: "md-house-district-3",
        title: "Rep.",
        chamber: "House of Representatives"
      )
      senate_seat = Seat.find_or_create_by_identity!(
        district: senate_district,
        office_identity: "md-senate-class-1",
        title: "Sen.",
        chamber: "Senate"
      )
      chamber_switcher = create(:legislator, sway_locale: congress, district: senate_district)
      create(
        :legislator_term,
        legislator: chamber_switcher,
        district: house_district,
        seat: house_seat,
        title: "Rep.",
        term_start_year: 2023,
        term_end_year: 2025
      )
      create(
        :legislator_term,
        legislator: chamber_switcher,
        district: senate_district,
        seat: senate_seat,
        title: "Sen.",
        term_start_year: 2025,
        term_end_year: 2031
      )

      house_2024_bill = create(
        :bill,
        sway_locale: congress,
        legislator: chamber_switcher,
        chamber: "house",
        scheduled_release_date_utc: Date.new(2024, 4, 1),
        house_vote_date_time_utc: Time.utc(2024, 4, 1, 15, 0, 0)
      )
      senate_2024_bill = create(
        :bill,
        sway_locale: congress,
        legislator: chamber_switcher,
        chamber: "senate",
        scheduled_release_date_utc: Date.new(2024, 6, 1),
        senate_vote_date_time_utc: Time.utc(2024, 6, 1, 15, 0, 0)
      )
      house_2026_bill = create(
        :bill,
        sway_locale: congress,
        legislator: chamber_switcher,
        chamber: "house",
        scheduled_release_date_utc: Date.new(2026, 3, 1),
        house_vote_date_time_utc: Time.utc(2026, 3, 1, 15, 0, 0)
      )
      senate_2026_bill = create(
        :bill,
        sway_locale: congress,
        legislator: chamber_switcher,
        chamber: "senate",
        scheduled_release_date_utc: Date.new(2026, 5, 1),
        senate_vote_date_time_utc: Time.utc(2026, 5, 1, 15, 0, 0)
      )

      get "/legislators/#{chamber_switcher.id}", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      votes = response.parsed_body.dig("legislator", "bill_of_the_month_votes")
      expect(votes.pluck("bill_id")).to eq([senate_2026_bill.id, house_2024_bill.id])
      expect(votes.pluck("bill_id")).not_to include(senate_2024_bill.id, house_2026_bill.id)
    end

    it "orders terms descending, distinguishes 0% agreement from unvoted terms, and serializes executive and legislative term scores without mutations" do
      congress = create(:sway_locale, city: "congress", state: "congress", country: "United States")
      user = create(:user)
      session_hash[:user_id] = user.id
      district = create(:district, sway_locale: congress, name: "MD1")
      switcher = create(:legislator, sway_locale: congress, district:)
      switcher_user_leg = create(:user_legislator, user:, legislator: switcher)

      council_seat = Seat.find_or_create_by_identity!(district:, office_identity: "council-seat-#{district.id}", title: "Councilmember", chamber: "Council")
      exec_seat = Seat.find_or_create_by_identity!(district:, office_identity: "mayor-exec-#{district.id}", title: "Mayor", chamber: "Executive")

      term_2017 = create(:legislator_term, :prior_term, legislator: switcher, district:, seat: council_seat, term_start_year: 2017, term_end_year: 2019)
      term_2019 = create(:legislator_term, :prior_term, legislator: switcher, district:, seat: council_seat, term_start_year: 2019, term_end_year: 2023)
      exec_term = create(:legislator_term, legislator: switcher, district:, seat: exec_seat, term_start_year: 2023, term_end_year: 2027, ended_on: nil)

      create(:legislator_district_score, legislator_term: exec_term, count_agreed: 40, count_disagreed: 4)
      create(:user_legislator_term_score, user_legislator: switcher_user_leg, legislator_term: term_2019, count_agreed: 0, count_disagreed: 5, count_no_legislator_vote: 0, count_legislator_abstained: 0)
      create(:user_legislator_term_score, user_legislator: switcher_user_leg, legislator_term: exec_term, count_agreed: 18, count_disagreed: 2, count_no_legislator_vote: 0, count_legislator_abstained: 0)
      create(:historical_score_explanation, user:, legislator: switcher, score_type: "term_#{term_2019.id}", title: "2019 Audit", body: "Corrected.", delta: 0.05)

      expect(ScoreRecomputeService).not_to receive(:recompute_legislator!)
      get "/legislators/#{switcher.id}", headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:ok)

      terms = response.parsed_body.dig("legislator", "terms")
      expect(terms.pluck("term_start_year")).to eq([2023, 2019, 2017])

      exec_payload = terms.find { |t| t["id"] == exec_term.id }
      t2019_payload = terms.find { |t| t["id"] == term_2019.id }
      t2017_payload = terms.find { |t| t["id"] == term_2017.id }

      expect(exec_payload["is_executive"]).to be(true)
      expect(exec_payload["user_score"]["count_agreed"]).to eq(18)
      expect(exec_payload["correction_explanation"]).to be_nil

      expect(t2019_payload["is_executive"]).to be(false)
      expect(t2019_payload["user_score"]).to eq({"count_agreed" => 0, "count_disagreed" => 5, "count_no_legislator_vote" => 0, "count_legislator_abstained" => 0})
      expect(t2019_payload["correction_explanation"]).to include("title" => "2019 Audit", "score_type" => "term_#{term_2019.id}")
      expect(t2017_payload["user_score"]).to be_nil
    end

    it "treats unicameral council seats as eligible for council bills within the member's term and excludes out-of-term council bills" do
      sway_locale, _user = setup
      legislator = sway_locale.legislators.first
      council_seat = Seat.find_or_create_by_identity!(
        district: legislator.district,
        office_identity: "baltimore-council-1",
        title: "Council Member",
        chamber: "City Council"
      )
      legislator.active_term.update!(seat: council_seat, title: "Council Member")

      in_term_council_bill = create(
        :bill,
        sway_locale:,
        legislator:,
        external_id: "ORD-26-01",
        title: "In Term Council Ordinance",
        chamber: "council",
        introduced_date_time_utc: Time.utc(2026, 3, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2026, 4, 1)
      )
      pre_term_council_bill = create(
        :bill,
        sway_locale:,
        legislator:,
        external_id: "ORD-20-01",
        title: "Pre Term Council Ordinance",
        chamber: "council",
        introduced_date_time_utc: Time.utc(2020, 3, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2020, 4, 1)
      )

      get "/legislators/#{legislator.id}", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      votes = response.parsed_body.dig("legislator", "bill_of_the_month_votes")
      expect(votes.pluck("bill_id")).to eq([in_term_council_bill.id])
      expect(votes.pluck("bill_id")).not_to include(pre_term_council_bill.id)
    end
  end

  describe "GET /legislators eager-load" do
    it "preloads district.sway_locale so no N+1 SELECT on sway_locales" do
      sway_locale, _ = setup
      legislator = sway_locale.legislators.first
      expect(legislator).not_to be_nil

      # Check that a legislator's district can reach its sway_locale WITHOUT an
      # extra database query, thanks to the preloading in json_legislators. The
      # check is that the association is already loaded on the returned
      # user_legislator's legislator.district.
      get "/legislators"

      expect(response).to have_http_status(:ok)
      # The includes chain loads district AND district.sway_locale. If
      # to_builder's district.sway_locale.id call fired its own SELECT, strict
      # mode would raise a StrictLoadingViolationError. This example passing
      # means the preload does cover sway_locale.
      expect(inertia).to have_props { |p| p[:legislators].is_a?(Array) }
    end
  end

  describe "GET /legislators dual-scope score keys" do
    it "ships user_legislator_score AND lifetime_score on every list row" do
      sway_locale, _user = setup
      legislator = sway_locale.legislators.first
      expect(legislator).to_not be_nil

      get "/legislators"

      expect(inertia).to have_props { |p|
        row = p[:legislators]&.first
        row.is_a?(Hash) && row.key?(:user_legislator_score) && row.key?(:lifetime_score)
      }
    end
  end

  describe "GET /legislators poll of only: [legislators]" do
    it "leaves waiting_for_new_term uncomputed, so no roster-membership query runs" do
      sway_locale, _user = setup
      legislator = sway_locale.legislators.first #: Legislator
      legislator.legislator_terms.update_all(term_start_year: 2019, term_end_year: 2021)

      get "/legislators"
      expect(inertia.props[:waiting_for_new_term]).to be(true)

      statements = []
      subscriber =
        ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          statements << payload[:sql].to_s
        end
      begin
        inertia_versioned_reload_only("legislators")
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(response).to have_http_status(:ok)
      expect(inertia.props.keys).to include("legislators")
      expect(inertia.props.keys).not_to include("waiting_for_new_term")

      membership_probes = statements.select { |sql|
        sql.include?("SELECT 1 AS one") && sql.include?('INNER JOIN "legislators"')
      }
      expect(membership_probes).to be_empty
    end

    it "still resolves both props on the mobile JSON body" do
      sway_locale, _user = setup
      legislator = sway_locale.legislators.first #: Legislator
      legislator.legislator_terms.update_all(term_start_year: 2019, term_end_year: 2021)

      get "/legislators", params: {search: "smith"}, headers: {"Accept" => "application/json"}

      expect(response.parsed_body["waiting_for_new_term"]).to be(true)
      expect(response.parsed_body["filters"]).to eq({"search" => "smith"})
    end

    # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
    it "resolves filters on mobile JSON with canonical legislators_search and precedence" do
      sway_locale, _user = setup
      legislator = sway_locale.legislators.first #: Legislator
      legislator.legislator_terms.update_all(term_start_year: 2019, term_end_year: 2021)

      get "/legislators", params: {legislators_search: "smith"}, headers: {"Accept" => "application/json"}
      expect(response.parsed_body["filters"]).to eq({"search" => "smith"})

      get "/legislators", params: {legislators_search: "smith", search: "jones"}, headers: {"Accept" => "application/json"}
      expect(response.parsed_body["filters"]).to eq({"search" => "smith"})
    end
  end

  describe "GET /legislators history lazy prop (first InertiaRails.optional usage)" do
    it "omits history on a full load and serves it on a partial reload of only: [history]" do
      _sway_locale, _user = setup

      get "/legislators"
      expect(inertia).to render_component Pages::LEGISLATORS
      expect(inertia.props.keys).not_to include("history")

      inertia_versioned_reload_only("history")
      expect(response).to have_http_status(:ok)
      expect(inertia.props.keys).to include("history")
      expect(inertia.props[:history]).to include("sessions" => [])
    end

    # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
    it "ships history eagerly when the request declares canonical ?legislators_tab=history" do
      _sway_locale, _user = setup

      get "/legislators", params: {legislators_tab: "history"}

      expect(inertia).to render_component Pages::LEGISLATORS
      expect(inertia.props.keys).to include("history")
      expect(inertia.props[:history]).to include("sessions" => [])
    end

    # Switching locale from the History tab is an ordinary Inertia visit, and
    # those leave optional props out. The client keeps ?tab=history in the URL,
    # so the server has to send history up front — otherwise the History tab
    # comes back with nothing in it.
    # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
    it "still ships history eagerly when the request declares legacy ?tab=history" do
      _sway_locale, _user = setup

      get "/legislators", params: {tab: "history"}

      expect(inertia).to render_component Pages::LEGISLATORS
      expect(inertia.props.keys).to include("history")
      expect(inertia.props[:history]).to include("sessions" => [])
    end

    # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
    it "gives precedence to canonical ?legislators_tab= over legacy ?tab= when both are provided" do
      _sway_locale, _user = setup

      get "/legislators", params: {legislators_tab: "current", tab: "history"}
      expect(inertia).to render_component Pages::LEGISLATORS
      expect(inertia.props.keys).not_to include("history")

      get "/legislators", params: {legislators_tab: "history", tab: "current"}
      expect(inertia).to render_component Pages::LEGISLATORS
      expect(inertia.props.keys).to include("history")
      expect(inertia.props[:history]).to include("sessions" => [])
    end
  end

  # With Baltimore selected, History was showing a deactivated US-Congress
  # link. History has to respect the SAME locale as json_legislators: every tab
  # on the page reads through whichever locale is active.
  describe "GET /legislators history locale scoping" do
    it "excludes another locale's deactivated links and includes them under that locale" do
      sway_locale, user = setup

      congress = create(:sway_locale, city: "congress", state: "congress", country: "united_states")
      congress_district = create(:district, sway_locale: congress, name: "MD0")
      former_senator = create(:legislator, district: congress_district)
      create(:legislator_term, legislator: former_senator, district: congress_district,
        term_start_year: 2017, term_end_year: 2023, title: "Sen.")
      create(:user_legislator, user:, legislator: former_senator, active: false)

      # Active locale is the home locale from setup, so the congress entry must NOT appear.
      get "/legislators", params: {sway_locale_id: sway_locale.id}, headers: {"Accept" => "application/json"}
      expect(response.parsed_body["history"]).to eq({"sessions" => [], "legislative_sessions" => []})

      # Active locale is congress, so the same link does appear.
      get "/legislators", params: {sway_locale_id: congress.id}, headers: {"Accept" => "application/json"}
      sessions = response.parsed_body["history"]["sessions"]
      expect(sessions.length).to eq(1)
      expect(sessions.first["entries"].first["legislator"]["last_name"]).to eq(former_senator.last_name)
    end
  end

  describe "POST /user_legislators" do
    context "when signed in" do
      it "runs SwayRegistrationService and redirects to legislators" do
        sway_locale, user = setup
        expect(user).to_not be_nil
        address = create(:address, city: sway_locale.city, region_code: sway_locale.region_code, country: sway_locale.country)
        create(:user_address, user:, address:)

        allow_any_instance_of(SwayRegistrationService).to receive(
          :call
        ).and_return(true)

        post "/user_legislators"

        expect(response).to redirect_to(legislators_path)
        expect(flash[:notice]).to include(
          "Your representatives have been added"
        )
      end
    end

    context "when not signed in" do
      it "rejects unauthenticated requests" do
        post "/user_legislators"

        expect(response).to have_http_status(:unauthorized).or have_http_status(
               :redirect
             )
      end
    end
  end

  # @lat: [[voter-privacy-threshold#No endpoint sends a count that could identify a voter]]
  describe "legislator agreement counters" do
    counter_keys = %w[count_agreed count_disagreed count_no_legislator_vote count_legislator_abstained]
    percent_keys = %w[agreed_percent disagreed_percent no_legislator_vote_percent legislator_abstained_percent]

    let(:sway_locale_and_user) { setup }
    let(:sway_locale) { sway_locale_and_user.first }
    let(:user) { sway_locale_and_user.last }
    let(:legislator) { sway_locale.legislators.first }
    let(:term) { legislator.active_term }
    let(:json_headers) { {"Accept" => "application/json"} }

    before do
      create(:legislator_district_score, legislator_term: term, count_agreed: 6, count_disagreed: 3, distinct_voter_count: 9)
      create(:legislator_locale_score, legislator_term: term, count_agreed: 9, count_disagreed: 3, distinct_voter_count: 10)
      create(:user_legislator_term_score, user_legislator: user.user_legislators.find_by(legislator:),
        legislator_term: term, count_agreed: 2, count_disagreed: 1)
    end

    def expect_no_counters(district_score, locale_score, counter_keys, percent_keys)
      expect(district_score.keys & counter_keys).to be_empty
      expect(locale_score.keys & counter_keys).to be_empty
      expect(district_score["comparison_suppressed"]).to be(true)
      expect(district_score.values_at(*percent_keys)).to all(be_nil)
      expect(locale_score["comparison_suppressed"]).to be(false)
      expect(locale_score.values_at(*percent_keys)).to eq([75, 25, 0, 0])
    end

    it "GET /legislators/:id sends no raw counter on a district or locale score and keeps the user's own" do
      get "/legislators/#{legislator.id}", headers: json_headers

      payload = response.parsed_body["legislator"]
      term_entry = payload["terms"].find { |entry| entry["id"] == term.id }
      expect_no_counters(term_entry["district_score"], term_entry["locale_score"], counter_keys, percent_keys)
      expect(term_entry["user_score"]).to eq(
        "count_agreed" => 2, "count_disagreed" => 1, "count_no_legislator_vote" => 0, "count_legislator_abstained" => 0
      )
      %w[user_legislator_score lifetime_score].each do |scope|
        expect_no_counters(
          payload[scope]["legislator_district_score"], payload[scope]["legislator_locale_score"], counter_keys, percent_keys
        )
        expect(payload[scope]["count_agreed"]).to eq(2)
      end
    end

    it "GET /legislators sends no raw counter on a district or locale score" do
      get "/legislators", headers: json_headers

      row = response.parsed_body["legislators"].find { |entry| entry["id"] == legislator.id }
      term_entry = row["terms"].find { |entry| entry["id"] == term.id }
      expect_no_counters(term_entry["district_score"], term_entry["locale_score"], counter_keys, percent_keys)
      %w[user_legislator_score lifetime_score].each do |scope|
        expect_no_counters(
          row[scope]["legislator_district_score"], row[scope]["legislator_locale_score"], counter_keys, percent_keys
        )
        expect(row[scope]["count_agreed"]).to eq(2)
      end
    end

    it "GET /api/legislator_votes sends no raw counter on a district or locale score" do
      api_token = SecureRandom.hex(32)
      ApiKey.create!(bearer: user, token: api_token)

      get "/api/legislator_votes", headers: {"Authorization" => "Bearer #{api_token}"}

      expect(response).to have_http_status(:ok), response.body.to_s.first(300)
      row = response.parsed_body.find { |entry| entry["id"] == legislator.id }
      term_entry = row["terms"].find { |entry| entry["id"] == term.id }
      expect_no_counters(term_entry["district_score"], term_entry["locale_score"], counter_keys, percent_keys)
    end
  end

  # @lat: [[voter-privacy-threshold#Legislator scores count only bills that reached the minimum]]
  describe "a district score over a bill whose district split is withheld" do
    it "GET /legislators/:id hides the score while one voter sits outside the only district with ten" do
      sway_locale, _user = setup
      district_four = create(:district, sway_locale:, name: "#{sway_locale.region_code}4")
      district_five = create(:district, sway_locale:, name: "#{sway_locale.region_code}5")
      member = create(:legislator, district: district_four)
      term = create(:legislator_term, legislator: member, district: district_four)
      neighbour = create(:legislator, district: district_five)
      create(:legislator_term, legislator: neighbour, district: district_five)
      bill = create(:bill, sway_locale:, legislator: member)
      create(:legislator_vote, bill:, legislator: member, support: LegislatorVote::Support::FOR)
      votes = [[member, "FOR"]] * 7 + [[member, "AGAINST"]] * 3 + [[neighbour, "FOR"]]
      votes.each do |legislator, support|
        voter = create(:user)
        create(:user_legislator, user: voter, legislator:)
        create(:user_vote, user: voter, bill:, support:)
      end
      ScoreRecomputeService.recompute_bill!(bill)
      ScoreRecomputeService.recompute_legislator!(term)

      expect(BillScore.find_by!(bill:).publishable_districts).to eq([])

      get "/legislators/#{member.id}", headers: {"Accept" => "application/json"}

      term_entry = response.parsed_body["legislator"]["terms"].find { |entry| entry["id"] == term.id }
      expect(term_entry["district_score"]).to include(
        "comparison_suppressed" => true, "agreed_percent" => nil, "disagreed_percent" => nil
      )
      expect(term_entry["locale_score"]).to include("comparison_suppressed" => false)
    end
  end
end
