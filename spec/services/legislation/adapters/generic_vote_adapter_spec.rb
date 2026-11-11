# frozen_string_literal: true

require "rails_helper"

RSpec.describe Legislation::Adapters::GenericVoteAdapter do
  after do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear if defined?(ActiveJob::Base)
  end

  let(:sway_locale) { create(:sway_locale, :congress) }
  let(:bill) { create(:bill, sway_locale: sway_locale, external_id: "HR100") }

  describe "#initialize" do
    it "sets engine and base_url from config" do
      adapter = described_class.new(engine: "generic_csv", base_url: "https://api.example.gov")
      expect(adapter.engine).to eq("generic_csv")
      expect(adapter.base_url).to eq("https://api.example.gov")
    end

    it "initializes from a SwayLocale instance extracting vote_rules" do
      adapter = described_class.new(sway_locale)
      expect(adapter.engine).to eq("congress_dot_gov")
    end

    it "preserves locale rules and merges keyword arguments when initialized with SwayLocale and kwargs" do
      adapter = described_class.new(sway_locale, client: "custom_vote_client", timeout: 15)
      expect(adapter.engine).to eq("congress_dot_gov")
      expect(adapter.retrieval).to eq(:congress_dot_gov)
      expect(adapter.parsing).to eq(:congress_dot_gov)
      expect(adapter.client).to eq("custom_vote_client")
      expect(adapter.config[:timeout]).to eq(15)
      expect(adapter.instance_variable_get(:@sway_locale)).to eq(sway_locale)
    end

    it "preserves rules and merges keyword arguments when initialized with a duck-typed jurisdiction_rules object" do
      duck_rules = instance_double(
        SwayLocale::JurisdictionRules,
        vote_rules: {retrieval: "maryland_general_assembly", parsing: "generic_html", base_url: "https://mgaleg.maryland.gov"},
        legislation_rules: {}
      )
      duck_locale = double("DuckLocale", jurisdiction_rules: duck_rules)
      adapter = described_class.new(duck_locale, client: "md_client", max_retries: 3)
      expect(adapter.retrieval).to eq(:maryland_general_assembly)
      expect(adapter.parsing).to eq(:generic_html)
      expect(adapter.base_url).to eq("https://mgaleg.maryland.gov")
      expect(adapter.client).to eq("md_client")
      expect(adapter.config[:max_retries]).to eq(3)
    end

    it "preserves rules and merges keyword arguments when initialized with an object responding directly to vote_rules" do
      duck_vote = double("DirectVoteRules", vote_rules: {retrieval: "legistar", parsing: "legistar"})
      adapter = described_class.new(duck_vote, client: "baltimore", active: true)
      expect(adapter.retrieval).to eq(:legistar)
      expect(adapter.parsing).to eq(:legistar)
      expect(adapter.client).to eq("baltimore")
      expect(adapter.config[:active]).to eq(true)
    end

    it "initializes correctly with keyword arguments only" do
      adapter = described_class.new(retrieval: :generic_rest, parsing: :generic_json, client: "rest_client")
      expect(adapter.retrieval).to eq(:generic_rest)
      expect(adapter.parsing).to eq(:generic_json)
      expect(adapter.client).to eq("rest_client")
    end
  end

  describe "#fetch_votes" do
    context "when engine is manual or unavailable" do
      let(:adapter) { described_class.new(engine: "manual") }

      it "returns an empty array" do
        expect(adapter.fetch_votes(bill)).to eq([])
      end
    end

    context "when bill is nil" do
      let(:adapter) { described_class.new(engine: "generic_csv") }

      it "returns an empty array" do
        expect(adapter.fetch_votes(nil)).to eq([])
      end
    end

    context "when engine is congress_dot_gov with house roll call" do
      let(:adapter) { described_class.new(engine: "congress_dot_gov") }
      let!(:vote_record) { create(:vote, bill: bill, house_roll_call_vote_number: 42, senate_roll_call_vote_number: nil) }

      before do
        bill.update!(house_vote_date_time_utc: Time.zone.parse("2026-02-10"))
        house_scraper = instance_double(Scraper::Congress::House::LegislatorVotes)
        allow(Scraper::Congress::House::LegislatorVotes).to receive(:new).and_return(house_scraper)
        allow(house_scraper).to receive(:process).and_return([
          Scraper::LegislatorVote.new(
            external_id: "G000607",
            support: "FOR",
            first_name: "James",
            last_name: "Gallagher",
            party: "Republican",
            state_code: "CA"
          )
        ])
        allow(house_scraper).to receive(:identity).and_return(
          instance_double(Scraper::Congress::RollCallIdentity, taken_on?: true, names?: true, voted_on: Date.parse("2026-02-10"), question: "On Passage", title: "HR100", to_h: {})
        )
      end

      it "returns normalized vote hashes" do
        votes = adapter.fetch_votes(bill)
        expect(votes.size).to eq(1)
        expect(votes.first[:legislator_external_id]).to eq("G000607")
        expect(votes.first[:vote_value]).to eq("FOR")
        expect(votes.first[:chamber]).to eq("house")
      end
    end

    context "when engine is open_states" do
      let(:adapter) { described_class.new(engine: "open_states") }
      let!(:vote_record) { create(:vote, bill: bill, senate_roll_call_vote_number: 15, house_roll_call_vote_number: nil) }

      before do
        bill.update!(senate_vote_date_time_utc: Time.zone.parse("2026-03-01"), chamber: "senate")
        os_scraper = instance_double(Scraper::OpenStates::Senate::LegislatorVotes)
        allow(Scraper::OpenStates::Senate::LegislatorVotes).to receive(:new).and_return(os_scraper)
        allow(os_scraper).to receive(:process).and_return([
          Scraper::LegislatorVote.new(
            external_id: "ocd-person/777",
            support: "AGAINST",
            first_name: "Bob",
            last_name: "Jones",
            party: "Democratic",
            state_code: "MD"
          )
        ])
      end

      it "returns normalized vote hashes" do
        votes = adapter.fetch_votes(bill)
        expect(votes.size).to eq(1)
        expect(votes.first[:legislator_external_id]).to eq("ocd-person/777")
        expect(votes.first[:vote_value]).to eq("AGAINST")
        expect(votes.first[:chamber]).to eq("senate")
      end

      it "does not hijack to Maryland scraper even when region_code is MD (TASK-ok5ox.43: Remove jurisdiction hardcoding from GenericVoteAdapter)" do
        md_locale = create(:sway_locale, :maryland)
        md_bill = create(:bill, sway_locale: md_locale, external_id: "SB10")
        create(:vote, bill: md_bill, senate_roll_call_vote_number: 5, house_roll_call_vote_number: nil)
        md_bill.update!(senate_vote_date_time_utc: Time.zone.parse("2026-03-01"))

        os_scraper = instance_double(Scraper::OpenStates::Senate::LegislatorVotes)
        allow(Scraper::OpenStates::Senate::LegislatorVotes).to receive(:new).and_return(os_scraper)
        allow(os_scraper).to receive(:process).and_return([])
        allow(Scraper::Maryland::LegislatorVotes).to receive(:new)

        adapter.fetch_votes(md_bill)

        expect(Scraper::OpenStates::Senate::LegislatorVotes).to have_received(:new)
        expect(Scraper::Maryland::LegislatorVotes).not_to have_received(:new)
      end
    end

    context "when routing generic HTML roll-call scraper votes" do
      let(:adapter) { described_class.new(engine: "generic_html") }

      before do
        @md_locale = create(:sway_locale, :maryland)
        @md_bill = create(:bill, sway_locale: @md_locale, external_id: "SB10", chamber: "senate")
        create(:vote, bill: @md_bill, senate_roll_call_vote_number: 10, house_roll_call_vote_number: nil)
        @md_bill.update!(senate_vote_date_time_utc: Time.zone.parse("2026-03-01"))

        @mock_scraper = instance_double(Scraper::Maryland::LegislatorVotes)
        allow(Scraper::Maryland::LegislatorVotes).to receive(:new).and_return(@mock_scraper)
        allow(@mock_scraper).to receive(:process).and_return([
          Scraper::LegislatorVote.new(
            external_id: "MD-LEG-1",
            support: "FOR",
            first_name: "Jane",
            last_name: "Smith",
            party: "Democratic",
            state_code: "MD"
          )
        ])
      end

      it "routes to fetch_html_votes and returns normalized vote hashes via generic_html engine" do
        votes = adapter.fetch_votes(@md_bill)
        expect(votes.size).to eq(1)
        expect(votes.first[:legislator_external_id]).to eq("MD-LEG-1")
        expect(votes.first[:vote_value]).to eq("FOR")
        expect(votes.first[:chamber]).to eq("senate")
      end

      it "supports alias fetch_maryland_votes for backwards compatibility" do
        votes = adapter.send(:fetch_maryland_votes, @md_bill)
        expect(votes.size).to eq(1)
        expect(votes.first[:legislator_external_id]).to eq("MD-LEG-1")
      end

      it "dynamically determines :generic_html from declared_jurisdiction_rules parsing_for(:vote)" do
        rules = instance_double(SwayLocale::JurisdictionRules, parsing_for: "generic_html", retrieval_for: nil)
        allow(@md_locale).to receive(:declared_jurisdiction_rules).and_return(rules)

        default_adapter = described_class.new({})
        expect(default_adapter.determine_retrieval(@md_bill)).to eq(:generic_html)

        votes = default_adapter.fetch_votes(@md_bill)
        expect(votes.size).to eq(1)
        expect(votes.first[:legislator_external_id]).to eq("MD-LEG-1")
      end

      it "dynamically determines :generic_html from declared_jurisdiction_rules retrieval_for(:vote)" do
        rules = instance_double(SwayLocale::JurisdictionRules, parsing_for: nil, retrieval_for: "generic_html")
        allow(@md_locale).to receive(:declared_jurisdiction_rules).and_return(rules)

        default_adapter = described_class.new({})
        expect(default_adapter.determine_retrieval(@md_bill)).to eq(:generic_html)
      end

      it "maps legacy engine maryland_general_assembly to :generic_html via determine_retrieval" do
        mga_adapter = described_class.new(engine: "maryland_general_assembly")
        expect(mga_adapter.determine_retrieval(@md_bill)).to eq(:generic_html)

        votes = mga_adapter.fetch_votes(@md_bill)
        expect(votes.size).to eq(1)
        expect(votes.first[:legislator_external_id]).to eq("MD-LEG-1")
      end
    end

    context "when engine is generic_rest" do
      let(:adapter) do
        described_class.new(
          engine: "generic_rest",
          base_url: "https://api.example.gov",
          endpoints: {votes: "/bills/:external_id/votes"},
          metadata_mapping: {
            legislator_external_id: "$.voter_id",
            vote_value: "$.position",
            voted_on: "$.date",
            chamber: "$.chamber"
          }
        )
      end
      let(:payload) do
        [
          {voter_id: "V100", position: "yea", date: "2026-02-20", chamber: "house"}
        ].to_json
      end

      it "fetches votes from REST endpoint and normalizes them" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/bills/HR100/votes") { [200, {"content-type" => "application/json"}, payload] }
        conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }

        votes = adapter.fetch_votes(bill, connection: conn)
        expect(votes.size).to eq(1)
        first = votes.first
        expect(first[:legislator_external_id]).to eq("V100")
        expect(first[:vote_value]).to eq("yea")
        expect(first[:chamber]).to eq("house")
      end
    end

    context "when upstream REST response is empty or malformed" do
      let(:adapter) do
        described_class.new(
          engine: "generic_rest",
          base_url: "https://api.example.gov",
          endpoints: {votes: "/bills/:external_id/votes"},
          metadata_mapping: {
            legislator_external_id: "$.voter_id",
            vote_value: "$.position"
          }
        )
      end

      it "returns an empty array on empty JSON object response {} without phantom votes" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/bills/HR100/votes") { [200, {"content-type" => "application/json"}, "{}"] }
        conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }

        votes = adapter.fetch_votes(bill, connection: conn)
        expect(votes).to eq([])
      end

      it "returns an empty array when votes key is null or empty" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/bills/HR100/votes") { [200, {"content-type" => "application/json"}, '{"votes": null}'] }
        conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }

        expect(adapter.fetch_votes(bill, connection: conn)).to eq([])
      end

      it "returns an empty array on empty string body" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/bills/HR100/votes") { [200, {"content-type" => "application/json"}, ""] }
        conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }

        expect(adapter.fetch_votes(bill, connection: conn)).to eq([])
      end

      it "safely handles sparse arrays and non-hash elements without crashing" do
        sparse_payload = [
          {"voter_id" => "V100", "position" => "yea"},
          nil,
          {},
          "invalid_string"
        ].to_json

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/bills/HR100/votes") { [200, {"content-type" => "application/json"}, sparse_payload] }
        conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }

        votes = adapter.fetch_votes(bill, connection: conn)
        expect(votes.size).to eq(1)
        expect(votes.first[:legislator_external_id]).to eq("V100")
        expect(votes.first[:vote_value]).to eq("yea")
      end

      it "handles single vote item returned as a top-level JSON object" do
        single_payload = {"voter_id" => "V100", "position" => "yea", "chamber" => "house"}.to_json
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/bills/HR100/votes") { [200, {"content-type" => "application/json"}, single_payload] }
        conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }

        votes = adapter.fetch_votes(bill, connection: conn)
        expect(votes.size).to eq(1)
        expect(votes.first[:legislator_external_id]).to eq("V100")
        expect(votes.first[:vote_value]).to eq("yea")
        expect(votes.first[:chamber]).to eq("house")
      end
    end
  end

  describe "TASK-ok5ox.48: Decoupled retrieval and parsing configuration" do
    describe "initialization with decoupled retrieval and parsing" do
      it "initializes from explicit retrieval and parsing keys" do
        adapter = described_class.new({
          retrieval: "generic_rest",
          parsing: "generic_json",
          base_url: "https://api.example.gov"
        })
        expect(adapter.retrieval).to eq(:generic_rest)
        expect(adapter.parsing).to eq(:generic_json)
        expect(adapter.engine).to eq("generic_rest")
      end

      it "falls back retrieval and parsing to engine when explicit keys are absent" do
        adapter = described_class.new(engine: "open_states")
        expect(adapter.engine).to eq("open_states")
        expect(adapter.retrieval).to eq(:open_states)
        expect(adapter.parsing).to eq(:open_states)
      end

      it "supports alias keys retrieval_strategy and parser_format" do
        adapter = described_class.new({
          retrieval_strategy: "open_states",
          parser_format: "generic_json"
        })
        expect(adapter.retrieval).to eq(:open_states)
        expect(adapter.parsing).to eq(:generic_json)
        expect(adapter.engine).to eq("open_states")
      end

      it "prioritizes explicit retrieval over conflicting engine" do
        adapter = described_class.new({
          engine: "manual",
          retrieval: "generic_rest",
          parsing: "generic_json",
          base_url: "https://api.example.gov"
        })
        expect(adapter.retrieval).to eq(:generic_rest)
        expect(adapter.parsing).to eq(:generic_json)
      end

      it "extracts retrieval and parsing from SwayLocale instance" do
        adapter = described_class.new(sway_locale)
        expect(adapter.retrieval).to eq(:congress_dot_gov)
        expect(adapter.parsing).to eq(:congress_dot_gov)
      end
    end

    describe "precedence and short-circuiting in #fetch_votes" do
      it "returns empty array when retrieval is :unavailable even if engine is active" do
        adapter = described_class.new({
          engine: "generic_rest",
          retrieval: "unavailable"
        })
        expect(adapter.fetch_votes(bill)).to eq([])
      end

      it "fetches votes when retrieval is active even if engine is :manual" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/bills/HR100/votes") { [200, {"content-type" => "application/json"}, '[{"voter_id": "V1", "position": "yea"}]'] }
        conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }

        adapter = described_class.new({
          engine: "manual",
          retrieval: "generic_rest",
          parsing: "generic_json",
          base_url: "https://api.example.gov",
          endpoints: {votes: "/bills/:external_id/votes"},
          metadata_mapping: {legislator_external_id: "$.voter_id", vote_value: "$.position"}
        }, connection: conn)

        votes = adapter.fetch_votes(bill)
        expect(votes.size).to eq(1)
        expect(votes.first[:legislator_external_id]).to eq("V1")
      end
    end

    describe "Legistar client isolation and multi-locale scoping" do
      it "resolves Legistar client from target_locale vote_rules" do
        locale = instance_double(
          SwayLocale,
          name: "annapolis-maryland-united_states",
          city: "annapolis",
          jurisdiction_rules: instance_double(
            SwayLocale::JurisdictionRules,
            vote_rules: {retrieval: "legistar", client: "annapolis"},
            legislation_rules: {client: "annapolis"}
          )
        )
        adapter = described_class.new({retrieval: "legistar", client: "baltimore"})
        expect(adapter.legistar_client(locale).client).to eq("annapolis")
      end

      it "raises ArgumentError when client cannot be resolved (no Baltimore fallback)" do
        adapter = described_class.new({retrieval: "legistar"})
        expect { adapter.legistar_client }.to raise_error(ArgumentError, /No client configured for Legistar vote adapter/)
      end
    end

    describe "#parse_generic_votes_payload deep JSONPath and resilience" do
      let(:adapter) do
        described_class.new(
          retrieval: "generic_rest",
          parsing: "generic_json",
          metadata_mapping: {
            legislator_external_id: "$.voter.id",
            vote_value: "$.decision.cast",
            voted_on: "$.decision.date",
            chamber: "$.body.name"
          }
        )
      end

      it "parses deep JSONPath fields, handles invalid dates, and ignores malformed JSON or blank entries" do
        payload = {
          votes: [
            {voter: {id: "L100"}, decision: {cast: "Yea", date: "2026-03-15"}, body: {name: "senate"}},
            {voter: {id: "L200"}, decision: {cast: "Nay", date: "not-a-valid-date"}, body: {name: "house"}},
            {decision: {date: "2026-01-01"}}
          ]
        }.to_json

        parsed = adapter.send(:parse_generic_votes_payload, payload)
        expect(parsed.size).to eq(2)
        expect(parsed.first).to include(
          legislator_external_id: "L100",
          vote_value: "Yea",
          voted_on: Date.new(2026, 3, 15),
          chamber: "senate"
        )
        expect(parsed.second[:legislator_external_id]).to eq("L200")
        expect(parsed.second[:voted_on]).to be_nil
        expect(adapter.send(:parse_generic_votes_payload, "INVALID_JSON_HERE")).to eq([])
      end

      it "initializes cleanly with retrieval: :congress_dot_gov and parsing: :generic_csv" do
        csv_adapter = described_class.new(retrieval: :congress_dot_gov, parsing: :generic_csv)
        expect(csv_adapter.retrieval).to eq(:congress_dot_gov)
        expect(csv_adapter.parsing).to eq(:generic_csv)
      end
    end
  end
end
