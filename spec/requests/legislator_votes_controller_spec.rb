require "rails_helper"

RSpec.describe "LegislatorVotesController admin gate", type: :request do
  # @type var empty_votes: Array[untyped]
  empty_votes = []
  include_examples "requires sway admin",
    verb: :post,
    path: "/legislator_votes",
    params: {bill_id: 0, legislator_votes: empty_votes}
end

RSpec.describe "LegislatorVotesController", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  # @lat: [[legislator-vote-upserter-guard-rules#Why LegislatorVoteUpserter guards writes the way it does]]
  let(:seat_legislator_for) do
    lambda do |sway_locale, anchor_date|
      district = create(:district, sway_locale:)
      legislator = create(:legislator, district:)
      cycle_start = TermWindow.cycle_start_year(sway_locale, anchor_date)
      create(
        :legislator_term,
        legislator:,
        district:,
        term_start_year: cycle_start,
        term_end_year: cycle_start + sway_locale.term_rules.cycle_years
      )
      legislator
    end
  end

  let(:build_legislator_vote_params) do
    lambda do |sway_locale|
      bill =
        create(
          :bill,
          sway_locale:,
          summary:
            "Summary from spec - spec/requests/legislator_votes_controller_spec.rb"
        )
      legislator = seat_legislator_for.call(sway_locale, bill.introduced_date_time_utc)

      {
        bill_id: bill.id,
        legislator_votes: [{support: "FOR", legislator_id: legislator.id}]
      }
    end
  end

  describe "POST /legislator_votes" do
    it "creates new Legislator Votes for a bill" do
      sway_locale, _user = setup

      count_legislator_votes = LegislatorVote.count

      params = build_legislator_vote_params.call(sway_locale)
      post legislator_votes_path, params: params

      expect(response).to have_http_status(302)

      expect(LegislatorVote.count).to eql(count_legislator_votes + 1)
      latest_vote = LegislatorVote.last!
      expect(latest_vote.bill_id).to eql(params[:bill_id])
      expect(latest_vote.legislator_id).to eql(
        params[:legislator_votes].first[:legislator_id]
      )
      expect(latest_vote.support).to eql("FOR")
    end

    # The Legislator Votes panel only appears on the Creator tab, so #create
    # redirects to that tab's URL. The tab used to travel as a
    # `?tab_key=creator` query param; it now sits in the path itself (tracked
    # As ).
    it "redirects to the Creator tab so the operator stays on the tab they submitted from" do
      sway_locale, _user = setup
      params = build_legislator_vote_params.call(sway_locale)
      bill_id = params[:bill_id]
      post legislator_votes_path, params: params

      expect(response).to have_http_status(302)
      expect(response.location).to include("/admin/bill_creator/#{bill_id}/creator")
      expect(response.location).not_to include("tab_key=")
    end

    context "source sticky-admin — creating a new vote" do
      it "sets source to 'manual' on the created row" do
        sway_locale, _user = setup
        params = build_legislator_vote_params.call(sway_locale)
        post legislator_votes_path, params: params

        expect(response).to have_http_status(302)
        expect(LegislatorVote.last!.source).to eq("manual")
      end
    end

    context "source sticky-admin — updating existing vote with different support" do
      it "flips source to 'manual' and updates support" do
        sway_locale, _user = setup
        legislator = create(:legislator)
        bill = create(:bill, sway_locale:, summary: "spec bill")
        existing = create(:legislator_vote,
          bill: bill, legislator: legislator,
          support: "FOR", source: "legistar")

        params = {
          bill_id: bill.id,
          legislator_votes: [{support: "AGAINST", legislator_id: legislator.id}]
        }
        post legislator_votes_path, params: params

        expect(response).to have_http_status(302)
        existing.reload
        expect(existing.support).to eq("AGAINST")
        expect(existing.source).to eq("manual")
      end
    end

    context "source sticky-admin — updating existing vote with same support but non-manual source" do
      it "flips source to 'manual' without changing support" do
        sway_locale, _user = setup
        legislator = create(:legislator)
        bill = create(:bill, sway_locale:, summary: "spec bill")
        existing = create(:legislator_vote,
          bill: bill, legislator: legislator,
          support: "FOR", source: "open_states")

        params = {
          bill_id: bill.id,
          legislator_votes: [{support: "FOR", legislator_id: legislator.id}]
        }
        post legislator_votes_path, params: params

        expect(response).to have_http_status(302)
        existing.reload
        expect(existing.support).to eq("FOR")
        expect(existing.source).to eq("manual")
      end
    end

    context "source sticky-admin — no-op when already manual and same support" do
      it "does not change the row when source is already manual and support matches" do
        sway_locale, _user = setup
        legislator = create(:legislator)
        bill = create(:bill, sway_locale:, summary: "spec bill")
        existing = create(:legislator_vote,
          bill: bill, legislator: legislator,
          support: "FOR", source: "manual")
        updated_at_before = existing.updated_at

        params = {
          bill_id: bill.id,
          legislator_votes: [{support: "FOR", legislator_id: legislator.id}]
        }
        post legislator_votes_path, params: params

        expect(response).to have_http_status(302)
        existing.reload
        expect(existing.source).to eq("manual")
        expect(existing.support).to eq("FOR")
        expect(existing.updated_at).to be_within(1.second).of(updated_at_before)
      end
    end

    # The controller hands the create-or-update work to
    # LegislatorVoteUpserter#upsert_legislator_vote with source: "manual", so
    # one change to that shared code reaches the admin path and the three
    # locale services at once, with nothing drifting apart.
    context "WR-04 — delegates upsert to LegislatorVoteUpserter" do
      it "calls upsert_legislator_vote with source: 'manual' for each param" do
        sway_locale, _user = setup
        legislator = create(:legislator)
        bill = create(:bill, sway_locale:, summary: "spec bill")
        params = {
          bill_id: bill.id,
          legislator_votes: [{support: "FOR", legislator_id: legislator.id}]
        }

        # Spy on the concern method on the controller class.
        expect_any_instance_of(LegislatorVotesController)
          .to receive(:upsert_legislator_vote)
          .with(legislator.id, kind_of(Struct), hash_including(source: "manual"))
          .and_call_original

        post legislator_votes_path, params: params
        expect(response).to have_http_status(302)
      end
    end

    # The loop used to run outside a transaction and put the raw exception
    # object into the Inertia errors prop. When one row's upsert returned false
    # because the vote was invalid, nothing noticed and the response still
    # reported success.
    context "transactional batch + String error prop" do
      it "rolls back every row and error-redirects when any vote is invalid (no partial commit)" do
        sway_locale, _user = setup
        bill = create(:bill, sway_locale:, summary: "spec bill")
        legislator1 = seat_legislator_for.call(sway_locale, bill.introduced_date_time_utc)
        legislator2 = seat_legislator_for.call(sway_locale, bill.introduced_date_time_utc)
        params = {
          bill_id: bill.id,
          legislator_votes: [
            {support: "FOR", legislator_id: legislator1.id},
            {support: "GARBAGE", legislator_id: legislator2.id} # invalid → upsert false
          ]
        }

        expect {
          post legislator_votes_path, params: params
        }.not_to change(LegislatorVote, :count)

        expect(response.location).to include("event_key=legislator_votes")
        follow_redirect!
        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props[:errors][:legislator_votes]).to be_a(String)
      end

      it "error-redirects (not 500) with a String message when legislator_votes is absent" do
        sway_locale, _user = setup
        bill = create(:bill, sway_locale:, summary: "spec bill")

        post legislator_votes_path, params: {bill_id: bill.id}

        expect(response).to have_http_status(:redirect)
        follow_redirect!
        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props[:errors][:legislator_votes]).to eq("No votes submitted.")
      end

      it "puts e.message (a String), never the exception object, in the errors prop on a raise" do
        sway_locale, _user = setup
        legislator = create(:legislator)
        bill = create(:bill, sway_locale:, summary: "spec bill")
        allow_any_instance_of(LegislatorVotesController)
          .to receive(:upsert_legislator_vote).and_raise(StandardError, "boom")

        post legislator_votes_path,
          params: {bill_id: bill.id, legislator_votes: [{support: "FOR", legislator_id: legislator.id}]}

        follow_redirect!
        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props[:errors][:legislator_votes]).to eq("boom")
      end
    end

    # @lat: [[legislator-votes-controller-admin-entry#Collecting failures instead of committing partial rows]]
    context "a legislator whose term does not cover the bill's date" do
      it "keeps the valid votes and names the skipped legislator in the flash" do
        sway_locale, _user = setup
        bill = create(:bill, sway_locale:, summary: "spec bill")
        seated = seat_legislator_for.call(sway_locale, bill.introduced_date_time_utc)
        unseated = create(:legislator)

        expect {
          post legislator_votes_path, params: {
            bill_id: bill.id,
            legislator_votes: [
              {support: "FOR", legislator_id: seated.id},
              {support: "AGAINST", legislator_id: unseated.id}
            ]
          }
        }.to change(LegislatorVote, :count).by(1)

        expect(LegislatorVote.exists?(bill: bill, legislator: seated)).to be(true)
        expect(LegislatorVote.exists?(bill: bill, legislator: unseated)).to be(false)
        expect(response.location).to include("event_key=organizations")
        expect(flash[:notice]).to eq("Saved 1 of 2 legislator votes.")
        expect(flash[:alert]).to eq(
          "No term covers this bill's date for #{unseated.full_name}. Fix the term and save again."
        )
      end

      it "still rolls the whole batch back when a vote is invalid alongside a skipped one" do
        sway_locale, _user = setup
        bill = create(:bill, sway_locale:, summary: "spec bill")
        seated = seat_legislator_for.call(sway_locale, bill.introduced_date_time_utc)
        invalid = seat_legislator_for.call(sway_locale, bill.introduced_date_time_utc)
        unseated = create(:legislator)

        expect {
          post legislator_votes_path, params: {
            bill_id: bill.id,
            legislator_votes: [
              {support: "FOR", legislator_id: seated.id},
              {support: "FOR", legislator_id: unseated.id},
              {support: "GARBAGE", legislator_id: invalid.id}
            ]
          }
        }.not_to change(LegislatorVote, :count)

        expect(response.location).to include("event_key=legislator_votes")
        follow_redirect!
        expect(inertia.props[:errors][:legislator_votes]).to include(invalid.id.to_s)
      end
    end
  end
end
