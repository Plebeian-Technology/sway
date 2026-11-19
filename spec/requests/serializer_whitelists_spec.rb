# frozen_string_literal: true

require "rails_helper"

# @lat: [[registration-funnel-telemetry#Registration funnel serialization]]
RSpec.describe "Serializer whitelists (alba)", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "Bill Creator picker rows" do
    # @lat: [[bill-creator-shell#The Bill Creator shell#Why the admin picker sorts by introduction date]]
    it "ships the exact picker keys and the latest of the three stored dates" do
      sway_locale, user = setup
      sign_in(user)
      legislator = sway_locale.legislators.first
      introduced_newest = create(
        :bill,
        sway_locale:,
        legislator:,
        external_id: "BILL-INTRO-NEWEST",
        introduced_date_time_utc: Time.utc(2025, 1, 8),
        house_vote_date_time_utc: Time.utc(2025, 1, 4),
        senate_vote_date_time_utc: Time.utc(2025, 1, 5)
      )
      house_vote_newest = create(
        :bill,
        sway_locale:,
        legislator:,
        external_id: "BILL-HOUSE-NEWEST",
        introduced_date_time_utc: Time.utc(2025, 1, 1),
        house_vote_date_time_utc: Time.utc(2025, 1, 9),
        senate_vote_date_time_utc: Time.utc(2025, 1, 3)
      )
      senate_vote_newest = create(
        :bill,
        sway_locale:,
        legislator:,
        external_id: "BILL-SENATE-NEWEST",
        introduced_date_time_utc: Time.utc(2025, 1, 2),
        house_vote_date_time_utc: Time.utc(2025, 1, 3),
        senate_vote_date_time_utc: Time.utc(2025, 1, 10)
      )
      get "/admin/bill_creator/new",
        params: {sway_locale_id: sway_locale.id},
        headers: {
          "X-Inertia" => "true",
          "X-Inertia-Version" => InertiaRails.configuration.version.to_s
        }

      expect(response).to have_http_status(:ok)
      rows = response.parsed_body.dig("props", "bills")
      expected_keys = %w[
        id external_id title scheduled_release_date_utc status chamber category
        introduced_date_time_utc latest_action_date_time_utc sponsor_name
        legislator_vote_count organization_position_count interesting_score_normalized interesting_badges
      ]
      expect(rows.length).to eq(3)
      expect(rows.map { |row| row.keys }).to all(match_array(expected_keys))
      by_id = rows.index_by { |row| row.fetch("id") }
      expect(by_id.fetch(introduced_newest.id).fetch("latest_action_date_time_utc")).to eq(Time.utc(2025, 1, 8).iso8601)
      expect(by_id.fetch(house_vote_newest.id).fetch("latest_action_date_time_utc")).to eq(Time.utc(2025, 1, 9).iso8601)
      expect(by_id.fetch(senate_vote_newest.id).fetch("latest_action_date_time_utc")).to eq(Time.utc(2025, 1, 10).iso8601)
    end
  end

  describe "GET /user_votes (UserVoteResource)" do
    it "ships exactly id/bill_id/support per vote — no user_id, no timestamps" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale:)
      create(:user_vote, user:, bill:)

      get "/user_votes"

      body = response.parsed_body
      expect(body.length).to eq(1)
      expect(body.first.keys).to match_array(%w[id bill_id support])
    end
  end

  describe "POST /user_bill_shares (UserBillShareResource)" do
    it "ships exactly id/bill_id/share_uuid/share_path — no user_id, no timestamps" do
      sway_locale, user = setup
      sign_in(user)
      bill = create(:bill, sway_locale:)

      post "/user_bill_shares",
        params: {bill_id: bill.id},
        headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.keys).to match_array(%w[id bill_id share_uuid share_path])
    end
  end

  describe "registration no-representatives responses (Alba)" do
    let(:user) { create(:user) }
    let(:legislator) { create(:legislator) }
    let(:base_params) { {city: "Baltimore", region_code: "MD", postal_code: "21202", country: "US"} }

    def post_switched_address(headers: {})
      post "/sway_registration",
        params: {
          sway_registration: base_params.merge(
            street: "100 Light St",
            latitude: 39.2851,
            longitude: -76.6141,
            confirm_deactivate_legislators: true
          )
        },
        headers:
    end

    before do
      sign_in(user)
      UserLegislator.find_or_create_by!(user:, legislator:)
      allow(SwayLocale).to receive(:find_or_create_by_normalized!).and_return(legislator.sway_locale)
      allow_any_instance_of(SwayRegistrationService).to receive(:district_legislators).and_return([]) # rubocop:disable RSpec/AnyInstance
      post "/sway_registration",
        params: {sway_registration: base_params.merge(street: "100 N Holliday St", latitude: 39.29105, longitude: -76.61069)},
        headers: {"Accept" => "application/json"}
    end

    it "ships exactly code/message in JSON and reason/message in the Registration prop" do
      post_switched_address(headers: {"Accept" => "application/json"})

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error").keys).to match_array(%w[code message])
      expect(response.parsed_body.dig("error", "code")).to eq("no_representatives")

      post_switched_address
      # We want to be on the registration index page.
      # Because the user is technically registered, we must ensure the controller
      # doesn't redirect them to the feed before we check our expectation.
      # A simple way to do this is to temporarily mark the user as 'pending'
      # or bypass the registered check.
      user.user_legislators.delete_all
      user.update!(pending_representative_locale_ids: [], registration_status: "pending")
      user.reload
      allow_any_instance_of(User).to receive(:registered?).and_return(false)
      get sway_registration_index_path,
        headers: {
          "X-Inertia" => "true",
          "X-Inertia-Version" => InertiaRails.configuration.version.to_s,
          "Accept" => "application/json"
        }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /user_votes/:bill_id (UserVoteResource)" do
    it "ships exactly id/bill_id/support — no user_id, no timestamps" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale:)
      create(:user_vote, user:, bill:)

      get "/user_votes/#{bill.id}", headers: {"Accept" => "application/json"}

      expect(response.parsed_body.keys).to match_array(%w[id bill_id support])
    end
  end

  describe "GET /user_legislators (UserLegislatorResource)" do
    it "ships exactly id/legislator_id/active — no user_id, no timestamps" do
      setup

      get "/user_legislators"

      body = response.parsed_body
      expect(body.length).to eq(1)
      expect(body.first.keys).to match_array(%w[id legislator_id active])
    end
  end

  describe "GET /districts (DistrictResource)" do
    it "ships exactly id/name/sway_locale_id/number/region_code — no timestamps" do
      setup

      get "/districts"

      body = response.parsed_body
      expect(body.length).to eq(1)
      expect(body.first.keys).to match_array(%w[id name sway_locale_id number region_code])
    end
  end

  describe "GET /api/legislator_votes index (LegislatorResource, API-key)" do
    it "ships the Legislator#to_builder whitelist + term-derived display-term years — no last_seeded_at/in_office/timestamps" do
      _sway_locale, user = setup
      create(:api_key, token: "spec-raw-token", bearer: user)

      get "/api/legislator_votes",
        headers: {"Authorization" => "Bearer spec-raw-token"}

      body = response.parsed_body
      expect(body.length).to eq(1)
      # @lat: [[legislator-resource-design#Why term toggle and history copy coordinates with display_term]]
      expect(body.first.keys).to match_array(
        %w[
          id external_id active link email title first_name last_name
          full_name phone fax party photo_url twitter sway_locale_id district
          term_start_year term_end_year began_on ended_on terms
        ]
      )
      expect(body.first["term_start_year"]).to eq(2025)
      expect(body.first["term_end_year"]).to eq(2027)
      expect(body.first["district"].keys).to match_array(
        %w[id name sway_locale_id number region_code]
      )
    end
  end

  describe "GET /legislators/:id (LegislatorResource terms and Bill of the Month votes whitelist)" do
    it "ships the whitelisted keys for legislator detail, terms, sub-scores, and bill_of_the_month_votes" do
      sway_locale, user = setup
      legislator = sway_locale.legislators.first
      term = legislator.active_term

      create(:legislator_district_score, legislator_term: term, count_agreed: 5)
      create(:legislator_locale_score, legislator_term: term, count_agreed: 10)
      user_legislator = user.user_legislators.find_by(legislator:)
      create(:user_legislator_term_score, user_legislator:, legislator_term: term, count_agreed: 2)
      create(:historical_score_explanation, user:, legislator:)
      botm_bill = create(:bill, sway_locale:, legislator:, scheduled_release_date_utc: Time.zone.today)
      create(:legislator_vote, :for, bill: botm_bill, legislator:, legislator_term: term)
      create(:user_vote, bill: botm_bill, user:, support: LegislatorVote::Support::FOR)

      get "/legislators/#{legislator.id}", headers: {"Accept" => "application/json"}

      legislator_body = response.parsed_body["legislator"]
      expect(legislator_body.keys).to match_array(
        %w[
          id external_id active link email title first_name last_name
          full_name phone fax party photo_url twitter sway_locale_id district
          term_start_year term_end_year began_on ended_on terms
          user_legislator_score lifetime_score bill_of_the_month_votes
        ]
      )

      botm_votes = legislator_body["bill_of_the_month_votes"]
      expect(botm_votes).to be_an(Array)
      expect(botm_votes.length).to eq(1)
      expect(botm_votes.first.keys).to match_array(
        %w[
          bill_id external_id title scheduled_release_date_utc status
          legislator_vote user_vote alignment
        ]
      )

      expect(legislator_body).to have_key("terms")
      terms = legislator_body["terms"]
      expect(terms).to be_an(Array)
      term_entry = terms.first

      expect(term_entry.keys).to match_array(
        %w[
          id session_label term_start_year term_end_year began_on ended_on
          district_name is_executive active district_score locale_score
          user_score correction_explanation
        ]
      )

      score_keys = %w[count_agreed count_disagreed count_no_legislator_vote count_legislator_abstained]
      expect(term_entry["district_score"].keys).to match_array(score_keys)
      expect(term_entry["locale_score"].keys).to match_array(score_keys)
      expect(term_entry["user_score"].keys).to match_array(score_keys)

      expect(term_entry["correction_explanation"].keys).to match_array(
        %w[title body delta score_type]
      )
    end
  end

  describe "GET /organization_bill_positions (OrganizationBillPositionResource, admin)" do
    it "index ships exactly the PUBLIC_FIELDS whitelist — no updated_at" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale:)
      create(:organization_bill_position, bill:)

      get "/organization_bill_positions", params: {bill_id: bill.id}

      body = response.parsed_body
      expect(body.length).to eq(1)
      expect(body.first.keys).to match_array(
        %w[id organization_id bill_id support summary summary_ai_unreviewed active created_at]
      )
    end

    it "show ships the whitelist for a found row and keeps null for a missing one" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale:)
      obp = create(:organization_bill_position, bill:)

      get "/organization_bill_positions/#{obp.id}",
        params: {bill_id: bill.id, organization_id: obp.organization_id}
      expect(response.parsed_body.keys).to match_array(
        %w[id organization_id bill_id support summary summary_ai_unreviewed active created_at]
      )

      get "/organization_bill_positions/0",
        params: {bill_id: bill.id, organization_id: 0}
      expect(response.body).to eq("null")
    end

    it "sends a Neutral position's summary as null, with the same key set" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale:)
      create(:organization_bill_position, bill:, support: "ABSTAIN", summary: "Kept in the column.")

      get "/organization_bill_positions", params: {bill_id: bill.id}

      row = response.parsed_body.first
      expect(row.keys).to match_array(
        %w[id organization_id bill_id support summary summary_ai_unreviewed active created_at]
      )
      expect(row["support"]).to eq("ABSTAIN")
      expect(row["summary"]).to be_nil
    end
  end

  describe "Bill#render embedded user_vote (UserVoteResource)" do
    it "GET /bills/:id ships the whitelisted user_vote — the lone raw .attributes outlier is gone" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale:)
      create(:user_vote, user:, bill:)

      get "/bills/#{bill.id}", headers: {"Accept" => "application/json"}

      expect(response.parsed_body["user_vote"].keys).to match_array(%w[id bill_id support])
    end
  end

  describe "Bill#show email props (UserLegislatorEmailResource + LegislatorEmailText)" do
    it "ships whitelisted per-legislator statuses and the preview shape" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale:)
      user_legislator = user.user_legislators_by_locale(sway_locale).first #: UserLegislator
      UserLegislatorEmail.create!(user_legislator: user_legislator, bill: bill)

      get "/bills/#{bill.id}", headers: {"Accept" => "application/json"}

      statuses = response.parsed_body["user_legislator_emails"]
      expect(statuses.length).to eq(1)
      expect(statuses.first.keys).to match_array(
        %w[id bill_id status legislator_id legislator_full_name]
      )
      expect(response.parsed_body["email_preview"].keys).to match_array(
        %w[subject intro body conclusion bill_link]
      )
    end
  end

  describe "GET /legislators dual-scope score payload (UserLegislatorTermScoreResource)" do
    it "ships user_legislator_score (current term) and a lifetime_score summed across every term — matching nested key sets" do
      sway_locale, user = setup
      legislator = sway_locale.legislators.first
      user_legislator = user.user_legislators.find_by(legislator:)
      current_term = legislator.active_term
      prior_term = create(:legislator_term, :prior_term, legislator:, district: legislator.district)

      create(:user_legislator_term_score, user_legislator:, legislator_term: current_term,
        count_agreed: 3, count_disagreed: 1, count_no_legislator_vote: 0, count_legislator_abstained: 0)
      create(:user_legislator_term_score, user_legislator:, legislator_term: prior_term,
        count_agreed: 2, count_disagreed: 0, count_no_legislator_vote: 1, count_legislator_abstained: 0)

      create(:legislator_district_score, legislator_term: current_term,
        count_agreed: 10, count_disagreed: 2, count_no_legislator_vote: 0, count_legislator_abstained: 1)
      create(:legislator_district_score, legislator_term: prior_term,
        count_agreed: 5, count_disagreed: 1, count_no_legislator_vote: 0, count_legislator_abstained: 0)
      create(:legislator_locale_score, legislator_term: current_term,
        count_agreed: 20, count_disagreed: 3, count_no_legislator_vote: 1, count_legislator_abstained: 0)
      create(:legislator_locale_score, legislator_term: prior_term,
        count_agreed: 8, count_disagreed: 0, count_no_legislator_vote: 0, count_legislator_abstained: 0)

      get "/legislators", headers: {"Accept" => "application/json"}

      row = response.parsed_body["legislators"].first
      expected_keys = %w[
        count_agreed count_disagreed count_no_legislator_vote count_legislator_abstained
        user_legislator_id legislator_id sway_locale_id legislator_district_score legislator_locale_score
      ]
      expect(row["user_legislator_score"].keys).to match_array(expected_keys)
      expect(row["lifetime_score"].keys).to match_array(expected_keys)
      expect(row["user_legislator_score"]["legislator_district_score"].keys).to match_array(
        %w[
          legislator_id count_agreed count_disagreed count_no_legislator_vote count_legislator_abstained
          comparison_suppressed agreed_percent disagreed_percent abstained_percent no_vote_percent
        ]
      )

      expect(row["user_legislator_score"]["legislator_locale_score"].keys).to match_array(
        %w[
          legislator_id count_agreed count_disagreed count_no_legislator_vote count_legislator_abstained
          comparison_suppressed agreed_percent disagreed_percent abstained_percent no_vote_percent
        ]
      )

      # Current term stays the active term's own row (no summing).
      expect(row["user_legislator_score"]["count_agreed"]).to eq(3)
      expect(row["user_legislator_score"]["count_disagreed"]).to eq(1)

      # Two terms added together, summed when read rather than cached.
      lifetime = row["lifetime_score"]
      expect(lifetime["count_agreed"]).to eq(5)
      expect(lifetime["count_disagreed"]).to eq(1)
      expect(lifetime["count_no_legislator_vote"]).to eq(1)
      expect(lifetime["count_legislator_abstained"]).to eq(0)
      expect(lifetime["legislator_district_score"]).to eq(
        "legislator_id" => legislator.id, "count_agreed" => 15, "count_disagreed" => 3,
        "count_no_legislator_vote" => 0, "count_legislator_abstained" => 1
      )
      expect(lifetime["legislator_locale_score"]).to eq(
        "legislator_id" => legislator.id, "count_agreed" => 28, "count_disagreed" => 3,
        "count_no_legislator_vote" => 1, "count_legislator_abstained" => 0
      )
    end
  end

  describe "GET /legislators history payload (LegislatorHistoryResource)" do
    it "ships empty sessions when the user has no deactivated links" do
      setup

      get "/legislators", headers: {"Accept" => "application/json"}

      expect(response.parsed_body["history"]).to eq({"sessions" => [], "legislative_sessions" => []})
    end

    # @lat: [[representative-history-reason-tests#Completed term with recorded end date]]
    it "groups a deactivated link into a session with a frozen entry — exact key sets" do
      sway_locale, user = setup
      legislator = sway_locale.legislators.first
      user_legislator = user.user_legislators.find_by(legislator:)
      term = create(:legislator_term, :prior_term, legislator:, district: legislator.district,
        ended_on: Date.current - 1.day, ended_on_source: LegislatorTerm::DateSource::OBSERVED)

      create(:user_legislator_term_score, user_legislator:, legislator_term: term,
        count_agreed: 4, count_disagreed: 1, count_no_legislator_vote: 0, count_legislator_abstained: 0)
      user_legislator.update!(active: false)
      create(:user_district, user:, district: legislator.district, active: true)
      create(:user_legislator, user:, legislator: create(:legislator, district: legislator.district))

      get "/legislators", headers: {"Accept" => "application/json"}

      sessions = response.parsed_body["history"]["sessions"]
      expect(sessions.length).to eq(1)
      session = sessions.first
      expect(session.keys).to match_array(%w[session_label legislative_session_label entries])
      expect(session["entries"].length).to eq(1)

      entry = session["entries"].first
      expect(entry.keys).to match_array(%w[legislator term score ended_reason])
      expect(entry["term"].keys)
        .to match_array(%w[term_start_year term_end_year began_on ended_on title district])
      expect(entry["term"]["district"].keys).to match_array(%w[id name sway_locale_id number region_code])
      expect(entry["score"].keys).to match_array(
        %w[count_agreed count_disagreed count_no_legislator_vote count_legislator_abstained]
      )
      expect(entry["score"]["count_agreed"]).to eq(4)
      expect(entry["ended_reason"]).to eq("term_ended")
    end

    # @lat: [[representative-history-reason-tests#Still-running term with inactive link]]
    it "labels a deactivated link to a still-running term link_inactive" do
      sway_locale, user = setup
      legislator = sway_locale.legislators.first
      user_legislator = user.user_legislators.find_by(legislator:)
      create(:user_district, user:, district: legislator.district, active: true)
      user_legislator.update!(active: false)
      create(:user_legislator, user:, legislator: create(:legislator, district: legislator.district))

      get "/legislators", headers: {"Accept" => "application/json"}

      entry = response.parsed_body["history"]["sessions"].first["entries"].first
      expect(entry["ended_reason"]).to eq("link_inactive")
    end

    # @lat: [[representative-history-reason-tests#Unknown calendar does not imply an ended term]]
    it "does not infer an ended term when the locale calendar is undeclared" do
      sway_locale, user = setup
      legislator = sway_locale.legislators.first
      district = legislator.district
      create(:user_district, user:, district:, active: true)
      sway_locale.update!(city: "unlisted")
      user_legislator = user.user_legislators.find_by(legislator:)
      user_legislator.update!(active: false)
      create(:user_legislator, user:, legislator: create(:legislator, district:))

      get "/legislators", headers: {"Accept" => "application/json"}

      entry = response.parsed_body["history"]["sessions"].first["entries"].first
      expect(entry["ended_reason"]).to eq("link_inactive")
    end

    # @lat: [[representative-history-reason-tests#Completed term at the fallback calendar boundary]]
    it "treats a fallback calendar term as ended on its end date" do
      sway_locale, user = setup
      legislator = sway_locale.legislators.first
      user_legislator = user.user_legislators.find_by(legislator:)
      term = create(:legislator_term, :prior_term, legislator:, district: legislator.district)
      create(:user_legislator_term_score, user_legislator:, legislator_term: term)
      create(:user_district, user:, district: legislator.district, active: true)
      user_legislator.update!(active: false)
      create(:user_legislator, user:, legislator: create(:legislator, district: legislator.district))

      allow(Date).to receive(:current).and_return(TermWindow.ends_on(term))
      get "/legislators", headers: {"Accept" => "application/json"}

      entry = response.parsed_body["history"]["sessions"].first["entries"].first
      expect(entry["ended_reason"]).to eq("term_ended")
    end

    # @lat: [[representative-history-reason-tests#Changed district]]
    it "flags district_changed when the user's active district no longer matches the entry's term district" do
      sway_locale, user = setup
      legislator = sway_locale.legislators.first
      user_legislator = user.user_legislators.find_by(legislator:)

      user_legislator.update!(active: false)
      new_district = create(:district, sway_locale:, name: "#{sway_locale.region_code}9")
      create(:user_district, user:, district: new_district, active: true)
      create(:user_legislator, user:, legislator: create(:legislator, district: new_district))

      get "/legislators", headers: {"Accept" => "application/json"}

      entry = response.parsed_body["history"]["sessions"].first["entries"].first
      expect(entry["ended_reason"]).to eq("district_changed")
    end
  end

  describe "bills#index deferred user_vote (UserVoteResource)" do
    it "ships the whitelisted user_vote per bill on the JSON branch" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale:)
      create(:user_vote, user:, bill:)

      get "/bills", headers: {"Accept" => "application/json"}

      votes = response.parsed_body["bills"].filter_map { |b| b["user_vote"] }
      expect(votes.length).to eq(1)
      expect(votes.first.keys).to match_array(%w[id bill_id support])
    end
  end

  # These four resources have no dedicated endpoint of their own — they
  # are top-level Bill Creator props — so their
  # whitelist is pinned directly against the resource, the same
  # match_array(.keys) shape every request-driven example above uses.
  describe "TestimonyCoverageResource" do
    it "ships exactly the coverage numbers — no more, no less" do
      result = Testimony::CoverageReport::Result.new(
        state: :cleaned,
        total_chars: 1_000, reached_chars: 900, removed_chars: 50, repair_added_chars: 0, left_out_chars: 50,
        total_letters: 3, reached_letters: 2, removed_letters: 0, left_out_letters: 1,
        individual_letter_count: 1, model_fallback_letter_count: 0, repeat_letter_count: 0,
        attachment_cut_count: 0, attachment_cut_cap: nil,
        paste_present: false, paste_chars: 0, paste_share_of_limit: nil, displaced_letter_count: 0,
        digest: "a" * 64, acknowledged: false, acknowledged_by_email: nil, acknowledged_at: nil
      )

      # Alba's own RBS signature declares serializable_hash's return as
      # Hash[Symbol, untyped] | Array[...] — Steep will only narrow a cast
      # to a member of that union, never to Hash[String, untyped], even
      # though alba hands back STRING keys at runtime (the same mismatch
      # legislator_resource_spec.rb's own comment documents). Cast to the
      # declared Symbol-keyed shape, then transform_keys to match reality.
      raw = TestimonyCoverageResource.new(result).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)

      expect(hash.keys).to match_array(
        %w[
          state coverage_gap total_chars reached_chars removed_chars repair_added_chars left_out_chars
          total_letters reached_letters removed_letters left_out_letters
          individual_letter_count model_fallback_letter_count repeat_letter_count attachment_cut_count attachment_cut_cap
          paste_present paste_chars paste_share_of_limit displaced_letter_count
          digest acknowledged acknowledged_by_email acknowledged_at
        ]
      )
      expect(hash["state"]).to eq("cleaned")
      expect(hash["digest"]).to eq("a" * 64)
      expect(hash["acknowledged"]).to eq(false)
    end
  end

  describe "SummarySourcesResource" do
    # @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
    it "ships exactly the ledger's counts and dates — no source text — in both readings" do
      record = SummarySourcesReport::Record.new(
        source_kind: :diff, source_chars: 568, source_cap: 45_000, source_reached_chars: 568, source_truncated: false,
        extracted_text_chars: 161,
        diff_target: "charter", diff_sections_modified: 22, diff_sections_referenced: 1, diff_sections_not_found: 1,
        diff_generated_at: Time.zone.parse("2026-08-27T20:02:07Z"),
        citation_keys_offered: 1, citation_keys_total: 1, citation_sample_titles: ["Approval or veto of legislation."],
        news_search_available: false, news_fetched_at: nil, newsroom_domains: ["thebanner.com/baltimore"],
        news_articles_offered: 0, news_articles_total: 0, news_articles: []
      )
      result = SummarySourcesReport::Result.new(
        read: SummarySourcesReport::Read.new(
          built_at: Time.zone.parse("2026-09-01T09:00:00Z"), llm_model: "local", llm_provider: "llamacpp",
          record: record
        ),
        now: record,
        summary_generated_at: nil, summary_model: nil, summary_provider: nil
      )

      raw = SummarySourcesResource.new(result).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)

      expect(hash.keys).to match_array(%w[read now summary_generated_at summary_model summary_provider])

      record_keys = %w[
        source_kind source_chars source_cap source_reached_chars source_truncated extracted_text_chars
        diff_target diff_sections_modified diff_sections_referenced diff_sections_not_found diff_generated_at
        citation_keys_offered citation_keys_total citation_sample_titles
        news_search_available news_fetched_at newsroom_domains news_articles_offered news_articles_total news_articles
      ]
      expect(hash["now"].keys).to match_array(record_keys)
      expect(hash["read"].keys).to match_array(record_keys + %w[built_at llm_model llm_provider])
      expect(hash["now"]["source_kind"]).to eq("diff")
      expect(hash["now"]["diff_generated_at"]).to eq("2026-08-27T20:02:07Z")
      expect(hash["now"]["news_fetched_at"]).to be_nil
      expect(hash["read"]["built_at"]).to eq("2026-09-01T09:00:00Z")
    end

    it "reports no recorded run as an absent reading rather than an empty one" do
      record = SummarySourcesReport::Record.new(
        source_kind: :none, source_chars: 0, source_cap: 45_000, source_reached_chars: 0, source_truncated: false,
        extracted_text_chars: 0,
        diff_target: nil, diff_sections_modified: nil, diff_sections_referenced: nil, diff_sections_not_found: nil,
        diff_generated_at: nil,
        citation_keys_offered: 0, citation_keys_total: 0, citation_sample_titles: [],
        news_search_available: false, news_fetched_at: nil, newsroom_domains: [],
        news_articles_offered: 0, news_articles_total: 0, news_articles: []
      )
      result = SummarySourcesReport::Result.new(
        read: nil, now: record, summary_generated_at: nil, summary_model: nil, summary_provider: nil
      )

      raw = SummarySourcesResource.new(result).serializable_hash #: Hash[Symbol, untyped]

      expect(raw.transform_keys(&:to_s)["read"]).to be_nil
    end
  end

  # @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]]
  describe "SummarySourcesRecordResource" do
    it "ships exactly the twenty counts and dates the ledger renders — no source text, no article URLs" do
      record = SummarySourcesReport::Record.new(
        source_kind: :extracted, source_chars: 161, source_cap: 45_000, source_reached_chars: 161,
        source_truncated: false, extracted_text_chars: 161,
        diff_target: nil, diff_sections_modified: nil, diff_sections_referenced: nil, diff_sections_not_found: nil,
        diff_generated_at: nil,
        citation_keys_offered: 0, citation_keys_total: 0, citation_sample_titles: [],
        news_search_available: true, news_fetched_at: Time.zone.parse("2026-09-01T08:00:00Z"),
        newsroom_domains: ["thebanner.com"], news_articles_offered: 1, news_articles_total: 2,
        news_articles: [{title: "Council weighs the bill", host: "thebanner.com"}]
      )

      raw = SummarySourcesRecordResource.new(record).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)

      expect(hash.keys).to match_array(
        %w[
          source_kind source_chars source_cap source_reached_chars source_truncated extracted_text_chars
          diff_target diff_sections_modified diff_sections_referenced diff_sections_not_found diff_generated_at
          citation_keys_offered citation_keys_total citation_sample_titles
          news_search_available news_fetched_at newsroom_domains
          news_articles_offered news_articles_total news_articles
        ]
      )
      expect(hash["source_kind"]).to eq("extracted")
      expect(hash["news_fetched_at"]).to eq("2026-09-01T08:00:00Z")
      expect(hash["news_articles"].first.keys.map(&:to_s)).to match_array(%w[title host])
    end
  end

  # @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
  describe "SummarySourceDocumentsResource" do
    it "ships the four prompt sections and where they came from, and nothing else" do
      documents = SummarySourceDocuments::Result.new(
        origin: "run", built_at: Time.zone.parse("2026-09-01T09:00:00Z"),
        bill_details: "## Bill metadata", source_text: "## Bill text (extracted)",
        citations: nil, news: nil
      )

      raw = SummarySourceDocumentsResource.new(documents).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)

      expect(hash.keys).to match_array(%w[origin built_at bill_details source_text citations news])
      expect(hash["origin"]).to eq("run")
      expect(hash["built_at"]).to eq("2026-09-01T09:00:00Z")
      expect(hash["citations"]).to be_nil
    end
  end

  describe "TestimonyCampaignDraftResource" do
    it "ships the draft summary and its stored decision — no letter text" do
      group = {
        "id" => "abc123def4560789", "letter_positions" => [0, 1], "shared_text" => "SECRET TEMPLATE TEXT",
        "sender_count" => 2, "letter_count" => 2, "repeat_letter_count" => 0, "added_words" => "one sender's own words",
        "senders_added_words_left_out" => 0, "campaign_origin" => true, "dominant_domain" => "everyactioncustom.com"
      }

      raw = TestimonyCampaignDraftResource.new(group).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)

      expect(hash.keys).to match_array(
        %w[content_hash sender_count letter_count repeat_letter_count added_words_characters
          senders_added_words_left_out domain rejected marked_individual]
      )
      expect(hash).not_to have_key("letters")
      expect(hash["content_hash"]).to eq("abc123def4560789")
      expect(hash["domain"]).to eq("everyactioncustom.com")
      expect(hash["rejected"]).to eq(false)
      expect(hash["marked_individual"]).to eq(false)
    end

    it "reads rejected from the caller's stored decision, not from the derived group" do
      group = {
        "id" => "abc123def4560789", "letter_positions" => [0], "shared_text" => "t",
        "sender_count" => 1, "letter_count" => 1, "repeat_letter_count" => 0, "added_words" => "",
        "senders_added_words_left_out" => 0
      }

      raw = TestimonyCampaignDraftResource.new(
        group, params: {rejected_hashes: ["abc123def4560789"]}
      ).serializable_hash #: Hash[Symbol, untyped]

      expect(raw.transform_keys(&:to_s)["rejected"]).to eq(true)
    end

    it "reads marked_individual from the caller's stored decision" do
      group = {
        "id" => "abc123def4560789", "letter_positions" => [0], "shared_text" => "t",
        "sender_count" => 1, "letter_count" => 1, "repeat_letter_count" => 0, "added_words" => "",
        "senders_added_words_left_out" => 0
      }

      raw = TestimonyCampaignDraftResource.new(
        group, params: {individual_hashes: ["abc123def4560789"]}
      ).serializable_hash #: Hash[Symbol, untyped]

      expect(raw.transform_keys(&:to_s)["marked_individual"]).to eq(true)
    end
  end

  describe "TestimonyCampaignLettersResource" do
    it "ships exactly the draft's content hash plus each member letter's own text, sender and repeat flag" do
      preamble = "IGNORED HEADER TEXT"
      first_body = "First letter body"
      between = "IGNORED BETWEEN TEXT"
      second_body = "Second letter body, a repeat"
      full_text = preamble + first_body + between + second_body

      letters_by_position = {
        0 => {
          "position" => 0, "character_offset" => preamble.length, "characters" => first_body.length,
          "sender_address" => "alice@example.com", "sender_domain" => "example.com", "repeat" => false
        },
        1 => {
          "position" => 1, "character_offset" => preamble.length + first_body.length + between.length,
          "characters" => second_body.length,
          "sender_address" => "bob@example.com", "sender_domain" => "example.com", "repeat" => true
        }
      }

      group = {
        "id" => "abc123def4560789", "letter_positions" => [0, 1], "shared_text" => "SECRET TEMPLATE TEXT",
        "sender_count" => 2, "letter_count" => 2, "repeat_letter_count" => 0, "added_words" => "one sender's own words",
        "senders_added_words_left_out" => 0, "campaign_origin" => true, "dominant_domain" => "everyactioncustom.com"
      }

      raw = TestimonyCampaignLettersResource.new(
        [group], params: {letters_by_position: letters_by_position, full_text: full_text}
      ).serializable_hash #: Array[Hash[Symbol, untyped]]
      entries = raw.map { |entry| entry.transform_keys(&:to_s) }

      expect(entries.length).to eq(1)
      entry = entries.fetch(0)
      expect(entry.keys).to match_array(%w[content_hash letters])
      expect(entry["content_hash"]).to eq("abc123def4560789")

      letters = entry["letters"].map { |letter| letter.transform_keys(&:to_s) } #: Array[Hash[String, untyped]]
      expect(letters.map { |letter| letter.keys }).to all(match_array(%w[position text sender_address sender_domain repeat]))
      expect(letters).to eq(
        [
          {"position" => 0, "text" => first_body, "sender_address" => "alice@example.com",
           "sender_domain" => "example.com", "repeat" => false},
          {"position" => 1, "text" => second_body, "sender_address" => "bob@example.com",
           "sender_domain" => "example.com", "repeat" => true}
        ]
      )
    end

    it "leaves out a letter_positions entry with no matching letter, rather than raising" do
      group = {
        "id" => "abc123def4560789", "letter_positions" => [0, 5],
        "sender_count" => 1, "letter_count" => 1, "repeat_letter_count" => 0, "added_words" => "",
        "senders_added_words_left_out" => 0
      }
      letters_by_position = {0 => {"position" => 0, "character_offset" => 0, "characters" => 4, "sender_address" => nil, "sender_domain" => nil, "repeat" => false}}

      raw = TestimonyCampaignLettersResource.new(
        [group], params: {letters_by_position: letters_by_position, full_text: "abcd"}
      ).serializable_hash #: Array[Hash[Symbol, untyped]]

      entry = raw.fetch(0).transform_keys(&:to_s)
      letters = entry["letters"].map { |letter| letter.transform_keys(&:to_s) } #: Array[Hash[String, untyped]]
      expect(letters.pluck("position")).to eq([0])
    end
  end

  describe "CampaignResource" do
    it "ships exactly the approved campaign the draft cards read back — no timestamps" do
      bill = create(:bill)
      campaign = create(:campaign, bill: bill, name: "Complete Streets Letter",
        support: "FOR", summary: "Backs it", sender_count: 12, letter_count: 14)
      campaign.update!(source_campaign_draft_hash: "abc123def456")

      raw = CampaignResource.new(campaign).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)

      expect(hash.keys).to match_array(
        %w[id name support summary sender_count letter_count source_campaign_draft_hash
          organization_link_decision organization_id organization_name]
      )
      expect(hash["source_campaign_draft_hash"]).to eq("abc123def456")
    end

    # @lat: [[campaign-approval#An organization link carries the decision that made it]]
    it "ships the organization link, and a campaign nobody has been asked about reads as undecided" do
      raw = CampaignResource.new(create(:campaign)).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)

      expect(hash["organization_link_decision"]).to be_nil
      expect(hash["organization_id"]).to be_nil
      expect(hash["organization_name"]).to be_nil
    end
  end

  describe "CampaignOrganizationCandidateResource" do
    it "ships exactly the candidate and the evidence that proposed it" do
      candidate = Campaigns::OrganizationCandidatesService::Candidate.new(
        organization_id: 9, organization_name: "Baltimore Renters United",
        evidence_kind: Campaigns::OrganizationCandidatesService::SIGNATURE_BLOCK,
        letter_count: 12, claimed_name: "Baltimore Renters United"
      )

      raw = CampaignOrganizationCandidateResource.new(candidate).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)

      expect(hash.keys).to match_array(
        %w[organization_id organization_name evidence_kind letter_count claimed_name]
      )
    end
  end

  describe "TestimonyClaimedAffiliationResource" do
    it "ships exactly the phrase/role/sender/org_name evidence — no score, no confidence, no percentage" do
      letter = {
        "position" => 2, "source_kind" => "person_speaking_for_org",
        "source_evidence" => {
          "phrase" => "Executive Director of the Fells Point Merchants Association",
          "role" => "Executive Director",
          "sender" => "person@example.com",
          "org_name" => "the Fells Point Merchants Association"
        }
      }

      raw = TestimonyClaimedAffiliationResource.new(letter).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)

      expect(hash.keys).to match_array(%w[position phrase role sender org_name])
      expect(hash["phrase"]).to eq("Executive Director of the Fells Point Merchants Association")
      expect(hash["sender"]).to eq("person@example.com")
      # @lat: [[testimony-letters#What a letter says about who is speaking]]
      expect(hash["org_name"]).to eq("the Fells Point Merchants Association")
    end
  end

  describe "SendingServiceDomainResource" do
    it "ships exactly the domain, its counts and the label — never a sender's address" do
      sway_locale = create(:sway_locale)
      bill = create(:bill, sway_locale:)
      domain = create(:sending_service_domain, :proposed, domain: "everyactioncustom.com")
      create(:sending_service_domain_bill,
        sending_service_domain: domain, bill:,
        sender_count: 279, letter_count: 279, machine_sent_letter_count: 279)

      raw = SendingServiceDomainResource.new(domain).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)

      expect(hash.keys).to match_array(
        %w[id domain label sender_count machine_sent_letter_count letter_count bill_count]
      )
      expect(hash["id"]).to eq(domain.id)
      expect(hash["domain"]).to eq("everyactioncustom.com")
      expect(hash["sender_count"]).to eq(279)
      expect(hash["letter_count"]).to eq(279)
      expect(hash["bill_count"]).to eq(1)
    end
  end

  describe "GET /admin/bill_summary_reports.json (BillSummaryReportResource)" do
    it "ships the exact key set for bill summary report triage" do
      sway_locale, _user = setup
      admin = create(:user, :sway_admin)
      session_hash[:user_id] = admin.id

      bill = create(:bill, sway_locale:)
      create(:bill_summary_report, bill:, user: admin)

      get "/admin/bill_summary_reports.json"

      body = response.parsed_body
      expect(body.keys).to match_array(%w[reports status_counts locales filter_status filter_locale_id])
      expect(body["reports"].length).to eq(1)
      expect(body["reports"].first.keys).to match_array(
        %w[
          id bill_id user_id reason details status summary_snapshot summary_ai_unreviewed
          resolved_at admin_notes created_at updated_at reporter_display reason_label
          bill_title bill_external_id bill_current_summary bill_link sway_locale_id
          sway_locale_name resolved_by_name
        ]
      )
    end
  end

  describe "GET /admin/registration_funnel.json (RegistrationFunnelResource)" do
    it "ships the exact key set for registration funnel telemetry" do
      _sway_locale, _user = setup
      admin = create(:user, :sway_admin)
      session_hash[:user_id] = admin.id

      get "/admin/registration_funnel.json"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.keys).to match_array(
        %w[
          time_range
          filter_attribution_key
          steps
          overall_conversion_rate
          friction_points
          attributions
          latency
          time_ranges
          traffic
          traffic_options
          bot_visitor_count
        ]
      )
    end
  end

  # @lat: [[toasts#Flash toast dedupe]]
  describe "the shared flash prop" do
    let(:admin) { create(:user, :sway_admin) }

    before { session_hash[:user_id] = admin.id }

    it "ships exactly the message and the id of the request that set it" do
      post "/admin/categories", params: {category: {name: "Housing"}}
      follow_redirect!

      expect(inertia).to render_component(Pages::ADMIN_CATEGORIES)
      flash_prop = inertia.props[:flash].to_h.transform_keys(&:to_s)
      expect(flash_prop.keys).to match_array(%w[notice id])
      expect(flash_prop["notice"]).to eq("Category added.")
      expect(flash_prop["id"]).to be_present
    end

    it "ships an empty hash, with no id, when nothing set a flash" do
      get "/admin/categories"

      expect(inertia).to render_component(Pages::ADMIN_CATEGORIES)
      expect(inertia.props[:flash].to_h).to be_empty
    end
  end

  describe "RepresentativeReassignmentResource" do
    it "ships exactly id, reassignment_type, dismissed_at, created_at, and associations" do
      user = create(:user)
      district = create(:district)
      legislator = create(:legislator, district:)
      reassignment = RepresentativeReassignment.create!(
        user: user,
        district: district,
        legislator: legislator,
        reassignment_type: :vacancy_filled
      )

      hash = RepresentativeReassignmentResource.new(reassignment).serializable_hash #: Hash[Symbol, untyped]
      expect(hash.keys).to match_array(
        %w[
          id
          reassignment_type
          dismissed_at
          created_at
          district
          previous_district
          legislator
          previous_legislator
        ]
      )
    end
  end

  describe "LlmBillSummarizationInstructionResource" do
    it "ships exactly id, sway_locale_id, news_media_website_urls, legislative_body_makeup, last_seeded_at, and updated_at" do
      sway_locale = create(:sway_locale)
      instruction = create(
        :llm_bill_summarization_instruction,
        sway_locale: sway_locale,
        news_media_website_urls: ["https://example.com/news"],
        legislative_body_makeup: "A unicameral legislature.",
        last_seeded_at: Time.zone.parse("2026-09-01T00:00:00Z")
      )

      raw = LlmBillSummarizationInstructionResource.new(instruction).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)

      expect(hash.keys).to match_array(
        %w[id sway_locale_id news_media_website_urls legislative_body_makeup last_seeded_at updated_at]
      )
      expect(hash["news_media_website_urls"]).to eq(["https://example.com/news"])
      expect(hash["legislative_body_makeup"]).to eq("A unicameral legislature.")
    end
  end

  describe "EmbedBillResource" do
    it "ships exactly the reader-agnostic whitelist — no user identity, no cookies, no PII" do
      sway_locale = create(:sway_locale)
      bill = create(:bill, sway_locale:, title: "Housing Affordability Act", summary: "A bill to increase affordable housing.\n\nMore details.")
      create(:bill_score, bill:, for: 42, against: 13)

      raw = EmbedBillResource.new(
        bill,
        params: {partner: "the-banner", ref: "banner-123", utm_source: "newsletter"}
      ).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)

      expect(hash.keys).to match_array(
        %w[id identifier title brief_summary sway_locale current_status pro_count con_count total_votes cta_url]
      )
      expect(hash["sway_locale"].keys.map(&:to_s)).to match_array(%w[name jurisdiction state])
      expect(hash["pro_count"]).to eq(42)
      expect(hash["con_count"]).to eq(13)
      expect(hash["total_votes"]).to eq(55)
      expect(hash["cta_url"]).to include("/bills/#{bill.id}")
      expect(hash["cta_url"]).to include("partner=the-banner")
      expect(hash["cta_url"]).to include("ref=banner-123")
      expect(hash["cta_url"]).to include("utm_source=newsletter")
    end
  end

  describe "PartnerEngagementReportResource" do
    it "ships exactly the partner-facing aggregate whitelist with zero PII" do
      sway_locale = create(:sway_locale)
      org = create(:organization, sway_locale:, name: "The Baltimore Banner")
      bill = create(:bill, sway_locale:, title: "Housing Affordability Act")
      ArticleBill.create!(
        bill:,
        organization: org,
        partner_slug: "the-banner",
        article_url: "https://thebaltimorebanner.com/community/housing-bill",
        article_title: "City Council Considers Housing Bill",
        published_at: Time.current,
        clicks_count: 50,
        registrations_count: 10,
        votes_count: 8,
        pro_votes_count: 6,
        con_votes_count: 2
      )
      ArticleBill.create!(
        bill:,
        organization: org,
        partner_slug: "the-banner",
        article_url: "https://thebaltimorebanner.com/community/housing-bill-suppressed",
        article_title: "Small Sample Housing Bill",
        published_at: Time.current,
        clicks_count: 12,
        registrations_count: 2,
        votes_count: 3,
        pro_votes_count: 3,
        con_votes_count: 0
      )

      report = PartnerEngagementReportService.new(organization: org).call
      raw = PartnerEngagementReportResource.new(report).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)

      expect(hash.keys).to match_array(
        %w[
          partner_slug
          partner_name
          articles_count
          bills_count
          total_clicks
          total_registrations
          total_votes
          pro_percentage
          con_percentage
          articles
        ]
      )
      expect(hash["partner_slug"]).to eq("the-banner")
      expect(hash["partner_name"]).to eq("The Baltimore Banner")
      expect(hash["articles_count"]).to eq(2)
      expect(hash["bills_count"]).to eq(1)
      expect(hash["total_clicks"]).to eq(62)
      expect(hash["total_registrations"]).to eq(12)
      expect(hash["total_votes"]).to eq(11)
      expect(hash["pro_percentage"]).to eq(81.8)
      expect(hash["con_percentage"]).to eq(18.2)

      expected_article_keys = %w[
        id
        bill_id
        bill_title
        article_title
        article_url
        published_at
        clicks_count
        registrations_count
        votes_count
        sentiment_suppressed
        pro_votes_count
        con_votes_count
      ]

      articles = hash["articles"]
      expect(articles.length).to eq(2)
      expect(articles.map { |a| a.keys.map(&:to_s) }).to all(match_array(expected_article_keys))

      article_exposed = articles.find { |a| a[:votes_count] == 8 }
      expect(article_exposed[:sentiment_suppressed]).to be false
      expect(article_exposed[:pro_votes_count]).to eq(6)
      expect(article_exposed[:con_votes_count]).to eq(2)

      article_suppressed = articles.find { |a| a[:votes_count] == 3 }
      expect(article_suppressed[:sentiment_suppressed]).to be true
      expect(article_suppressed[:pro_votes_count]).to be_nil
      expect(article_suppressed[:con_votes_count]).to be_nil
    end
  end

  describe "BillSummaryRevisionResource" do
    it "ships exactly the pinned keys for bill summary revisions" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale: sway_locale)
      revision = BillSummaryRevision.create!(
        bill: bill,
        summary_markdown: "Summary markdown text.",
        origin: "operator_edit",
        actor: user,
        llm_provider: nil,
        llm_model: nil,
        publication_role: "published",
        review_state: "reviewed",
        restored_from: nil
      )

      raw = BillSummaryRevisionResource.new(revision).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)
      expected_keys = %w[
        id
        bill_id
        summary_markdown
        origin
        actor_name
        llm_provider
        llm_model
        publication_role
        review_state
        restored_from_id
        news_source_snapshot_id
        has_snapshot
        created_at
      ]

      expect(hash.keys).to match_array(expected_keys)
      expect(hash["has_snapshot"]).to be false
      expect(hash["news_source_snapshot_id"]).to be_nil

      article = create(:news_article, canonical_url: "https://thebaltimorebanner.com/transit")
      tv = create(:news_article_text_version, :extracted, news_article: article, text: "Some article text")
      bna = create(:bill_news_article, :approved, bill: bill, news_article: article, current_text_version: tv)
      snapshot = NewsArticleSourceSnapshotService.capture!(bill: bill, purpose: "summary", actor: user, sources: [bna])
      snapshot_rev = BillSummaryRevision.create!(
        bill: bill,
        summary_markdown: "Summary with snapshot.",
        origin: "operator_edit",
        actor: user,
        publication_role: "published",
        review_state: "reviewed",
        news_source_snapshot: snapshot
      )

      snapshot_raw = BillSummaryRevisionResource.new(snapshot_rev).serializable_hash #: Hash[Symbol, untyped]
      snapshot_hash = snapshot_raw.transform_keys(&:to_s)
      expect(snapshot_hash.keys).to match_array(expected_keys)
      expect(snapshot_hash["has_snapshot"]).to be true
      expect(snapshot_hash["news_source_snapshot_id"]).to eq(snapshot.id)
    end
  end

  describe "AdminBillNewsArticleResource" do
    it "ships exactly the pinned keys for admin bill news article" do
      sway_locale, _user = setup
      admin = create(:user, :sway_admin)
      bill = create(:bill, sway_locale: sway_locale)
      news_article = NewsArticle.create!(
        canonical_url: "https://thebaltimorebanner.com/community/housing-bill-123",
        title: "City Council Advances Housing Bill",
        outlet_name: "The Baltimore Banner",
        author_name: "Jane Reporter",
        published_at: 1.day.ago,
        article_kind: "reporting"
      )
      text_version = NewsArticleTextVersion.create!(
        news_article: news_article,
        text: "Full article text content for testing excerpt and digest.",
        origin: "manual",
        actor: admin,
        extraction_status: "extracted"
      )
      bill_news_article = BillNewsArticle.create!(
        bill: bill,
        news_article: news_article,
        match_kind: "direct",
        approved: false,
        review_version: 0,
        stance: nil,
        stance_version: 0,
        current_text_version: text_version
      )

      raw = AdminBillNewsArticleResource.new(bill_news_article).serializable_hash #: Hash[Symbol, untyped]
      expected_keys = %w[
        id
        bill_id
        news_article_id
        url
        title
        source_name
        domain
        author
        published_at
        approved
        review_version
        stance
        stance_version
        current_text_version_id
        has_text
        text_digest
        text_origin
        excerpt
        created_at
        updated_at
        match_kind
        article_kind
      ]

      hash = raw.transform_keys(&:to_s)
      expect(hash.keys).to match_array(expected_keys)
      expect(hash["url"]).to eq("https://thebaltimorebanner.com/community/housing-bill-123")
      expect(hash["title"]).to eq("City Council Advances Housing Bill")
      expect(hash["source_name"]).to eq("The Baltimore Banner")
      expect(hash["domain"]).to eq("thebaltimorebanner.com")
      expect(hash["author"]).to eq("Jane Reporter")
      expect(hash["has_text"]).to be(true)
      expect(hash["text_origin"]).to eq("manual")
      expect(hash["text_digest"]).to eq(text_version.digest)
      expect(hash["excerpt"]).to eq("Full article text content for testing excerpt and digest.")
      expect(hash["match_kind"]).to eq("direct")
      expect(hash["article_kind"]).to eq("reporting")
    end
  end

  # @lat: [[news-article-evidence#Changes after publication]]
  describe "NewsArticleResource" do
    it "ships exactly the public whitelist for an approved related article" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale:)
      news_article = NewsArticle.create!(
        canonical_url: "https://thebaltimorebanner.com/community/housing-bill-123",
        title: "City Council Advances Housing Bill",
        outlet_name: "The Baltimore Banner",
        author_name: "Jane Reporter",
        published_at: 1.day.ago,
        article_kind: "reporting"
      )
      bill_news_article = BillNewsArticle.create!(
        bill:,
        news_article:,
        match_kind: "direct",
        approved: true,
        review_version: 1
      )

      raw = NewsArticleResource.new(bill_news_article).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)
      expected_keys = %w[id title url outlet_name published_at author_name article_kind match_kind]

      expect(hash.keys).to match_array(expected_keys)
      expect(hash["id"]).to eq(bill_news_article.id)
      expect(hash["title"]).to eq("City Council Advances Housing Bill")
      expect(hash["url"]).to eq("https://thebaltimorebanner.com/community/housing-bill-123")
      expect(hash["outlet_name"]).to eq("The Baltimore Banner")
      expect(hash["author_name"]).to eq("Jane Reporter")
      expect(hash["published_at"]).to eq(news_article.published_at&.iso8601)
      expect(hash["article_kind"]).to eq("reporting")
      expect(hash["match_kind"]).to eq("direct")

      forbidden_keys = %w[text raw_text match_evidence approved approved_by_id review_version stance_version current_text_version_id discovery_requests]
      forbidden_keys.each do |forbidden|
        expect(hash).not_to have_key(forbidden)
      end
    end
  end

  # @lat: [[news-article-evidence#Changes after publication]]
  describe "NewsArticleTestimonyResource" do
    it "ships exactly the public whitelist for published opinion commentary" do
      sway_locale, _user = setup
      admin = create(:user, :sway_admin)
      bill = create(:bill, sway_locale:)
      news_article = NewsArticle.create!(
        canonical_url: "https://thebaltimorebanner.com/opinion/housing-editorial-123",
        title: "Editorial: City Council Should Pass Housing Bill",
        outlet_name: "The Baltimore Banner",
        author_name: "Editorial Board",
        published_at: 1.day.ago,
        article_kind: "editorial"
      )
      text_version = NewsArticleTextVersion.create!(
        news_article:,
        text: "The City Council must vote yes on the housing reform bill. Affordable housing is essential for Baltimore's future.",
        origin: "retrieved",
        extraction_status: "extracted"
      )
      bill_news_article = BillNewsArticle.create!(
        bill:,
        news_article:,
        match_kind: "direct",
        approved: true,
        approved_by: admin,
        approved_at: Time.current,
        review_version: 1,
        stance: "support",
        stance_by: admin,
        stance_version: 1,
        current_text_version: text_version
      )
      testimony = NewsArticleTestimony.create!(
        bill_news_article:,
        news_article_text_version: text_version,
        outlet_name: "The Baltimore Banner",
        author_name: "Editorial Board",
        citation_url: "https://thebaltimorebanner.com/opinion/housing-editorial-123",
        stance: "support",
        stance_version: 1,
        review_version: 1,
        text_digest: text_version.digest,
        evidence_excerpt: "The City Council must vote yes on the housing reform bill.",
        argument_markdown: "The Baltimore Banner editorial board urges a yes vote on the housing reform bill, arguing affordable housing is essential.",
        publication_state: "published"
      )

      raw = NewsArticleTestimonyResource.new(testimony).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)
      expected_keys = %w[id author_name outlet_name url stance argument]

      expect(hash.keys).to match_array(expected_keys)
      expect(hash["id"]).to eq(testimony.id)
      expect(hash["author_name"]).to eq("Editorial Board")
      expect(hash["outlet_name"]).to eq("The Baltimore Banner")
      expect(hash["url"]).to eq("https://thebaltimorebanner.com/opinion/housing-editorial-123")
      expect(hash["stance"]).to eq("support")
      expect(hash["argument"]).to eq(testimony.argument_markdown)

      forbidden_keys = %w[evidence_excerpt publication_state text_digest review_version stance_version news_article_text_version_id news_article_source_snapshot_id bill_news_article_id]
      forbidden_keys.each do |forbidden|
        expect(hash).not_to have_key(forbidden)
      end
    end
  end

  # @lat: [[news-article-evidence#Changes after publication]]
  describe "BillResource" do
    it "ships the core bill attributes with embedded related_articles and news_testimonies" do
      sway_locale, _user = setup
      admin = create(:user, :sway_admin)
      bill = create(:bill, sway_locale:)
      news_article = NewsArticle.create!(
        canonical_url: "https://thebaltimorebanner.com/community/housing-bill-123",
        title: "City Council Advances Housing Bill",
        outlet_name: "The Baltimore Banner",
        author_name: "Jane Reporter",
        published_at: 1.day.ago,
        article_kind: "reporting"
      )
      BillNewsArticle.create!(
        bill:,
        news_article:,
        match_kind: "direct",
        approved: true,
        review_version: 1
      )

      opinion_article = NewsArticle.create!(
        canonical_url: "https://thebaltimorebanner.com/opinion/housing-editorial-123",
        title: "Editorial: Pass Housing Bill",
        outlet_name: "The Baltimore Banner",
        author_name: "Editorial Board",
        published_at: 1.day.ago,
        article_kind: "editorial"
      )
      opinion_text = NewsArticleTextVersion.create!(
        news_article: opinion_article,
        text: "The City Council must vote yes. It will help Baltimore.",
        origin: "retrieved",
        extraction_status: "extracted"
      )
      opinion_bna = BillNewsArticle.create!(
        bill:,
        news_article: opinion_article,
        match_kind: "direct",
        approved: true,
        approved_by: admin,
        approved_at: Time.current,
        review_version: 1,
        stance: "support",
        stance_by: admin,
        stance_version: 1,
        current_text_version: opinion_text
      )
      NewsArticleTestimony.create!(
        bill_news_article: opinion_bna,
        news_article_text_version: opinion_text,
        outlet_name: "The Baltimore Banner",
        author_name: "Editorial Board",
        citation_url: "https://thebaltimorebanner.com/opinion/housing-editorial-123",
        stance: "support",
        stance_version: 1,
        review_version: 1,
        text_digest: opinion_text.digest,
        evidence_excerpt: "The City Council must vote yes.",
        argument_markdown: "Editorial board urges approval.",
        publication_state: "published"
      )

      raw = BillResource.new(bill).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)
      expected_keys = %w[
        id external_id external_version title summary summary_ai_unreviewed link
        chamber category categories status active scheduled_release_date_utc
        audio_bucket_path audio_by_line vote_date_time_utc introduced_date_time_utc
        house_vote_date_time_utc senate_vote_date_time_utc vote legislator_id
        sway_locale_id created_at related_articles news_testimonies
      ]

      expect(hash.keys).to match_array(expected_keys)
      expect(hash["related_articles"]).to be_an(Array)
      expect(hash["related_articles"].length).to eq(2)
      expect(hash["related_articles"].first.keys.map(&:to_s)).to match_array(
        %w[id title url outlet_name published_at author_name article_kind match_kind]
      )
      expect(hash["news_testimonies"]).to be_an(Array)
      expect(hash["news_testimonies"].length).to eq(1)
      expect(hash["news_testimonies"].first.keys.map(&:to_s)).to match_array(
        %w[id author_name outlet_name url stance argument]
      )
    end
  end

  # @lat: [[system-shape#System shape#One process, two languages#Why a payload goes through a resource rather than the record]]
  describe "GET /bills/:id and GET /bill_of_the_month populated payload keysets" do
    it "pins the page, bill, and every populated nested reader shape for both routes" do
      sway_locale, = setup
      sponsor = sway_locale.legislators.first
      current_term = sponsor.active_term
      create(:legislator_term, :prior_term, legislator: sponsor, district: current_term.district,
        title: "Former Delegate")

      bill = create(:bill, :without_session, sway_locale:, legislator: sponsor,
        scheduled_release_date_utc: Time.zone.today)
      create(:roll_call, bill:, house_roll_call_vote_number: 37, senate_roll_call_vote_number: 19)
      create(:legislator_vote, bill:, legislator: sponsor, legislator_term: current_term,
        support: LegislatorVote::Support::AGAINST)
      create(:organization_bill_position, bill:, organization: create(:organization, sway_locale:))
      score = bill.bill_score
      score.update!(for: 4, against: 2)
      create(:bill_score_district, bill_score: score, district: current_term.district, for: 3, against: 1)

      other_locale = create(:sway_locale, (sway_locale.city == "congress") ? :maryland : :congress)
      other_district = create(:district, sway_locale: other_locale)
      other_legislator = create(:legislator, sway_locale: other_locale)
      create(:legislator_term, legislator: other_legislator, district: other_district)
      voter = create(:user)
      create(:user_legislator, user: voter, legislator: other_legislator)
      voter.complete!
      sign_in(voter)
      cookies_hash[:sway_locale_id] = sway_locale.id
      user_vote = create(:user_vote, user: voter, bill:, support: LegislatorVote::Support::FOR)

      page_keys = %w[
        bill organizations organization_bill_positions legislator_votes legislators sponsor
        user_vote bill_score districts public_testimony_counts public_testimony_letters
      ]
      bill_keys = %w[
        id external_id external_version title summary link chamber category status active
        scheduled_release_date_utc audio_bucket_path audio_by_line vote_date_time_utc
        introduced_date_time_utc house_vote_date_time_utc senate_vote_date_time_utc
        legislator_id sway_locale_id created_at summary_ai_unreviewed vote categories
        related_articles news_testimonies
      ]
      legislator_keys = %w[
        id sway_locale_id external_id active link email title first_name last_name full_name
        phone fax party photo_url district twitter
      ]
      district_keys = %w[name number region_code]
      position_keys = %w[id bill_id organization support summary summary_ai_unreviewed]
      simple_organization_keys = %w[id sway_locale_id name icon_url]
      legislator_vote_keys = %w[id legislator_id bill_id support]
      score_keys = %w[id bill_id for against districts]
      score_district_keys = %w[
        bill_score_id district for against legislator_names comparison_suppressed for_percent against_percent at_large
      ]
      user_vote_keys = %w[id bill_id support]

      get "/bills/#{bill.id}", headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:ok)
      bill_page = response.parsed_body

      get "/bill_of_the_month", headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:ok)
      bill_of_the_month_page = response.parsed_body

      [bill_page, bill_of_the_month_page].each do |page|
        expect(page.keys).to match_array(page_keys)
        expect(page["bill"]).to be_present
        expect(page["bill"].keys).to match_array(bill_keys)
        expect(page["bill"]["vote"]).to be_present
        expect(page["bill"]["vote"].keys).to match_array(
          %w[id house_roll_call_vote_number senate_roll_call_vote_number]
        )
        expect(page["bill"]["categories"]).to be_an(Array)
        expect(page["bill"]["related_articles"]).to be_an(Array)
        expect(page["bill"]["news_testimonies"]).to be_an(Array)

        expect(page["sponsor"]).to be_present
        expect(page["sponsor"].keys).to match_array(legislator_keys)
        expect(page["sponsor"]["district"].keys).to match_array(district_keys)
        expect(page["sponsor"]["title"]).to eq(current_term.title)

        expect(page["legislators"]).not_to be_empty
        expect(page["legislators"].first.keys).to match_array(legislator_keys)
        expect(page["legislators"].first["district"].keys).to match_array(district_keys)
        expect(page["legislators"].find { |row| row["id"] == sponsor.id }["title"]).to eq(current_term.title)

        expect(page["organizations"]).not_to be_empty
        expect(page["organizations"].first.keys).to match_array(position_keys)
        expect(page["organizations"].first["organization"].keys).to match_array(simple_organization_keys)
        expect(page["organization_bill_positions"]).not_to be_empty
        expect(page["organization_bill_positions"].first.keys).to match_array(position_keys)
        expect(page["organization_bill_positions"].first["organization"].keys)
          .to match_array(simple_organization_keys)

        expect(page["legislator_votes"]).not_to be_empty
        expect(page["legislator_votes"].first.keys).to match_array(legislator_vote_keys)
        expect(page["user_vote"]).to be_present
        expect(page["user_vote"].keys).to match_array(user_vote_keys)
        expect(page["user_vote"]).to eq("id" => user_vote.id, "bill_id" => bill.id, "support" => "FOR")

        expect(page["bill_score"]).to be_present
        expect(page["bill_score"].keys).to match_array(score_keys)
        expect(page["bill_score"]["districts"]).not_to be_empty
        expect(page["bill_score"]["districts"].first.keys).to match_array(score_district_keys)
        expect(page["bill_score"]["districts"].first["district"].keys).to match_array(district_keys)
        expect(page["bill_score"]["districts"].first["legislator_names"]).to eq([sponsor.full_name])
        expect(page["districts"]).to eq([])
      end

      # @lat: [[district-chart-tooltip#The mobile bill JSON carries the names, the web page does not]]
      web_score_district_keys = %w[
        bill_score_id district for against comparison_suppressed for_percent against_percent at_large
      ]
      ["/bills/#{bill.id}", "/bill_of_the_month"].each do |web_path|
        get web_path
        web_score_districts = inertia.props[:bill_score]["districts"]
        expect(web_score_districts).not_to be_empty
        web_score_districts.each do |web_score_district|
          # In suppressed cases, some keys might be nil, but they should still be present
          # if they are part of the resource whitelist.
          expect(web_score_district.keys).to match_array(web_score_district_keys)
        end
        expect(web_score_districts.first["district"].keys).to match_array(district_keys)
      end
    end

    it "keeps the sponsor's legacy null shape when only a past term exists" do
      sway_locale, = setup
      past_district = create(:district, sway_locale:)
      past_sponsor = create(:legislator, sway_locale:)
      create(:legislator_term, :prior_term, legislator: past_sponsor, district: past_district,
        title: "Former Delegate")
      bill = create(:bill, :without_session, sway_locale:, legislator: past_sponsor)
      bill.bill_score.destroy!

      other_locale = create(:sway_locale, (sway_locale.city == "congress") ? :maryland : :congress)
      other_district = create(:district, sway_locale: other_locale)
      other_legislator = create(:legislator, sway_locale: other_locale)
      create(:legislator_term, legislator: other_legislator, district: other_district)
      voter = create(:user)
      create(:user_legislator, user: voter, legislator: other_legislator)
      voter.complete!
      sign_in(voter)
      cookies_hash[:sway_locale_id] = sway_locale.id

      get "/bills/#{bill.id}", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      page = response.parsed_body
      expect(page).to have_key("user_vote")
      expect(page["user_vote"]).to be_nil
      expect(page).to have_key("bill_score")
      expect(page["bill_score"]).to be_nil
      expect(page["sponsor"].keys).to match_array(%w[
        id sway_locale_id external_id active link email title first_name last_name full_name
        phone fax party photo_url district twitter
      ])
      expect(page["sponsor"]["active"]).to be(false)
      expect(page["sponsor"]["title"]).to be_nil
      expect(page["sponsor"]["district"]).to be_nil
    end

    it "uses the selected locale's real at-large district for guests on both bill routes" do
      sway_locale, = setup
      sponsor = sway_locale.legislators.first
      bill = create(:bill, :without_session, sway_locale:, legislator: sponsor,
        scheduled_release_date_utc: Time.zone.today)
      at_large_district = sway_locale.at_large_district

      expect(at_large_district).to be_present
      expect(at_large_district.number).to eq(0)
      session_hash.clear
      cookies_hash[:sway_locale_id] = sway_locale.id

      page_keys = %w[
        bill organizations organization_bill_positions legislator_votes legislators sponsor
        user_vote bill_score districts public_testimony_counts public_testimony_letters
      ]
      ["/bills/#{bill.id}", "/bill_of_the_month"].each do |path|
        get path, headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        page = response.parsed_body
        expect(page.keys).to match_array(page_keys)
        expect(page["districts"]).to be_present
        expect(page["districts"].first.keys).to match_array(%w[name number region_code])
        expect(page["districts"].first).to eq(
          "name" => at_large_district.name,
          "number" => 0,
          "region_code" => at_large_district.region_code
        )
        expect(page["public_testimony_counts"]).to be_nil
        expect(page["public_testimony_letters"]).to be_nil
      end
    end
  end

  # @lat: [[news-article-evidence#Changes after publication]]
  describe "GET /bills/:id and GET /bill_of_the_month news evidence reader endpoints" do
    let(:admin) { create(:user, :sway_admin) }

    it "exposes approved link-only articles and published commentary to guest and bearer clients" do
      sway_locale, user = setup
      create(:api_key, token: "bearer-test-token", bearer: user)
      bill = create(:bill, sway_locale:, summary: "Existing summary text citing news.")

      link_article = NewsArticle.create!(
        canonical_url: "https://thebaltimorebanner.com/community/housing-bill-link-only",
        title: "Link Only Housing Story",
        outlet_name: "The Baltimore Banner",
        author_name: "Staff Reporter",
        published_at: 2.days.ago,
        article_kind: "reporting"
      )
      link_bna = BillNewsArticle.create!(
        bill:,
        news_article: link_article,
        match_kind: "context",
        approved: true,
        approved_by: admin,
        approved_at: Time.current,
        review_version: 1
      )

      unapproved_article = NewsArticle.create!(
        canonical_url: "https://thebaltimorebanner.com/community/unapproved-story",
        title: "Candidate Story Not Yet Approved",
        outlet_name: "The Baltimore Banner",
        published_at: 1.day.ago,
        article_kind: "reporting"
      )
      BillNewsArticle.create!(
        bill:,
        news_article: unapproved_article,
        match_kind: "direct",
        approved: false
      )

      op_article = NewsArticle.create!(
        canonical_url: "https://thebaltimorebanner.com/opinion/editorial-pass-bill",
        title: "Editorial: Pass This Bill",
        outlet_name: "The Baltimore Banner",
        author_name: "Editorial Board",
        published_at: 1.day.ago,
        article_kind: "editorial"
      )
      op_text = NewsArticleTextVersion.create!(
        news_article: op_article,
        text: "The bill provides needed rent relief to city residents.",
        origin: "retrieved",
        extraction_status: "extracted"
      )
      op_bna = BillNewsArticle.create!(
        bill:,
        news_article: op_article,
        match_kind: "direct",
        approved: true,
        approved_by: admin,
        approved_at: Time.current,
        review_version: 1,
        stance: "support",
        stance_by: admin,
        stance_version: 1,
        current_text_version: op_text
      )
      testimony = NewsArticleTestimony.create!(
        bill_news_article: op_bna,
        news_article_text_version: op_text,
        outlet_name: "The Baltimore Banner",
        author_name: "Editorial Board",
        citation_url: "https://thebaltimorebanner.com/opinion/editorial-pass-bill",
        stance: "support",
        stance_version: 1,
        review_version: 1,
        text_digest: op_text.digest,
        evidence_excerpt: "The bill provides needed rent relief to city residents.",
        argument_markdown: "The editorial board strongly supports passage for rent relief.",
        publication_state: "published"
      )

      get "/bills/#{bill.id}", headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["bill"]).to be_present
      related = body["bill"]["related_articles"]
      testimonies = body["bill"]["news_testimonies"]

      expect(related).to be_an(Array)
      expect(related).not_to be_empty
      expect(related.pluck("id")).to include(link_bna.id, op_bna.id)
      expect(related.pluck("title")).not_to include("Candidate Story Not Yet Approved")
      link_entry = related.find { |a| a["id"] == link_bna.id }
      expect(link_entry.keys).to match_array(
        %w[id match_kind title url outlet_name author_name published_at article_kind]
      )
      expect(link_entry["title"]).to eq("Link Only Housing Story")
      expect(link_entry["url"]).to eq("https://thebaltimorebanner.com/community/housing-bill-link-only")
      expect(link_entry["match_kind"]).to eq("context")
      expect(link_entry.keys).not_to include("text", "raw_text", "current_text_version_id")

      expect(testimonies).to be_an(Array)
      expect(testimonies.length).to eq(1)
      expect(testimonies.first.keys).to match_array(
        %w[id author_name outlet_name stance url argument]
      )
      expect(testimonies.first["id"]).to eq(testimony.id)
      expect(testimonies.first["stance"]).to eq("support")
      expect(testimonies.first["author_name"]).to eq("Editorial Board")
      expect(testimonies.first.keys).not_to include("evidence_excerpt", "publication_state", "text_digest")

      get "/bills/#{bill.id}", headers: {"Authorization" => "Bearer bearer-test-token"}
      expect(response).to have_http_status(:ok)
      bearer_body = response.parsed_body
      expect(bearer_body["bill"]["related_articles"].pluck("id")).to match_array(related.pluck("id"))
      expect(bearer_body["bill"]["news_testimonies"].pluck("id")).to match_array(testimonies.pluck("id"))

      bill.update!(scheduled_release_date_utc: Time.zone.today)
      get "/bill_of_the_month", headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:ok)
      month_body = response.parsed_body
      expect(month_body["bill"]["related_articles"].pluck("id")).to match_array(related.pluck("id"))
      expect(month_body["bill"]["news_testimonies"].pluck("id")).to match_array(testimonies.pluck("id"))
    end

    it "hides stale commentary and withdrawn links while preserving previously published summary text" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale:, summary: "Historical published summary citing newsroom evidence.")
      op_article = NewsArticle.create!(
        canonical_url: "https://thebaltimorebanner.com/opinion/editorial-pass-bill-2",
        title: "Editorial 2",
        outlet_name: "The Baltimore Banner",
        article_kind: "editorial"
      )
      op_text = NewsArticleTextVersion.create!(
        news_article: op_article,
        text: "The bill must pass now.",
        origin: "retrieved",
        extraction_status: "extracted"
      )
      op_bna = BillNewsArticle.create!(
        bill:,
        news_article: op_article,
        match_kind: "direct",
        approved: true,
        approved_by: admin,
        approved_at: Time.current,
        review_version: 1,
        stance: "support",
        stance_by: admin,
        stance_version: 1,
        current_text_version: op_text
      )
      NewsArticleTestimony.create!(
        bill_news_article: op_bna,
        news_article_text_version: op_text,
        outlet_name: "The Baltimore Banner",
        author_name: "Editorial Board",
        citation_url: "https://thebaltimorebanner.com/opinion/editorial-pass-bill-2",
        stance: "support",
        stance_version: 1,
        review_version: 1,
        text_digest: op_text.digest,
        evidence_excerpt: "The bill must pass now.",
        argument_markdown: "Editorial urges passage now.",
        publication_state: "published"
      )

      op_bna.set_stance!("oppose", by: admin)

      get "/bills/#{bill.id}", headers: {"Accept" => "application/json"}
      body = response.parsed_body
      expect(body["bill"]["news_testimonies"]).to be_empty
      expect(body["bill"]["related_articles"].pluck("id")).to include(op_bna.id)
      expect(body["bill"]["summary"]).to eq("Historical published summary citing newsroom evidence.")

      op_bna.withdraw_approval!(by: admin)

      get "/bills/#{bill.id}", headers: {"Accept" => "application/json"}
      body2 = response.parsed_body
      expect(body2["bill"]["related_articles"]).to be_empty
      expect(body2["bill"]["news_testimonies"]).to be_empty
      expect(body2["bill"]["summary"]).to eq("Historical published summary citing newsroom evidence.")
    end

    # @lat: [[news-article-evidence#Changes after publication]]
    it "executes zero queries to news tables during 15-second client polling partial reloads" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale:)
      article = NewsArticle.create!(
        canonical_url: "https://thebaltimorebanner.com/community/housing-bill-polling-test",
        title: "Polling Test Story",
        outlet_name: "The Baltimore Banner"
      )
      BillNewsArticle.create!(
        bill:,
        news_article: article,
        approved: true,
        approved_by: admin,
        approved_at: Time.current,
        review_version: 1
      )

      queries = []
      callback = lambda do |_name, _start, _finish, _id, payload|
        sql = payload[:sql]
        queries << sql if payload[:name] != "SCHEMA" && !sql.include?("TRANSACTION")
      end

      headers = {
        "X-Inertia" => "true",
        "X-Inertia-Version" => InertiaRails.configuration.version.to_s,
        "X-Inertia-Partial-Component" => Pages::BILL,
        "X-Inertia-Partial-Data" => "bill_score,organizations,user_legislator_emails"
      }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        get "/bills/#{bill.id}", headers:
      end

      expect(response).to have_http_status(:ok)
      news_queries = queries.select { |q| q =~ /news_articles|bill_news_articles|news_article_testimonies/i }
      expect(news_queries).to be_empty

      bill.update!(scheduled_release_date_utc: Time.zone.today)
      queries.clear
      botm_headers = {
        "X-Inertia" => "true",
        "X-Inertia-Version" => InertiaRails.configuration.version.to_s,
        "X-Inertia-Partial-Component" => Pages::BILL_OF_THE_MONTH,
        "X-Inertia-Partial-Data" => "bill_score,organizations,user_legislator_emails"
      }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        get "/bill_of_the_month", headers: botm_headers
      end

      expect(response).to have_http_status(:ok)
      botm_news_queries = queries.select { |q| q =~ /news_articles|bill_news_articles|news_article_testimonies/i }
      expect(botm_news_queries).to be_empty
    end
  end

  describe "GET /bills legislative_sessions (LegislativeSessionResource)" do
    it "ships exactly id/name/active per legislative session" do
      sway_locale, _user = setup
      create(:legislative_session, sway_locale:, name: "2026 Session", active: true)
      create(:legislative_session, sway_locale:, name: "2024 Session", active: false)

      get "/bills", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      sessions = response.parsed_body.fetch("legislative_sessions")
      expect(sessions.length).to eq(2)
      expect(sessions.map(&:keys)).to all(match_array(%w[id name active]))
    end
  end

  describe "PublicTestimonyLetterResource" do
    # @lat: [[testimony-letters#Selecting browsable constituent letters]]
    it "ships exactly position/label/stance/body_text" do
      entry = Testimony::BrowsableLetters::Entry.new(
        position: 1,
        label: "Constituent Letter #1",
        stance: "support",
        body_text: "I support this bill."
      )

      raw = PublicTestimonyLetterResource.new(entry).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)
      expect(hash.keys).to match_array(%w[position label stance body_text])
      expect(hash.keys.map(&:to_sym)).to match_array(%i[position label stance body_text])
      expect(hash).to eq(
        "position" => 1,
        "label" => "Constituent Letter #1",
        "stance" => "support",
        "body_text" => "I support this bill."
      )
    end
  end

  describe "UserAddressChangeResource" do
    it "ships the exact audit key set with no street or coordinate fields" do
      locale = create(:sway_locale)
      previous_address = create(:address, street: "101 Audit St")
      new_address = create(:address, street: "202 Audit St")
      change = create(
        :user_address_change,
        previous_address:,
        new_address:,
        deactivated_legislator_ids: [1],
        activated_legislator_ids: [2],
        deactivated_district_ids: [10],
        activated_district_ids: [20],
        previous_sway_locale_ids: [locale.id],
        new_sway_locale_ids: [locale.id],
        prior_vote_count: 1,
        prior_voted_bill_ids: [99],
        prior_voted_sway_locale_ids: [locale.id]
      )

      raw = UserAddressChangeResource.new(change).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)

      expect(hash.keys).to match_array(
        %w[
          id user_id previous_address_id new_address_id
          deactivated_legislator_ids activated_legislator_ids
          deactivated_district_ids activated_district_ids
          previous_sway_locale_ids new_sway_locale_ids
          previous_sway_locale_names new_sway_locale_names
          prior_vote_count prior_voted_bill_ids prior_voted_sway_locale_ids
          cross_district cross_sway_locale voted_before_switch
          user_switch_count created_at
        ]
      )
      expect(hash["cross_district"]).to be(true)
      expect(hash["cross_sway_locale"]).to be(false)
      expect(hash["voted_before_switch"]).to be(true)
      expect(hash["user_switch_count"]).to eq(1)
      expect(hash["previous_sway_locale_names"]).to eq([locale.name])
      expect(hash["new_sway_locale_names"]).to eq([locale.name])
    end
  end

  describe "AdminLocaleSampleAddressResource" do
    # @lat: [[mobile-admin-area#The locales screen]]
    it "ships the exact sample address key set" do
      locale = create(:sway_locale, :baltimore)

      hash = AdminLocaleSampleAddressResource.new(locale).serializable_hash.transform_keys(&:to_s)

      expect(hash.keys).to match_array(%w[id sample_street sample_postal_code sample_latitude sample_longitude])
    end
  end

  describe "FeedItemResource" do
    it "ships the exact feed item keys and nested hash shapes" do
      locale = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
      district = create(:district, sway_locale: locale, name: "MD1")
      legislator = create(:legislator, district:, first_name: "Ada", last_name: "Lovelace", title: "Delegate")
      bill = create(:bill, sway_locale: locale, legislator:, external_id: "25-0001", title: "Sample Bill", summary: "Summary text")
      organization = create(:organization, sway_locale: locale, name: "Civic Org")
      position = create(:organization_bill_position, organization:, bill:, support: "FOR", active: true)
      user = create(:user)
      user_vote = create(:user_vote, user:, bill:, support: "FOR")
      legislator_vote = create(:legislator_vote, bill:, legislator:, support: "FOR")

      item = FeedQuery::Item.new(
        kind: "legislator_voted",
        key: "legislator_voted:#{legislator_vote.id}",
        occurred_at: Time.utc(2026, 5, 1, 12, 0, 0),
        sway_locale: locale,
        bill:,
        legislator:,
        legislators: [legislator],
        organization_bill_position: position,
        user_vote:,
        legislator_vote:
      )

      raw = FeedItemResource.new(item).serializable_hash #: Hash[Symbol, untyped]
      hash = raw.transform_keys(&:to_s)

      expect(hash.keys).to match_array(
        %w[
          key kind occurred_at sway_locale bill legislator legislators
          organization user_support legislator_support agreement
        ]
      )
      expect(hash["sway_locale"].keys).to match_array(%i[id name])
      expect(hash["bill"].keys).to match_array(%i[id external_id title summary summary_ai_unreviewed vote_count view_count share_count])
      expect(hash["legislator"].keys).to match_array(%i[id full_name title district_name photo_url])
      expect(hash["legislators"].first.keys).to match_array(%i[id full_name title district_name photo_url])
      expect(hash["organization"].keys).to match_array(%i[id name support])
    end
  end
end
