# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Partial-reload contracts", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  # `organizations` was added to the list so organization positions refresh on
  # the same 15-second score-sync beat. Build one array and splat it into both
  # the reload and the assertion, as this file does everywhere.
  describe "Bill page — usePoll only: [bill_score, organizations]" do
    it "serves the widened tuple on a partial reload of GET /bills/:id" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale: sway_locale)

      get "/bills/#{bill.id}"
      expect(inertia).to render_component(Pages::BILL)

      bill_props = %w[bill_score organizations]
      inertia_versioned_reload_only(*bill_props)
      expect(response).to have_http_status(:ok)
      expect(inertia.props.keys).to include(*bill_props)
    end
  end

  describe "Bill of the Month page — usePoll only: [bill_score, organizations]" do
    it "serves the widened tuple on a partial reload of GET /bill_of_the_month" do
      sway_locale, _user = setup
      create(
        :bill,
        sway_locale: sway_locale,
        legislator: create(:legislator),
        scheduled_release_date_utc: Time.zone.now
      )

      get "/bill_of_the_month"
      expect(inertia).to render_component(Pages::BILL_OF_THE_MONTH)

      bill_props = %w[bill_score organizations]
      inertia_versioned_reload_only(*bill_props)
      expect(response).to have_http_status(:ok)
      expect(inertia.props.keys).to include(*bill_props)
    end
  end

  describe "Bill page — DistrictLabel only: [legislators]" do
    it "omits the roster on a full load and serves it when the chart asks by name" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale: sway_locale)

      get "/bills/#{bill.id}"
      expect(inertia).to render_component(Pages::BILL)
      expect(inertia.props.keys).not_to include("legislators")

      inertia_versioned_reload_only("legislators")
      expect(response).to have_http_status(:ok)
      expect(inertia.props[:legislators]).to be_a(Array)
    end
  end

  describe "Legislators page — usePoll only: [legislators]" do
    it "serves legislators on a partial reload of GET /legislators" do
      _sway_locale, _user = setup

      get "/legislators"
      expect(inertia).to render_component(Pages::LEGISLATORS)

      inertia_versioned_reload_only("legislators")
      expect(response).to have_http_status(:ok)
      expect(inertia.props.keys).to include("legislators")
    end
  end

  describe "Feed page — cable/poll only: [newest_keys]" do
    it "omits optional newest_keys on a full load and serves it without items on a partial reload of GET /feed" do
      _sway_locale, _user = setup

      get "/feed"
      expect(inertia).to render_component(Pages::FEED)
      expect(inertia.props.keys).to include("items")
      expect(inertia.props.keys).not_to include("newest_keys")

      inertia_versioned_reload_only("newest_keys")
      expect(response).to have_http_status(:ok)
      expect(inertia.props.keys).to include("newest_keys")
      expect(inertia.props[:newest_keys]).to be_an(Array)
      expect(inertia.props.keys).not_to include("items")
    end
  end

  describe "Feed page — search and refresh only: [items, feed_search, feed_match_count, newest_keys]" do
    it "serves the search tuple and the refresh tuple on partial reloads of GET /feed" do
      _sway_locale, _user = setup

      get "/feed", params: {feed_search: "fare"}
      expect(inertia).to render_component(Pages::FEED)

      search_props = %w[items feed_search feed_match_count newest_keys]
      inertia_versioned_reload_only(*search_props)
      expect(response).to have_http_status(:ok)
      expect(inertia.props.keys).to include(*search_props)

      refresh_props = %w[items feed_match_count newest_keys]
      inertia_versioned_reload_only(*refresh_props)
      expect(response).to have_http_status(:ok)
      expect(inertia.props.keys).to include(*refresh_props)
    end
  end

  # Three tabs of one admin page (Pages::BILL_CREATOR), each refreshing its own
  # prop list, which #edit and the LegislationPipelineRunSourcing share both serve.
  # @lat: [[bill-creator-positions-tab#Splitting the tab split the poll list]]
  describe "Bill Creator — PipelineLLM tab tuple" do
    it "serves the full PIPELINE_LLM_ONLY_PROPS tuple on a partial reload of the Pipeline tab" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale: sway_locale)

      get "/admin/bill_creator/#{bill.id}/pipeline"
      expect(inertia).to render_component(Pages::BILL_CREATOR)

      # The reload and the assertion have to use the same list, or this example
      # could reload one set of props, check another, and still pass. Splat one
      # array into both.
      pipeline_llm_props = BillCreatorPollProps.pipeline_llm
      inertia_versioned_reload_only(*pipeline_llm_props)
      expect(response).to have_http_status(:ok)
      expect(inertia.props.keys).to include(*pipeline_llm_props)
      expect(pipeline_llm_props).not_to include("testimony_campaign_letters")
    end
  end

  describe "Bill Creator — Summary tab tuple" do
    it "serves the SUMMARY_ONLY_PROPS tuple on a partial reload of the Summary tab" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale: sway_locale)

      get "/admin/bill_creator/#{bill.id}/summary"
      expect(inertia).to render_component(Pages::BILL_CREATOR)

      summary_props = BillCreatorPollProps.summary
      inertia_versioned_reload_only(*summary_props)
      expect(response).to have_http_status(:ok)
      expect(inertia.props.keys).to include(*summary_props)
      expect(summary_props).not_to include("testimony_campaign_letters")
    end
  end

  describe "Bill Creator — Positions tab tuple" do
    it "serves the POSITIONS_ONLY_PROPS tuple on a partial reload of the Positions tab" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale: sway_locale)

      get "/admin/bill_creator/#{bill.id}/positions"
      expect(inertia).to render_component(Pages::BILL_CREATOR)

      positions_props = BillCreatorPollProps.positions
      inertia_versioned_reload_only(*positions_props)
      expect(response).to have_http_status(:ok)
      expect(inertia.props.keys).to include(*positions_props)
      expect(positions_props).not_to include("testimony_campaign_letters")
    end
  end

  describe "Bill Creator new action — full props and Pipeline tab poll" do
    # @lat: [[partial-reload-poll-lists#Why the laziness example reloads the real tuple]]
    it "keeps the full new-form payload and skips unpolled work on a real versioned reload" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale: sway_locale)

      get "/admin/bill_creator/new",
        params: {
          tab_key: "pipeline",
          bill_id: "42",
          download_missing_assets: "0"
        }

      expect(inertia).to render_component(Pages::BILL_CREATOR)

      new_action_props = %w[
        bills activity_log_entries activity_log_next_cursor activity_log_has_more bill
        legislators legislator_votes organizations tab_key pipeline_preview fetched_bills
        selected_stages bill_id download_missing_assets news_articles receipt_status
      ]
      expect(inertia.props.keys.map(&:to_s)).to include(*new_action_props)
      expect(inertia.props[:bills].pluck(:id)).to include(bill.id)
      expect(inertia).to have_props(
        {
          activity_log_entries: [],
          activity_log_next_cursor: nil,
          activity_log_has_more: false,
          bill: Bill.new.attributes,
          legislators: sway_locale.legislators.with_active_term.map(&:to_sway_json),
          legislator_votes: [],
          organizations: [],
          tab_key: "pipeline",
          pipeline_preview: nil,
          bill_id: "42",
          download_missing_assets: false,
          news_articles: [],
          receipt_status: nil
        }
      )
      expect(inertia.props[:fetched_bills]).to be_a(Array)
      expect(inertia.props[:selected_stages]).to eq(BillsController::DEFAULT_PIPELINE_STAGE_KEYS)

      pipeline_llm_props = BillCreatorPollProps.pipeline_llm
      unpolled_props = %w[bills activity_log_entries legislators organizations]
      unpolled_queries = []
      query_counter = lambda do |_name, _start, _finish, _id, payload|
        next if payload[:cached] || payload[:name] == "SCHEMA"

        sql = payload[:sql].to_s
        fetched_bill_lookup = sql.include?(
          'SELECT "bills"."external_id", "bills"."id", "bills"."title" FROM "bills"'
        )
        if !fetched_bill_lookup && sql.match?(/\b(?:bills|legislators|organizations|pipeline_activity_log_entries)\b/i)
          unpolled_queries << sql
        end
      end

      ActiveSupport::Notifications.subscribed(query_counter, "sql.active_record") do
        expect(BillCreator::PickerBillsSerializer).not_to receive(:call)
        ActiveRecord::Base.uncached do
          inertia_versioned_reload_only(*pipeline_llm_props)
        end
      end

      expect(response).to have_http_status(:ok)
      expect(inertia.props.keys.map(&:to_s)).to include("bill", "fetched_bills")
      expect(inertia.props.keys.map(&:to_s)).not_to include(*unpolled_props)
      expect(unpolled_queries).to be_empty
    end
  end

  # @lat: [[lazy-inertia-props#Lazy Inertia props]]
  describe "LegislationPipelineRunSourcing share is lazy" do
    it "runs no legislation_pipeline_runs query on a partial reload that omits the pipeline props" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale: sway_locale)
      LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "running", bill_id: nil)

      get "/bills/#{bill.id}"
      expect(inertia).to render_component(Pages::BILL)
      # The admin-gated share is present on the full load.
      expect(inertia.props.keys).to include("legislation_pipeline_run")

      pipeline_queries = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        pipeline_queries += 1 if payload[:sql].to_s.match?(/\blegislation_pipeline_runs\b/i)
      end
      inertia_versioned_reload_only("bill_score")
      expect(response).to have_http_status(:ok)
      ActiveSupport::Notifications.unsubscribe(subscriber)

      expect(inertia.props.keys).to include("bill_score")
      expect(pipeline_queries).to eq(0)
    end

    it "still serves legislation_pipeline_run on a partial reload that requests it" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale: sway_locale)
      run = LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "running", bill_id: nil)

      get "/bills/#{bill.id}"
      expect(inertia).to render_component(Pages::BILL)

      inertia_versioned_reload_only("legislation_pipeline_run")
      expect(response).to have_http_status(:ok)
      expect(inertia.props.keys).to include("legislation_pipeline_run")
      expect(inertia.props[:legislation_pipeline_run]).to include("id" => run.id)
    end
  end

  # @lat: [[partial-reload-poll-lists#Why the laziness example reloads the real tuple]]
  describe "Bill Creator bill_creator_props/testimony_report_props are lazy" do
    it "excludes the props the Pipeline tab's real poll does not name, and runs no query for them" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale: sway_locale)
      create(:category, active: true)
      create(:legislator_vote, bill: bill, legislator: bill.legislator)
      create(:campaign, bill: bill)
      create(:sending_service_domain, :proposed)

      get "/admin/bill_creator/#{bill.id}/pipeline"
      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props.keys).to include(
        "active_categories", "legislators", "legislator_votes", "campaigns", "sending_service_domains"
      )

      pipeline_llm_props = BillCreatorPollProps.pipeline_llm
      unpolled = %w[
        active_categories
        legislators
        legislator_votes
        campaigns
        campaign_organization_candidates
        organizations
        testimony_campaign_letters
      ]
      expect(pipeline_llm_props & unpolled).to eq([])

      skipped_prop_queries = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        sql = payload[:sql].to_s
        skipped_prop_queries += 1 if sql.match?(/\blegislators\b/i) && !sql.match?(/"legislators"\."id" = /i)
        skipped_prop_queries += 1 if sql.match?(/\bcategories\b/i) && !sql.match?(/bill_categories/i)
      end
      inertia_versioned_reload_only(*pipeline_llm_props)
      ActiveSupport::Notifications.unsubscribe(subscriber)

      expect(response).to have_http_status(:ok)
      expect(inertia.props.keys).to include(*pipeline_llm_props)
      expect(inertia.props.keys).not_to include(*unpolled)
      expect(skipped_prop_queries).to eq(0)
    end
  end

  # The PipelineRuns index refreshes its list on its own while a run in it is
  # still going: a WebSocket message first, plus a 15-second poll as backup.
  # Both reload only ["runs"]. This admin page signs the user in its own way,
  # as pipeline_runs_index_spec does.
  describe "PipelineRuns Index — cable/poll only: [runs]" do
    it "serves runs on a partial reload of GET /pipeline_runs" do
      admin = create(:user, :sway_admin)
      session_hash[:user_id] = admin.id
      create(:legislation_pipeline_run)

      get "/pipeline_runs"
      expect(inertia).to render_component("admin/PipelineRuns/Index")

      inertia_versioned_reload_only("runs")
      expect(response).to have_http_status(:ok)
      expect(inertia.props.keys).to include("runs")
    end
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Which run the Bill Creator surfaces]]
  describe "recent_pipeline_runs row carries completed_at" do
    it "serves the run's terminal timestamp, present on a finished run and null on a running one" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale: sway_locale)
      finished_run = create(:legislation_pipeline_run, :failed, bill: nil)
      running_run = create(:legislation_pipeline_run, :running, bill: nil)

      get "/admin/bill_creator/#{bill.id}/pipeline"
      expect(inertia).to render_component(Pages::BILL_CREATOR)

      inertia_versioned_reload_only("recent_pipeline_runs")
      expect(response).to have_http_status(:ok)

      rows = inertia.props["recent_pipeline_runs"].index_by { |row| row["id"] }
      expect(rows[finished_run.id].keys).to contain_exactly("id", "status", "kind", "bill_external_id", "created_at", "completed_at")
      expect(rows[finished_run.id]["completed_at"]).to be_present
      expect(rows[running_run.id]["completed_at"]).to be_nil

      # Same representation as PipelineRuns::RunSummarySerializer, which emits the
      # same field: UTC, second precision, trailing Z.
      expect(rows[finished_run.id]["completed_at"]).to eq(finished_run.completed_at.utc.iso8601)
      expect(rows[finished_run.id]["created_at"]).to eq(finished_run.created_at.utc.iso8601)
    end
  end
end
