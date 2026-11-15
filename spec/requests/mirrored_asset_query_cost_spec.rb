# frozen_string_literal: true

require "rails_helper"

# @lat: [[query-plan-indexes#A query-cost guard measures growth, not a ceiling]]
RSpec.describe "Reading response payloads and stored copies", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  def asset_row_reads
    seen = [] #: Array[String]
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if /SCHEMA|TRANSACTION/.match?(payload[:name].to_s)

      seen << payload[:sql].to_s
    end
    begin
      yield
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end
    seen.count { |sql| sql.include?("active_storage_attachments") || sql.include?("active_storage_blobs") }
  end

  def mirrored_asset_response_measurement
    {
      attachment_reads: asset_row_reads { yield },
      response_bytes: response.body.bytesize
    }
  end

  def bill_score_district_query_counts
    counts = {bill_score_districts: 0, districts: 0}
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next unless sql.match?(/\bSELECT\b/i)

      counts[:bill_score_districts] += 1 if sql.match?(/\bFROM\s+["'`]?bill_score_districts["'`]?(?=\s|$)/i)
      counts[:districts] += 1 if sql.match?(/\bFROM\s+["'`]?districts["'`]?(?=\s|$)/i)
    end
    begin
      yield
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end
    counts
  end

  def sql_response_measurement(&block)
    telemetry = Sway::SqlQueryTelemetry.measure(&block)
    {
      queries: telemetry.queries,
      max_repeats: telemetry.max_repeats,
      top_fingerprint: telemetry.top_fingerprint,
      response_bytes: response.body.bytesize
    }
  end

  def add_bill_score_districts(count:, from:, sway_locale:, bill_score:)
    count.times do |index|
      district = create(:district, sway_locale:, name: "Score District #{from + index}")
      create(:bill_score_district, bill_score:, district:, for: 4, against: 2)
    end
  end

  def add_correlated_bill_votes(count:, from:, sway_locale:, bill:)
    count.times do |index|
      district = create(:district, sway_locale:, name: "Vote District #{from + index}")
      legislator = create(
        :legislator,
        sway_locale:,
        district:,
        external_id: "payload-voter-#{from + index}"
      )
      create(
        :legislator_term,
        legislator:,
        district:,
        term_start_year: 2019,
        term_end_year: 2021
      )
      timestamp = Time.current
      LegislatorVote.insert_all!([{
        bill_id: bill.id,
        legislator_id: legislator.id,
        support: LegislatorVote::Support::FOR,
        source: "manual",
        inferred: false,
        created_at: timestamp,
        updated_at: timestamp
      }])
    end
  end

  def add_session_roster_members(count:, from:, sway_locale:, session:)
    count.times do |index|
      district = create(:district, sway_locale:, name: "Roster District #{from + index}")
      legislator = create(:legislator, district:, sway_locale:, external_id: "roster-#{from + index}")
      create(
        :legislator_term,
        legislator:,
        district:,
        term_start_year: 2025,
        term_end_year: 2027,
        began_on: session.start_date,
        ended_on: session.end_date,
        began_on_source: LegislatorTerm::DateSource::OBSERVED,
        ended_on_source: LegislatorTerm::DateSource::OBSERVED
      )
    end
  end

  def add_stored_roster_members(count:, from:, sway_locale:, session: nil)
    count.times do |index|
      district = create(:district, sway_locale:, name: "Stored Photo District #{from + index}")
      legislator = create(
        :legislator,
        district:,
        sway_locale:,
        external_id: "stored-photo-roster-#{from + index}"
      )
      create(
        :legislator_term,
        legislator:,
        district:,
        term_start_year: 2025,
        term_end_year: 2027,
        began_on: session&.start_date || (Date.current - 1.day),
        ended_on: session&.end_date || (Date.current + 1.day),
        began_on_source: LegislatorTerm::DateSource::OBSERVED,
        ended_on_source: LegislatorTerm::DateSource::OBSERVED
      )
      legislator.photo.attach(
        io: StringIO.new("roster-photo-#{from + index}"),
        filename: "roster-#{from + index}.png",
        content_type: "image/png"
      )
    end
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now]]
  def seated_roster_entries(payload, external_id_prefix)
    payload
      .fetch("legislators")
      .select { |entry| entry.fetch("external_id").to_s.start_with?(external_id_prefix) }
  end

  def reads_at_two_sizes(add:, &probe)
    add.call(2, 0)
    small = mirrored_asset_response_measurement(&probe)
    expect(small.fetch(:attachment_reads)).to be_positive,
      "measured no reads of a stored copy, so this compares nothing"
    expect(small.fetch(:response_bytes)).to be_positive,
      "measured a zero-byte response, so this compares nothing"

    add.call(4, 2)
    [small, mirrored_asset_response_measurement(&probe)]
  end

  describe "an organization icon" do
    def add_organizations(count:, from:, sway_locale:, user:, bill:)
      count.times do |index|
        organization = create(:organization, sway_locale: sway_locale, name: "Icon Org #{from + index}")
        organization.icon.attach(
          io: StringIO.new("icon-bytes"),
          filename: "icon#{from + index}.png",
          content_type: "image/png"
        )
        create(:organization_bill_position, organization: organization, bill: bill, active: true)
        create(:user_organization_membership, user: user, organization: organization, status: "active")
      end
    end

    def organization_adder(sway_locale:, user:, bill:)
      ->(count, from) { add_organizations(count: count, from: from, sway_locale: sway_locale, user: user, bill: bill) }
    end

    it "holds steady on the bill page" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale: sway_locale)

      small, large = reads_at_two_sizes(add: organization_adder(sway_locale: sway_locale, user: user, bill: bill)) do
        get bill_path(bill)
        expect(response).to have_http_status(:ok)
      end

      expect(large.fetch(:attachment_reads)).to eq(small.fetch(:attachment_reads))
    end

    it "holds steady on the bill creator" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale: sway_locale)

      small, large = reads_at_two_sizes(add: organization_adder(sway_locale: sway_locale, user: user, bill: bill)) do
        get "/admin/bill_creator/#{bill.id}/creator"
        expect(response).to have_http_status(:ok)
      end

      expect(large.fetch(:attachment_reads)).to eq(small.fetch(:attachment_reads))
    end

    it "holds steady on the admin organizations list" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale: sway_locale)

      small, large = reads_at_two_sizes(add: organization_adder(sway_locale: sway_locale, user: user, bill: bill)) do
        get organizations_path, headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:ok)
      end

      expect(large.fetch(:attachment_reads)).to eq(small.fetch(:attachment_reads))
    end

    it "holds steady on a person's own memberships list" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale: sway_locale)

      small, large = reads_at_two_sizes(add: organization_adder(sway_locale: sway_locale, user: user, bill: bill)) do
        get users_organization_memberships_path
        expect(response).to have_http_status(:ok)
      end

      expect(large.fetch(:attachment_reads)).to eq(small.fetch(:attachment_reads))
    end
  end

  # @lat: [[query-plan-indexes#A query-cost guard measures growth, not a ceiling]]
  describe "a legislator portrait" do
    def add_past_legislators(count:, from:, sway_locale:, user:)
      count.times do |index|
        district = create(:district, sway_locale: sway_locale, name: "Past District #{from + index}")
        legislator = create(
          :legislator,
          district: district,
          sway_locale: sway_locale,
          external_id: "past-#{from + index}"
        )
        legislator.photo.attach(
          io: StringIO.new("photo-bytes"),
          filename: "photo#{from + index}.png",
          content_type: "image/png"
        )
        create(:legislator_term, legislator: legislator, district: district)
        create(:user_legislator, user: user, legislator: legislator, active: false)
      end
    end

    it "holds steady on the history tab" do
      sway_locale, user = setup
      adder = ->(count, from) { add_past_legislators(count: count, from: from, sway_locale: sway_locale, user: user) }

      small, large = reads_at_two_sizes(add: adder) do
        get "/legislators", params: {tab: "history"}
        expect(response).to have_http_status(:ok)
      end

      expect(large.fetch(:attachment_reads)).to eq(small.fetch(:attachment_reads))
    end
  end

  describe "a bill page legislator roster" do
    it "keeps initial Inertia bytes flat while default bearer JSON grows with the eligible roster" do
      sway_locale, user = setup
      session = create(
        :legislative_session,
        sway_locale:,
        name: "Roster payload measurement",
        start_date: Date.new(2025, 1, 3),
        end_date: Date.new(2027, 1, 3),
        active: false
      )
      bill = create(:bill, sway_locale:, legislative_session: session)
      api_token = "roster-payload-measurement-token"
      create(:api_key, token: api_token, bearer: user)

      add_roster = lambda do |count, from|
        add_session_roster_members(count:, from:, sway_locale:, session:)
      end

      add_roster.call(2, 0)
      browser_small = mirrored_asset_response_measurement do
        get bill_path(bill)
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL)
      end
      json_small = mirrored_asset_response_measurement do
        get bill_path(bill), headers: {"Authorization" => "Bearer #{api_token}"}
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
      end
      small_roster = seated_roster_entries(response.parsed_body, "roster-")
      expect(small_roster.length).to eq(2),
        "expected the short JSON response to contain the two session legislators it seated"
      add_roster.call(2, 2)
      browser_large = mirrored_asset_response_measurement do
        get bill_path(bill)
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL)
      end
      json_large = mirrored_asset_response_measurement do
        get bill_path(bill), headers: {"Authorization" => "Bearer #{api_token}"}
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
      end
      large_roster = seated_roster_entries(response.parsed_body, "roster-")
      expect(large_roster.length).to eq(4),
        "expected the large JSON response to contain the four session legislators it seated"
      expect(browser_small.fetch(:response_bytes)).to be_positive
      expect(json_small.fetch(:response_bytes)).to be_positive
      expect(browser_large.fetch(:response_bytes)).to eq(browser_small.fetch(:response_bytes)),
        "expected browser response bytes #{browser_large.fetch(:response_bytes)} to stay flat at #{browser_small.fetch(:response_bytes)} as the optional roster grows"
      expect(json_large.fetch(:response_bytes)).to be > json_small.fetch(:response_bytes),
        "expected default bearer JSON bytes #{json_large.fetch(:response_bytes)} to grow beyond #{json_small.fetch(:response_bytes)} with its serialized roster"
    end

    it "serves stored roster photos without attachment-query growth" do
      sway_locale, user = setup
      session = create(
        :legislative_session,
        sway_locale:,
        name: "Stored roster photo measurement",
        start_date: Date.new(2025, 1, 3),
        end_date: Date.new(2027, 1, 3),
        active: false
      )
      bill = create(:bill, sway_locale:, legislative_session: session)
      api_token = "stored-roster-photo-measurement-token"
      create(:api_key, token: api_token, bearer: user)
      request_json = -> {
        get bill_path(bill), headers: {"Authorization" => "Bearer #{api_token}"}
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
      }

      add_stored_roster_members(count: 2, from: 0, sway_locale:, session:)
      small = mirrored_asset_response_measurement(&request_json)
      small_payload = seated_roster_entries(response.parsed_body, "stored-photo-roster-")
      expect(small_payload.length).to eq(2),
        "expected the short JSON response to contain both stored-photo legislators it seated"
      expect(small.fetch(:attachment_reads)).to be_positive,
        "expected the short response to read stored attachment/blob rows"
      add_stored_roster_members(count: 18, from: 2, sway_locale:, session:)
      large = mirrored_asset_response_measurement(&request_json)
      large_payload = seated_roster_entries(response.parsed_body, "stored-photo-roster-")
      expect(large_payload.length).to eq(20),
        "expected the large JSON response to contain all twenty stored-photo legislators it seated"
      expect(large.fetch(:attachment_reads)).to eq(small.fetch(:attachment_reads)),
        "expected photo attachment/blob reads to stay flat as the serialized roster grows"
      expect(large.fetch(:response_bytes)).to be > small.fetch(:response_bytes),
        "expected the larger JSON response to include its additional roster entries"
      expect(large_payload.map { |entry| entry.fetch("photo_url") })
        .to all(match(%r{/rails/active_storage/}))
    end

    it "serves the sponsor's stored photo URL from the Sway host" do
      sway_locale, user = setup
      session = create(:legislative_session, sway_locale:, active: false)
      sponsor = create(:legislator, sway_locale:, external_id: "stored-photo-sponsor")
      sponsor.update!(photo_url: "https://source.invalid/sponsor.png")
      sponsor.photo.attach(
        io: StringIO.new("sponsor-photo-bytes"),
        filename: "sponsor.png",
        content_type: "image/png"
      )
      bill = create(:bill, sway_locale:, legislative_session: session, legislator: sponsor)
      api_token = "stored-sponsor-photo-measurement-token"
      create(:api_key, token: api_token, bearer: user)

      get bill_path(bill), headers: {"Authorization" => "Bearer #{api_token}"}

      expect(response).to have_http_status(:ok)
      photo_url = response.parsed_body.dig("sponsor", "photo_url")
      uri = URI.parse(photo_url)
      expected_host = Rails.application.config.action_mailer.default_url_options[:host]
        .then { |mailer_host| Rails.application.routes.default_url_options[:host] || mailer_host }
      expect(uri.host).to eq(expected_host),
        "expected the sponsor photo URL to use the configured Sway application host"
      expect(uri.path).to match(%r{/rails/active_storage/}),
        "expected the sponsor photo URL to point at Sway's stored copy"
    end

    it "preloads stored copies for the populated active-term fallback roster" do
      sway_locale = create(:sway_locale, :congress)
      user = create(:user)
      sponsor = create(:legislator, sway_locale:)
      bill = create(:bill, :without_session, sway_locale:, legislator: sponsor)
      api_token = "stored-fallback-roster-photo-measurement-token"
      create(:api_key, token: api_token, bearer: user)
      request_json = -> {
        get bill_path(bill), headers: {"Authorization" => "Bearer #{api_token}"}
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
      }

      add_stored_roster_members(count: 2, from: 0, sway_locale:)
      small = mirrored_asset_response_measurement(&request_json)
      expect(response.parsed_body.fetch("legislators").length).to eq(2),
        "expected the short fallback response to contain both eligible stored-photo legislators"
      expect(small.fetch(:attachment_reads)).to be_positive,
        "expected the fallback response to read stored attachment/blob rows"

      add_stored_roster_members(count: 18, from: 2, sway_locale:)
      large = mirrored_asset_response_measurement(&request_json)
      expect(response.parsed_body.fetch("legislators").length).to eq(20),
        "expected the large fallback response to contain all twenty eligible stored-photo legislators"
      expect(large.fetch(:attachment_reads)).to eq(small.fetch(:attachment_reads)),
        "expected fallback photo attachment/blob reads to stay flat as the current roster grows"
      expect(large.fetch(:response_bytes)).to be > small.fetch(:response_bytes),
        "expected the larger fallback JSON response to include its additional roster entries"
    end
  end

  describe "requested bill page props" do
    it "keeps opted-out bearer bytes flat while the default roster payload grows" do
      sway_locale, user = setup
      session = create(
        :legislative_session,
        sway_locale:,
        name: "Optional roster payload measurement",
        start_date: Date.new(2025, 1, 3),
        end_date: Date.new(2027, 1, 3),
        active: false
      )
      bill = create(:bill, sway_locale:, legislative_session: session)
      api_token = "requested-roster-payload-measurement-token"
      create(:api_key, token: api_token, bearer: user)
      add_roster = lambda do |count, from|
        add_session_roster_members(count:, from:, sway_locale:, session:)
      end
      default_headers = {"Authorization" => "Bearer #{api_token}"}
      omit_headers = default_headers.merge(
        "X-Sway-Omit-Props" => "legislators,legislator_votes,districts"
      )

      add_roster.call(2, 0)
      default_small = mirrored_asset_response_measurement do
        get bill_path(bill), headers: default_headers
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
      end
      expect(seated_roster_entries(response.parsed_body, "roster-").length).to eq(2),
        "expected the default response to serialize the two session legislators it seated"
      omitted_small = mirrored_asset_response_measurement do
        get bill_path(bill), headers: omit_headers
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
      end
      expect(response.parsed_body.keys).to include("bill", "organizations", "organization_bill_positions")

      add_roster.call(2, 2)
      default_large = mirrored_asset_response_measurement do
        get bill_path(bill), headers: default_headers
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
      end
      expect(seated_roster_entries(response.parsed_body, "roster-").length).to eq(4),
        "expected the default response to serialize the four session legislators it seated"
      omitted_large = mirrored_asset_response_measurement do
        get bill_path(bill), headers: omit_headers
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
      end
      expect(response.parsed_body.keys).to include("bill", "organizations", "organization_bill_positions")

      expect(default_small.fetch(:response_bytes)).to be_positive
      expect(omitted_small.fetch(:response_bytes)).to be_positive
      expect(default_large.fetch(:response_bytes)).to be > default_small.fetch(:response_bytes),
        "expected default bearer JSON bytes to grow with its populated roster"
      expect(omitted_large.fetch(:response_bytes)).to eq(omitted_small.fetch(:response_bytes)),
        "expected opted-out bearer bytes #{omitted_large.fetch(:response_bytes)} to stay flat at #{omitted_small.fetch(:response_bytes)} as the roster grows"
      expect(omitted_large.fetch(:response_bytes)).to be < default_large.fetch(:response_bytes),
        "expected the opted-out response to be smaller than default JSON containing the roster"
    end
  end

  describe "the Bill Creator new-form poll" do
    it "keeps unpolled roster work out of a versioned Pipeline poll as the locale roster grows" do
      sway_locale, _user = setup
      session = create(
        :legislative_session,
        sway_locale:,
        name: "Bill Creator new-form payload measurement",
        start_date: Date.new(2025, 1, 3),
        end_date: Date.new(2027, 1, 3),
        active: false
      )
      bill = create(:bill, sway_locale:)
      path = "/admin/bill_creator/new?tab_key=pipeline&bill_id=#{bill.id}&download_missing_assets=0"
      add_roster = lambda do |count, from|
        add_session_roster_members(count:, from:, sway_locale:, session:)
      end

      add_roster.call(1, 0)
      initial_small = sql_response_measurement do
        get path
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props.keys).to include(
          "bills", "activity_log_entries", "activity_log_next_cursor", "activity_log_has_more",
          "bill", "legislators", "legislator_votes", "organizations", "tab_key", "pipeline_preview",
          "fetched_bills", "selected_stages", "bill_id", "download_missing_assets", "news_articles",
          "receipt_status"
        )
        expect(inertia.props.fetch("legislators").length).to eq(2),
          "expected the short full form to contain its two locale legislators"
      end
      poll_small = sql_response_measurement do
        inertia_versioned_reload_only(*BillCreatorPollProps.pipeline_llm)
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props.keys).to include("bill", "fetched_bills")
        expect(inertia.props.keys).not_to include(
          "bills", "activity_log_entries", "activity_log_next_cursor", "activity_log_has_more",
          "legislators", "legislator_votes", "organizations"
        )
      end
      expect(initial_small.fetch(:queries)).to be_positive,
        "measured no SQL while rendering the full Bill Creator form"
      expect(initial_small.fetch(:response_bytes)).to be_positive,
        "measured a zero-byte full Bill Creator response"
      expect(poll_small.fetch(:queries)).to be_positive,
        "measured no SQL while serving the Bill Creator Pipeline poll"
      expect(poll_small.fetch(:response_bytes)).to be_positive,
        "measured a zero-byte Bill Creator Pipeline poll response"

      add_roster.call(2, 1)
      initial_large = sql_response_measurement do
        get path
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props.fetch("legislators").length).to eq(4),
          "expected the large full form to contain its four locale legislators"
      end
      poll_large = sql_response_measurement do
        inertia_versioned_reload_only(*BillCreatorPollProps.pipeline_llm)
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props.keys).to include("bill", "fetched_bills")
        expect(inertia.props.keys).not_to include(
          "bills", "activity_log_entries", "activity_log_next_cursor", "activity_log_has_more",
          "legislators", "legislator_votes", "organizations"
        )
      end
      expect(initial_large.fetch(:response_bytes)).to be > initial_small.fetch(:response_bytes),
        "expected the full new-form response to grow with its serialized roster"
      expect(poll_large.fetch(:response_bytes)).to eq(poll_small.fetch(:response_bytes)),
        "expected the real Pipeline poll bytes to stay flat while unpolled legislators grow"
      expect(poll_large.fetch(:queries)).to eq(poll_small.fetch(:queries)),
        "expected the real Pipeline poll query count to stay flat while unpolled legislators grow"
    end
  end

  describe "the Bill Creator new-form photo roster" do
    # @lat: [[query-plan-indexes#A query-cost guard measures growth, not a ceiling]]
    it "keeps photo attachment reads flat as the full form roster grows" do
      sway_locale, = setup

      add_stored_roster_members(count: 1, from: 0, sway_locale:)
      small = mirrored_asset_response_measurement do
        get "/admin/bill_creator/new"
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props.fetch("legislators").length).to eq(2),
          "expected the short new form to serialize its two active legislators"
      end

      add_stored_roster_members(count: 18, from: 1, sway_locale:)
      large = mirrored_asset_response_measurement do
        get "/admin/bill_creator/new"
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props.fetch("legislators").length).to eq(20),
          "expected the large new form to serialize its twenty active legislators"
      end

      expect(small.fetch(:attachment_reads)).to be_positive,
        "measured no photo attachment/blob reads for the small new-form roster"
      expect(large.fetch(:attachment_reads)).to eq(small.fetch(:attachment_reads)),
        "expected Bill Creator photo reads to stay flat at #{small.fetch(:attachment_reads)} as its roster grows, got #{large.fetch(:attachment_reads)}"
      expect(large.fetch(:response_bytes)).to be > small.fetch(:response_bytes),
        "expected the full new-form response to grow with its serialized photo roster"
    end

    it "keeps total SQL queries and max repeated fingerprints flat as the full form roster grows" do
      sway_locale, = setup

      add_stored_roster_members(count: 1, from: 0, sway_locale:)
      small = sql_response_measurement do
        get "/admin/bill_creator/new"
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props.fetch("legislators").length).to eq(2)
      end

      add_stored_roster_members(count: 6, from: 1, sway_locale:)
      large = sql_response_measurement do
        get "/admin/bill_creator/new"
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props.fetch("legislators").length).to eq(8)
      end

      expect(large.fetch(:queries)).to eq(small.fetch(:queries)),
        "expected Bill Creator SQL queries to stay flat at #{small.fetch(:queries)} as roster grows, got #{large.fetch(:queries)} (top: #{large.fetch(:top_fingerprint)})"
      expect(large.fetch(:max_repeats)).to eq(small.fetch(:max_repeats))
    end
  end

  describe "bills index and bill page SQL fingerprint stability" do
    it "keeps total SQL queries flat on the bill page session roster as legislators grow" do
      sway_locale, user = setup
      session = create(
        :legislative_session,
        sway_locale:,
        name: "Session SQL fingerprint measurement",
        start_date: Date.new(2025, 1, 3),
        end_date: Date.new(2027, 1, 3),
        active: false
      )
      bill = create(:bill, sway_locale:, legislative_session: session)
      api_token = "session-roster-sql-measurement-token"
      create(:api_key, token: api_token, bearer: user)

      add_session_roster_members(count: 2, from: 0, sway_locale:, session:)
      small = sql_response_measurement do
        get bill_path(bill), headers: {"Authorization" => "Bearer #{api_token}"}
        expect(response).to have_http_status(:ok)
        expect(seated_roster_entries(response.parsed_body, "roster-").length).to eq(2)
      end

      add_session_roster_members(count: 6, from: 2, sway_locale:, session:)
      large = sql_response_measurement do
        get bill_path(bill), headers: {"Authorization" => "Bearer #{api_token}"}
        expect(response).to have_http_status(:ok)
        expect(seated_roster_entries(response.parsed_body, "roster-").length).to eq(8)
      end

      expect(large.fetch(:queries)).to eq(small.fetch(:queries)),
        "expected bill page roster SQL queries to stay flat at #{small.fetch(:queries)}, got #{large.fetch(:queries)} (top: #{large.fetch(:top_fingerprint)})"
    end

    it "keeps total SQL queries flat on /bills as bills with summaries and district scores grow" do
      sway_locale, user = setup
      api_token = "bills-index-sql-measurement-token"
      create(:api_key, token: api_token, bearer: user)

      add_bills = lambda do |count, from|
        count.times do |idx|
          bill = create(:bill, sway_locale:, summary: "Published summary #{from + idx}")
          bill_score = create(:bill_score, bill:)
          add_bill_score_districts(count: 2, from: (from + idx) * 10, sway_locale:, bill_score:)
        end
      end

      add_bills.call(2, 0)
      small = sql_response_measurement do
        get bills_path, headers: {"Authorization" => "Bearer #{api_token}"}
        expect(response).to have_http_status(:ok)
      end

      add_bills.call(4, 2)
      large = sql_response_measurement do
        get bills_path, headers: {"Authorization" => "Bearer #{api_token}"}
        expect(response).to have_http_status(:ok)
      end

      expect(large.fetch(:queries)).to eq(small.fetch(:queries)),
        "expected /bills SQL queries to stay flat at #{small.fetch(:queries)} as bills grow, got #{large.fetch(:queries)} (top: #{large.fetch(:top_fingerprint)})"
    end

    it "executes no user lookups and keeps SQL queries flat on unauthenticated /bills as bills grow" do
      sway_locale, _user = setup
      session_hash.clear

      user_select_count = lambda do |&block|
        count = 0
        subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          sql = payload[:sql].to_s
          next if /SCHEMA|TRANSACTION/.match?(payload[:name].to_s)

          count += 1 if sql.match?(/\bSELECT\b.*\bFROM\s+["'`]?users["'`]?/i)
        end
        begin
          block.call
        ensure
          ActiveSupport::Notifications.unsubscribe(subscription)
        end
        count
      end

      add_bills = lambda do |count, from|
        count.times do |idx|
          bill = create(:bill, sway_locale:, summary: "Unauthenticated summary #{from + idx}")
          bill_score = create(:bill_score, bill:)
          add_bill_score_districts(count: 2, from: (from + idx) * 10, sway_locale:, bill_score:)
        end
      end

      add_bills.call(2, 0)
      small_user_queries = 0
      small = sql_response_measurement do
        small_user_queries = user_select_count.call do
          get bills_path, headers: {"Accept" => "application/json"}
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body.fetch("bills").length).to eq(2)
        end
      end

      add_bills.call(4, 2)
      large_user_queries = 0
      large = sql_response_measurement do
        large_user_queries = user_select_count.call do
          get bills_path, headers: {"Accept" => "application/json"}
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body.fetch("bills").length).to eq(6)
        end
      end

      expect(small_user_queries).to eq(0)
      expect(large_user_queries).to eq(0)
      expect(large.fetch(:queries)).to eq(small.fetch(:queries)),
        "expected unauthenticated /bills SQL queries to stay flat at #{small.fetch(:queries)} as bills grow, got #{large.fetch(:queries)} (top: #{large.fetch(:top_fingerprint)})"
    end
  end

  describe "unread Bill page props" do
    it "keeps initial Inertia bytes flat while default bearer JSON grows with correlated votes" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale:)
      token = "bill-vote-payload-measurement-token"
      create(:api_key, token:, bearer: user)

      add_correlated_bill_votes(count: 2, from: 0, sway_locale:, bill:)
      browser_small = mirrored_asset_response_measurement do
        get bill_path(bill)
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL)
      end
      json_small = mirrored_asset_response_measurement do
        get bill_path(bill), headers: {"Authorization" => "Bearer #{token}"}
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
      end
      expect(response.parsed_body.fetch("legislator_votes").length).to eq(2)

      add_correlated_bill_votes(count: 2, from: 2, sway_locale:, bill:)
      browser_large = mirrored_asset_response_measurement do
        get bill_path(bill)
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL)
      end
      json_large = mirrored_asset_response_measurement do
        get bill_path(bill), headers: {"Authorization" => "Bearer #{token}"}
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
      end
      expect(response.parsed_body.fetch("legislator_votes").length).to eq(4)

      expect(browser_large.fetch(:response_bytes)).to eq(browser_small.fetch(:response_bytes)),
        "expected initial Inertia bytes #{browser_large.fetch(:response_bytes)} to stay flat at #{browser_small.fetch(:response_bytes)} as correlated bill votes grow"
      expect(json_large.fetch(:response_bytes)).to be > json_small.fetch(:response_bytes),
        "expected default bearer JSON bytes #{json_large.fetch(:response_bytes)} to grow beyond #{json_small.fetch(:response_bytes)} with its serialized votes"
    end
  end

  describe "bill score district serialization" do
    it "keeps district queries flat as scored districts grow" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale:)
      bill_score = create(:bill_score, bill:)
      add_bill_score_districts(count: 2, from: 0, sway_locale:, bill_score:)

      small = bill_score_district_query_counts do
        get bill_path(bill)
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL)
        expect(inertia.props.dig(:bill_score, "districts").length).to eq(2)
      end

      add_bill_score_districts(count: 2, from: 2, sway_locale:, bill_score:)
      large = bill_score_district_query_counts do
        get bill_path(bill)
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL)
        expect(inertia.props.dig(:bill_score, "districts").length).to eq(4)
      end

      expect(small.fetch(:bill_score_districts)).to be_positive
      expect(small.fetch(:districts)).to be_positive
      expect(large.fetch(:districts)).to eq(small.fetch(:districts)),
        "expected bill-score district lookups to stay flat at #{small.fetch(:districts)} as scored districts grow, got #{large.fetch(:districts)}"
    end
  end

  describe "Sway::SqlQueryTelemetry" do
    it "normalizes ASCII-8BIT and invalid UTF-8 SQL bytes without raising" do
      binary_sql = (+"SELECT * FROM \"users\" WHERE \"blob\" = '\xFF\xFE' AND \"id\" = 42").force_encoding(Encoding::ASCII_8BIT)

      fp = Sway::SqlQueryTelemetry.fingerprint(binary_sql)

      expect(fp.encoding).to eq(Encoding::UTF_8)
      expect(fp).to be_valid_encoding
      expect(fp).to eq("SELECT * FROM \"users\" WHERE \"blob\" = ? AND \"id\" = ?")
    end

    it "normalizes negative integers, SQLite hex literals, and long IN clauses exceeding 4,096 chars" do
      negative_in = "SELECT * FROM \"bills\" WHERE \"id\" IN (-1, -2, -3)"
      expect(Sway::SqlQueryTelemetry.fingerprint(negative_in)).to eq(
        "SELECT * FROM \"bills\" WHERE \"id\" IN (?)"
      )

      hex_sql = "SELECT * FROM \"active_storage_blobs\" WHERE \"checksum\" = x'deadbeef' AND \"raw\" = X'CAFE01'"
      expect(Sway::SqlQueryTelemetry.fingerprint(hex_sql)).to eq(
        "SELECT * FROM \"active_storage_blobs\" WHERE \"checksum\" = ? AND \"raw\" = ?"
      )

      long_ids = (1..1200).to_a.join(", ")
      long_in_sql = "SELECT \"bills\".* FROM \"bills\" WHERE \"bills\".\"id\" IN (#{long_ids}) ORDER BY \"bills\".\"id\" ASC"
      expect(long_in_sql.length).to be > Sway::SqlQueryTelemetry::MAX_SQL_FINGERPRINT_LENGTH
      expect(Sway::SqlQueryTelemetry.fingerprint(long_in_sql)).to eq(
        "SELECT \"bills\".* FROM \"bills\" WHERE \"bills\".\"id\" IN (?) ORDER BY \"bills\".\"id\" ASC"
      )

      prefix = "SELECT * FROM \"active_storage_blobs\" WHERE \"note\" = "
      padding = "a" * (Sway::SqlQueryTelemetry::MAX_SQL_INPUT_LENGTH - prefix.length - 10)
      truncated_escaped_quote_sql = "#{prefix}'#{padding}''unclosed_tail_after_limit'"
      expect(truncated_escaped_quote_sql.length).to be > Sway::SqlQueryTelemetry::MAX_SQL_INPUT_LENGTH
      expect(Sway::SqlQueryTelemetry.fingerprint(truncated_escaped_quote_sql)).to eq(
        "SELECT * FROM \"active_storage_blobs\" WHERE \"note\" = ?"
      )

      truncated_hex_sql = "#{prefix}x'#{padding}deadbeef'"
      expect(truncated_hex_sql.length).to be > Sway::SqlQueryTelemetry::MAX_SQL_INPUT_LENGTH
      expect(Sway::SqlQueryTelemetry.fingerprint(truncated_hex_sql)).to eq(
        "SELECT * FROM \"active_storage_blobs\" WHERE \"note\" = ?"
      )
    end
  end
end
