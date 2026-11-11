# frozen_string_literal: true

require "rails_helper"

RSpec.describe Legislation::Adapters::GenericRosterAdapter do
  let(:sway_locale) { create(:sway_locale, :congress) }

  describe "#initialize" do
    it "parses engine, base_url, and metadata_mapping from symbol and string keys" do
      config = {
        "engine" => "generic_rest",
        "base_url" => "https://api.example.gov/v1",
        "metadata_mapping" => {"external_id" => "$.id", "full_name" => "$.name"}
      }
      adapter = described_class.new(config)
      expect(adapter.engine).to eq("generic_rest")
      expect(adapter.base_url).to eq("https://api.example.gov/v1")
      expect(adapter.metadata_mapping).to eq({external_id: "$.id", full_name: "$.name"})
    end

    it "initializes from a SwayLocale instance extracting roster_rules" do
      adapter = described_class.new(sway_locale)
      expect(adapter.engine).to eq("congress_dot_gov")
    end

    it "preserves locale rules and merges keyword arguments when initialized with SwayLocale and kwargs" do
      adapter = described_class.new(sway_locale, client: "custom_override", extra_flag: true)
      expect(adapter.engine).to eq("congress_dot_gov")
      expect(adapter.retrieval).to eq(:congress_dot_gov)
      expect(adapter.parsing).to eq(:congress_dot_gov)
      expect(adapter.client).to eq("custom_override")
      expect(adapter.config[:extra_flag]).to eq(true)
      expect(adapter.instance_variable_get(:@sway_locale)).to eq(sway_locale)
    end

    it "preserves rules and merges keyword arguments when initialized with a duck-typed jurisdiction_rules object" do
      duck_rules = instance_double(
        SwayLocale::JurisdictionRules,
        roster_rules: {retrieval: "open_states", parsing: "open_states", base_url: "https://openstates.org/api/v3"},
        legislation_rules: {}
      )
      duck_locale = double("DuckLocale", jurisdiction_rules: duck_rules)
      adapter = described_class.new(duck_locale, client: "duck_client", timeout: 10)
      expect(adapter.retrieval).to eq(:open_states)
      expect(adapter.parsing).to eq(:open_states)
      expect(adapter.base_url).to eq("https://openstates.org/api/v3")
      expect(adapter.client).to eq("duck_client")
      expect(adapter.config[:timeout]).to eq(10)
    end

    it "preserves rules and merges keyword arguments when initialized with an object responding directly to roster_rules" do
      duck_roster = double("DirectRosterRules", roster_rules: {retrieval: "legistar", parsing: "legistar"})
      adapter = described_class.new(duck_roster, client: "baltimore", test_mode: true)
      expect(adapter.retrieval).to eq(:legistar)
      expect(adapter.parsing).to eq(:legistar)
      expect(adapter.client).to eq("baltimore")
      expect(adapter.config[:test_mode]).to eq(true)
    end

    it "initializes correctly with keyword arguments only" do
      adapter = described_class.new(retrieval: :generic_rest, parsing: :generic_json, client: "my_client")
      expect(adapter.retrieval).to eq(:generic_rest)
      expect(adapter.parsing).to eq(:generic_json)
      expect(adapter.client).to eq("my_client")
    end

    describe "evidence attribution readers" do
      it "extracts attribution from raw config hash with string or symbol keys" do
        adapter = described_class.new({
          "evidence_publisher" => "custom.gov",
          "evidence_jurisdiction" => "custom_jurisdiction",
          "evidence_source_url" => "https://custom.gov/roster"
        })
        expect(adapter.evidence_publisher).to eq("custom.gov")
        expect(adapter.evidence_jurisdiction).to eq("custom_jurisdiction")
        expect(adapter.evidence_source_url).to eq("https://custom.gov/roster")
      end

      it "extracts attribution from nested roster_rules in config hash" do
        adapter = described_class.new({
          roster_rules: {
            evidence_publisher: "nested.gov",
            evidence_jurisdiction: "nested_jurisdiction",
            evidence_source_url: "https://nested.gov/roster"
          }
        })
        expect(adapter.evidence_publisher).to eq("nested.gov")
        expect(adapter.evidence_jurisdiction).to eq("nested_jurisdiction")
        expect(adapter.evidence_source_url).to eq("https://nested.gov/roster")
      end

      it "extracts attribution from SwayLocale jurisdiction_rules" do
        duck_rules = instance_double(
          SwayLocale::JurisdictionRules,
          roster_rules: {
            evidence_publisher: "openstates.org",
            evidence_jurisdiction: "maryland-maryland-united_states",
            evidence_source_url: "https://v3.openstates.org/people"
          },
          legislation_rules: {}
        )
        duck_locale = instance_double(SwayLocale, jurisdiction_rules: duck_rules)
        adapter = described_class.new(duck_locale)
        expect(adapter.evidence_publisher).to eq("openstates.org")
        expect(adapter.evidence_jurisdiction).to eq("maryland-maryland-united_states")
        expect(adapter.evidence_source_url).to eq("https://v3.openstates.org/people")
      end

      it "allows keyword arguments to override or provide attribution" do
        adapter = described_class.new(
          {evidence_publisher: "original.gov", evidence_jurisdiction: "original_jur"},
          evidence_publisher: "override.gov",
          evidence_source_url: "https://override.gov/roster"
        )
        expect(adapter.evidence_publisher).to eq("override.gov")
        expect(adapter.evidence_jurisdiction).to eq("original_jur")
        expect(adapter.evidence_source_url).to eq("https://override.gov/roster")
      end

      it "treats whitespace-only and blank strings in top-level or nested roster_rules as nil" do
        top_adapter = described_class.new({
          evidence_publisher: "   \t\n  ",
          evidence_jurisdiction: "",
          evidence_source_url: nil
        })
        expect(top_adapter.evidence_publisher).to be_nil
        expect(top_adapter.evidence_jurisdiction).to be_nil
        expect(top_adapter.evidence_source_url).to be_nil

        nested_adapter = described_class.new({
          roster_rules: {
            evidence_publisher: "  ",
            evidence_jurisdiction: "",
            evidence_source_url: "\n\t"
          }
        })
        expect(nested_adapter.evidence_publisher).to be_nil
        expect(nested_adapter.evidence_jurisdiction).to be_nil
        expect(nested_adapter.evidence_source_url).to be_nil
      end
    end
  end

  describe "#fetch_roster" do
    context "when engine is unavailable" do
      let(:adapter) { described_class.new(engine: "unavailable") }

      it "returns an empty array without network calls" do
        expect(adapter.fetch_roster(sway_locale: sway_locale)).to eq([])
      end
    end

    context "legacy roster_source decoupling" do
      it "does not check roster_source on sway_locale during fetch_roster" do
        adapter = described_class.new(engine: "curated")
        strict_locale = instance_double(
          SwayLocale,
          name: "strict_locale",
          jurisdiction_rules: double("JurisdictionRules")
        )
        expect(adapter.fetch_roster(sway_locale: strict_locale)).to eq([])
      end
    end

    context "when engine is congress_dot_gov" do
      let(:adapter) { described_class.new(engine: "congress_dot_gov", base_url: "https://api.congress.gov/v3") }

      before do
        allow(EnvSecret).to receive(:congress_gov_api_key!).and_return("mock_congress_key")
      end

      it "fetches members and returns normalized hashes retaining upstream keys" do
        member_payload = {
          members: [
            {
              bioguideId: "A000360",
              name: "Alexander, Lamar",
              firstName: "Lamar",
              lastName: "Alexander",
              partyName: "Republican",
              state: "Tennessee",
              district: nil,
              depiction: {imageUrl: "https://example.com/alexander.jpg"}
            }
          ],
          pagination: {count: 1}
        }.to_json

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/v3/member") do
          [200, {"content-type" => "application/json"}, member_payload]
        end
        conn = Faraday.new("https://api.congress.gov/v3") { |f| f.adapter :test, stubs }

        roster = adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
        expect(roster.size).to eq(1)
        entry = roster.first
        expect(entry[:external_id]).to eq("A000360")
        expect(entry[:full_name]).to eq("Alexander, Lamar")
        expect(entry[:party]).to eq("Republican")
        expect(entry[:photo_url]).to eq("https://example.com/alexander.jpg")
        expect(entry[:bioguideId]).to eq("A000360")
        expect(entry[:state]).to eq("Tennessee")
      end

      it "safely extracts photo_url when depiction is a flat String URL" do
        member_payload = {
          members: [
            {
              bioguideId: "B000001",
              name: "Senator Flat",
              depiction: "https://example.com/flat_alexander.jpg"
            }
          ]
        }.to_json

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/v3/member") { [200, {"content-type" => "application/json"}, member_payload] }
        conn = Faraday.new("https://api.congress.gov/v3") { |f| f.adapter :test, stubs }

        roster = adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
        expect(roster.size).to eq(1)
        expect(roster.first[:photo_url]).to eq("https://example.com/flat_alexander.jpg")
      end

      it "filters out null members and empty hashes in members array without error" do
        member_payload = {
          members: [
            nil,
            {},
            {
              bioguideId: "B000002",
              name: "Senator Valid"
            }
          ]
        }.to_json

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/v3/member") { [200, {"content-type" => "application/json"}, member_payload] }
        conn = Faraday.new("https://api.congress.gov/v3") { |f| f.adapter :test, stubs }

        roster = adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
        expect(roster.size).to eq(1)
        expect(roster.first[:external_id]).to eq("B000002")
      end

      it "returns an empty array when response body is empty JSON object" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/v3/member") { [200, {"content-type" => "application/json"}, "{}"] }
        conn = Faraday.new("https://api.congress.gov/v3") { |f| f.adapter :test, stubs }

        expect(adapter.fetch_roster(sway_locale: sway_locale, connection: conn)).to eq([])
      end
    end

    context "when engine is open_states" do
      let(:adapter) do
        described_class.new(
          engine: "open_states",
          base_url: "https://v3.openstates.org",
          jurisdiction: "Maryland"
        )
      end

      before do
        allow(EnvSecret).to receive(:open_states_api_key!).and_return("mock_open_states_key")
      end

      it "fetches legislators and returns normalized hashes" do
        people_payload = {
          results: [
            {
              id: "ocd-person/12345",
              name: "Jane Smith",
              given_name: "Jane",
              family_name: "Smith",
              party: "Democratic",
              current_role: {title: "Senator", district: "42", org_classification: "upper"}
            }
          ],
          pagination: {max_page: 1}
        }.to_json

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/people") do
          [200, {"content-type" => "application/json"}, people_payload]
        end
        conn = Faraday.new("https://v3.openstates.org") { |f| f.adapter :test, stubs }

        roster = adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
        expect(roster.size).to eq(1)
        entry = roster.first
        expect(entry[:external_id]).to eq("ocd-person/12345")
        expect(entry[:full_name]).to eq("Jane Smith")
        expect(entry[:district]).to eq("42")
        expect(entry[:party]).to eq("Democratic")
        expect(entry[:id]).to eq("ocd-person/12345")
      end

      it "filters out null items and handles non-hash current_role in results array" do
        people_payload = {
          results: [
            nil,
            {},
            {
              id: "ocd-person/valid",
              name: "Valid Person",
              current_role: nil
            }
          ]
        }.to_json

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/people") { [200, {"content-type" => "application/json"}, people_payload] }
        conn = Faraday.new("https://v3.openstates.org") { |f| f.adapter :test, stubs }

        roster = adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
        expect(roster.size).to eq(1)
        expect(roster.first[:external_id]).to eq("ocd-person/valid")
      end

      it "returns an empty array when response body is empty JSON object" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/people") { [200, {"content-type" => "application/json"}, "{}"] }
        conn = Faraday.new("https://v3.openstates.org") { |f| f.adapter :test, stubs }

        expect(adapter.fetch_roster(sway_locale: sway_locale, connection: conn)).to eq([])
      end
    end

    context "with retrieval: 'open_states_api', parsing: 'open_states'" do
      let(:adapter) do
        described_class.new(
          retrieval: "open_states_api",
          parsing: "open_states",
          base_url: "https://v3.openstates.org",
          jurisdiction: "Maryland"
        )
      end

      it "reads API key via EnvSecret.open_states_api_key! and sends X-API-KEY header on every request" do
        allow(EnvSecret).to receive(:open_states_api_key!).and_return("secret_open_states_key")
        captured_headers = {}

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/people") do |env|
          captured_headers = env.request_headers
          [200, {"content-type" => "application/json"}, {results: [], pagination: {max_page: 1}}.to_json]
        end
        conn = Faraday.new("https://v3.openstates.org") { |f| f.adapter :test, stubs }

        adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
        expect(captured_headers["X-API-KEY"]).to eq("secret_open_states_key")
      end

      it "raises KeyError before network requests when OPEN_STATES_API_KEY is whitespace-only" do
        with_env("OPEN_STATES_API_KEY" => "  \n") do
          stubs = Faraday::Adapter::Test::Stubs.new
          conn = Faraday.new("https://v3.openstates.org") { |f| f.adapter :test, stubs }

          expect {
            adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
          }.to raise_error(KeyError, /OPEN_STATES_API_KEY/)
        end
      end

      it "strips trailing newlines from OPEN_STATES_API_KEY in the X-API-KEY header" do
        with_env("OPEN_STATES_API_KEY" => "test-key\n") do
          captured_headers = {}
          stubs = Faraday::Adapter::Test::Stubs.new
          stubs.get("/people") do |env|
            captured_headers = env.request_headers
            [200, {"content-type" => "application/json"}, {results: [], pagination: {max_page: 1}}.to_json]
          end
          conn = Faraday.new("https://v3.openstates.org") { |f| f.adapter :test, stubs }

          adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
          expect(captured_headers["X-API-KEY"]).to eq("test-key")
        end
      end

      it "requests per_page: 50 and paginates across 1..max_page concatenating all results" do
        allow(EnvSecret).to receive(:open_states_api_key!).and_return("mock_key")
        requested_pages = []

        page1_payload = {
          results: [{id: "ocd-person/1", name: "Person 1"}],
          pagination: {page: 1, per_page: 50, max_page: 2}
        }.to_json

        page2_payload = {
          results: [{id: "ocd-person/2", name: "Person 2"}],
          pagination: {page: 2, per_page: 50, max_page: 2}
        }.to_json

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/people") do |env|
          page = env.params["page"].to_i
          per_page = env.params["per_page"].to_i
          expect(per_page).to eq(50)
          requested_pages << page
          payload = (page == 1) ? page1_payload : page2_payload
          [200, {"content-type" => "application/json"}, payload]
        end
        conn = Faraday.new("https://v3.openstates.org") { |f| f.adapter :test, stubs }

        roster = adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
        expect(requested_pages).to eq([1, 2])
        expect(roster.pluck(:external_id)).to eq(["ocd-person/1", "ocd-person/2"])
      end

      it "preserves upstream OpenStates keys alongside normalized adapter keys in parse_open_states_members" do
        upstream_member = {
          "id" => "ocd-person/123",
          "name" => "Jane Doe",
          "given_name" => "Jane",
          "family_name" => "Doe",
          "current_role" => {"title" => "Delegate", "district" => "42A", "org_classification" => "lower"},
          "jurisdiction" => "Maryland",
          "party" => "Democratic",
          "image" => "https://example.com/jane.jpg",
          "email" => "jane.doe@mlis.state.md.us",
          "openstates_url" => "https://openstates.org/person/jane-doe-123/"
        }

        parsed = adapter.parse_open_states_members([upstream_member])
        entry = parsed.first

        expect(entry["id"]).to eq("ocd-person/123")
        expect(entry["given_name"]).to eq("Jane")
        expect(entry["family_name"]).to eq("Doe")
        expect(entry["current_role"]).to eq({"title" => "Delegate", "district" => "42A", "org_classification" => "lower"})
        expect(entry["jurisdiction"]).to eq("Maryland")
        expect(entry["party"]).to eq("Democratic")
        expect(entry["image"]).to eq("https://example.com/jane.jpg")
        expect(entry["email"]).to eq("jane.doe@mlis.state.md.us")
        expect(entry["openstates_url"]).to eq("https://openstates.org/person/jane-doe-123/")

        expect(entry[:external_id]).to eq("ocd-person/123")
        expect(entry[:full_name]).to eq("Jane Doe")
        expect(entry[:first_name]).to eq("Jane")
        expect(entry[:last_name]).to eq("Doe")
        expect(entry[:party]).to eq("Democratic")
        expect(entry[:district]).to eq("42A")
        expect(entry[:chamber]).to eq("lower")
        expect(entry[:title]).to eq("Delegate")
        expect(entry[:photo_url]).to eq("https://example.com/jane.jpg")
        expect(entry[:raw_data]).to eq(upstream_member)

        stringified = entry.deep_stringify_keys.except("raw_data")
        expect(stringified["openstates_url"]).to eq("https://openstates.org/person/jane-doe-123/")
        expect(stringified["current_role"]).to be_present
      end
    end

    context "with retrieval: 'congress_api', parsing: 'congress_dot_gov'" do
      let(:adapter) do
        described_class.new(
          retrieval: "congress_api",
          parsing: "congress_dot_gov",
          base_url: "https://api.congress.gov/v3"
        )
      end

      it "requests /v3/member with api_key, format, currentMember, limit: 250, and offset pagination" do
        allow(EnvSecret).to receive(:congress_gov_api_key!).and_return("secret_congress_key")
        captured_params = []

        page1_members = Array.new(250) { |i| {bioguideId: "H#{i}", name: "Member #{i}"} }
        page2_members = [{bioguideId: "H251", name: "Member 251"}]

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/v3/member") do |env|
          captured_params << env.params.dup
          offset = env.params["offset"].to_i
          members = (offset == 0) ? page1_members : page2_members
          [200, {"content-type" => "application/json"}, {members: members}.to_json]
        end
        conn = Faraday.new("https://api.congress.gov/v3") { |f| f.adapter :test, stubs }

        roster = adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
        expect(roster.size).to eq(251)
        expect(captured_params.size).to eq(2)
        expect(captured_params.first["api_key"]).to eq("secret_congress_key")
        expect(captured_params.first["format"]).to eq("json")
        expect(captured_params.first["currentMember"]).to eq("true")
        expect(captured_params.first["limit"]).to eq("250")
        expect(captured_params.first["offset"]).to eq("0")
        expect(captured_params.second["offset"]).to eq("250")
      end

      it "preserves upstream Congress.gov keys and populates first_name and last_name from name when absent" do
        require Rails.root.join("db", "seeds", "seed_preparers", "legislators", "congress_dot_gov")

        house_member = {
          "bioguideId" => "H000001",
          "name" => "Smith, John",
          "partyName" => "Democratic",
          "state" => "Maryland",
          "district" => 3,
          "depiction" => {"imageUrl" => "https://example.com/john.jpg"},
          "terms" => {"item" => [{"chamber" => "House of Representatives", "startYear" => 2023, "district" => 3, "stateCode" => "MD"}]},
          "updateDate" => "2026-10-10"
        }

        senator_member = {
          "bioguideId" => "S000001",
          "name" => "Jones, Sarah",
          "partyName" => "Republican",
          "state" => "Maryland",
          "depiction" => {"imageUrl" => "https://example.com/sarah.jpg"},
          "terms" => {"item" => [{"chamber" => "Senate", "startYear" => 2023, "stateCode" => "MD"}]},
          "updateDate" => "2026-10-10"
        }

        parsed = adapter.parse_congress_members([house_member, senator_member])
        house_entry = parsed.first
        senator_entry = parsed.second

        expect(house_entry["bioguideId"]).to eq("H000001")
        expect(house_entry["name"]).to eq("Smith, John")
        expect(house_entry["district"]).to eq(3)
        expect(house_entry[:first_name]).to eq("John")
        expect(house_entry[:last_name]).to eq("Smith")
        expect(house_entry["terms"]).to be_present
        expect(house_entry["updateDate"]).to eq("2026-10-10")

        expect(senator_entry["bioguideId"]).to eq("S000001")
        expect(senator_entry["name"]).to eq("Jones, Sarah")
        expect(senator_entry["district"]).to be_nil
        expect(senator_entry[:first_name]).to eq("Sarah")
        expect(senator_entry[:last_name]).to eq("Jones")

        house_prep = SeedPreparers::Legislators::CongressDotGov.new(house_entry.deep_stringify_keys.except("raw_data"), sway_locale)
        expect(house_prep.first_name).to eq("John")
        expect(house_prep.last_name).to eq("Smith")

        senator_prep = SeedPreparers::Legislators::CongressDotGov.new(senator_entry.deep_stringify_keys.except("raw_data"), sway_locale)
        expect(senator_prep.first_name).to eq("Sarah")
        expect(senator_prep.last_name).to eq("Jones")
      end
    end

    context "when engine is generic_rest" do
      let(:adapter) do
        described_class.new(
          engine: "generic_rest",
          base_url: "https://api.example.gov/v1",
          endpoints: {members: "/legislators"},
          metadata_mapping: {
            external_id: "$.id",
            full_name: "$.name",
            party: "$.party_name",
            district: "$.district_no"
          }
        )
      end

      it "fetches and maps fields using metadata_mapping" do
        generic_payload = [
          {
            id: "LEG-001",
            name: "John Doe",
            party_name: "Independent",
            district_no: "District 5"
          }
        ].to_json

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/legislators") do
          [200, {"content-type" => "application/json"}, generic_payload]
        end
        conn = Faraday.new("https://api.example.gov/v1") { |f| f.adapter :test, stubs }

        roster = adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
        expect(roster.size).to eq(1)
        entry = roster.first
        expect(entry[:external_id]).to eq("LEG-001")
        expect(entry[:full_name]).to eq("John Doe")
        expect(entry[:party]).to eq("Independent")
        expect(entry[:district]).to eq("District 5")
      end

      it "returns an empty array on empty JSON object response without emitting a phantom legislator" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/legislators") do
          [200, {"content-type" => "application/json"}, "{}"]
        end
        conn = Faraday.new("https://api.example.gov/v1") { |f| f.adapter :test, stubs }

        roster = adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
        expect(roster).to eq([])
      end

      it "filters out null items, non-hashes, and empty hashes in sparse arrays without crashing" do
        sparse_payload = [
          nil,
          {},
          "invalid string",
          42,
          {
            id: "LEG-002",
            name: "Jane Smith",
            party_name: "Democratic",
            district_no: "District 2"
          }
        ].to_json

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/legislators") do
          [200, {"content-type" => "application/json"}, sparse_payload]
        end
        conn = Faraday.new("https://api.example.gov/v1") { |f| f.adapter :test, stubs }

        roster = adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
        expect(roster.size).to eq(1)
        expect(roster.first[:external_id]).to eq("LEG-002")
        expect(roster.first[:full_name]).to eq("Jane Smith")
      end

      it "parses a single legislator object payload when returned as a bare JSON hash" do
        single_payload = {
          id: "LEG-003",
          name: "Single Representative",
          party_name: "Green",
          district_no: "District 9"
        }.to_json

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/legislators") do
          [200, {"content-type" => "application/json"}, single_payload]
        end
        conn = Faraday.new("https://api.example.gov/v1") { |f| f.adapter :test, stubs }

        roster = adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
        expect(roster.size).to eq(1)
        expect(roster.first[:external_id]).to eq("LEG-003")
        expect(roster.first[:full_name]).to eq("Single Representative")
      end
    end

    context "when HTTP error occurs" do
      let(:adapter) { described_class.new(engine: "congress_dot_gov", base_url: "https://api.congress.gov/v3") }

      it "raises a runtime error with status details" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/v3/member") { [500, {}, "Server error"] }
        conn = Faraday.new("https://api.congress.gov/v3") { |f| f.adapter :test, stubs }

        expect {
          adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
        }.to raise_error(/API returned 500/)
      end
    end
  end

  describe "TASK-ok5ox.48: Decoupled retrieval and parsing configuration" do
    describe "initialization with explicit retrieval and parsing" do
      it "derives @retrieval, @parsing, and fallback @engine from explicit configuration" do
        adapter = described_class.new({
          retrieval: "generic_rest",
          parsing: "congress_dot_gov",
          base_url: "https://api.example.gov/v1"
        })
        expect(adapter.retrieval).to eq(:generic_rest)
        expect(adapter.parsing).to eq(:congress_dot_gov)
        expect(adapter.engine).to eq("generic_rest")
      end

      it "supports symbol keys" do
        adapter = described_class.new({
          retrieval: :open_states,
          parsing: :open_states
        })
        expect(adapter.retrieval).to eq(:open_states)
        expect(adapter.parsing).to eq(:open_states)
        expect(adapter.engine).to eq("open_states")
      end

      it "supports alias keys retrieval_strategy and parser_format" do
        adapter = described_class.new({
          retrieval_strategy: "congress_dot_gov",
          parser_format: "congress_dot_gov"
        })
        expect(adapter.retrieval).to eq(:congress_dot_gov)
        expect(adapter.parsing).to eq(:congress_dot_gov)
        expect(adapter.engine).to eq("congress_dot_gov")
      end

      it "falls back retrieval and parsing to engine when explicit keys are absent" do
        adapter = described_class.new(engine: "open_states")
        expect(adapter.engine).to eq("open_states")
        expect(adapter.retrieval).to eq(:open_states)
        expect(adapter.parsing).to eq(:open_states)
      end

      it "extracts retrieval and parsing from SwayLocale instance" do
        adapter = described_class.new(sway_locale)
        expect(adapter.retrieval).to eq(:congress_dot_gov)
        expect(adapter.parsing).to eq(:congress_dot_gov)
      end
    end

    describe "decoupled execution" do
      it "executes generic_rest retrieval with congress_dot_gov parsing" do
        congress_payload = {
          members: [
            {
              bioguideId: "C100",
              name: "Rep. Decoupled",
              partyName: "Independent",
              state: "MD",
              district: 1
            }
          ]
        }.to_json

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/legislators") { [200, {"content-type" => "application/json"}, congress_payload] }
        conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }

        adapter = described_class.new({
          retrieval: "generic_rest",
          parsing: "congress_dot_gov",
          base_url: "https://api.example.gov",
          endpoints: {members: "/legislators"}
        }, connection: conn)

        roster = adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
        expect(roster.size).to eq(1)
        expect(roster.first[:external_id]).to eq("C100")
        expect(roster.first[:full_name]).to eq("Rep. Decoupled")
        expect(roster.first[:party]).to eq("Independent")
      end

      it "executes generic_rest retrieval with open_states parsing" do
        os_payload = {
          results: [
            {
              id: "OS-500",
              name: "Sen. State",
              party: "Democratic",
              current_role: {
                district: "District 20",
                title: "Senator",
                org_classification: "upper"
              }
            }
          ]
        }.to_json

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/legislators") { [200, {"content-type" => "application/json"}, os_payload] }
        conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }

        adapter = described_class.new({
          retrieval: "generic_rest",
          parsing: "open_states",
          base_url: "https://api.example.gov",
          endpoints: {members: "/legislators"}
        }, connection: conn)

        roster = adapter.fetch_roster(sway_locale: sway_locale, connection: conn)
        expect(roster.size).to eq(1)
        expect(roster.first[:external_id]).to eq("OS-500")
        expect(roster.first[:full_name]).to eq("Sen. State")
        expect(roster.first[:chamber]).to eq("upper")
      end

      it "returns empty array without network calls when retrieval is unavailable or curated" do
        expect(described_class.new(retrieval: "unavailable").fetch_roster(sway_locale: sway_locale)).to eq([])
        expect(described_class.new(retrieval: "curated").fetch_roster(sway_locale: sway_locale)).to eq([])
      end
    end

    describe "Legistar client isolation and multi-locale scoping" do
      it "resolves Legistar client from target_locale roster_rules" do
        locale = instance_double(
          SwayLocale,
          name: "annapolis-maryland-united_states",
          city: "annapolis",
          jurisdiction_rules: instance_double(
            SwayLocale::JurisdictionRules,
            roster_rules: {retrieval: "legistar", client: "annapolis"},
            legislation_rules: {client: "annapolis"}
          )
        )
        adapter = described_class.new({retrieval: "legistar", client: "baltimore"})
        expect(adapter.legistar_client(locale).client).to eq("annapolis")
      end

      it "prioritizes target_locale legislation_rules over @config[:client] when roster_rules lacks client" do
        locale = instance_double(
          SwayLocale,
          name: "annapolis-maryland-united_states",
          city: "annapolis",
          jurisdiction_rules: instance_double(
            SwayLocale::JurisdictionRules,
            roster_rules: {retrieval: "legistar"},
            legislation_rules: {client: "annapolis"}
          )
        )
        adapter = described_class.new({retrieval: "legistar", client: "baltimore"})
        expect(adapter.legistar_client(locale).client).to eq("annapolis")
      end

      it "raises ArgumentError when client cannot be resolved (no Baltimore fallback)" do
        adapter = described_class.new({retrieval: "legistar"})
        expect { adapter.legistar_client }.to raise_error(ArgumentError, /No client configured for Legistar roster adapter/)
      end
    end
  end

  describe "#build_official_evidence" do
    context "with dynamic configuration across jurisdictions" do
      it "populates Baltimore attribution dynamically from roster_rules without hardcoding" do
        payload = '{"members":[{"id":"M001","name":"Test Member"}]}'
        expected_digest = Digest::SHA256.hexdigest(payload)
        baltimore_config = {
          roster_rules: {
            evidence_publisher: "baltimorecity.gov",
            evidence_jurisdiction: "baltimore_city",
            evidence_source_url: "https://baltimorecity.gov"
          }
        }
        adapter = described_class.new(baltimore_config)
        evidence = adapter.build_official_evidence(payload)

        expect(evidence.publisher).to eq("baltimorecity.gov")
        expect(evidence.jurisdiction).to eq("baltimore_city")
        expect(evidence.source_url).to eq("https://baltimorecity.gov")
        expect(evidence.payload).to eq(payload)
        expect(evidence.payload_hash).to eq(expected_digest)
        expect(evidence.fact_type).to eq("roster")
        expect(evidence.fact_presence).to eq("present")
        expect(evidence.date_precision).to eq("none")
      end

      it "populates Maryland attribution dynamically from roster_rules without hardcoding" do
        payload = '{"members":[{"id":"M001","name":"Test Member"}]}'
        expected_digest = Digest::SHA256.hexdigest(payload)
        maryland_config = {
          roster_rules: {
            evidence_publisher: "openstates.org",
            evidence_jurisdiction: "maryland-maryland-united_states",
            evidence_source_url: "https://v3.openstates.org/people"
          }
        }
        adapter = described_class.new(maryland_config)
        evidence = adapter.build_official_evidence(payload)

        expect(evidence.publisher).to eq("openstates.org")
        expect(evidence.jurisdiction).to eq("maryland-maryland-united_states")
        expect(evidence.source_url).to eq("https://v3.openstates.org/people")
        expect(evidence.payload_hash).to eq(expected_digest)
      end

      it "populates Congress attribution dynamically from roster_rules without hardcoding" do
        payload = '{"members":[{"id":"M001","name":"Test Member"}]}'
        expected_digest = Digest::SHA256.hexdigest(payload)
        congress_config = {
          roster_rules: {
            evidence_publisher: "congress.gov",
            evidence_jurisdiction: "us_congress",
            evidence_source_url: "https://api.congress.gov/v3/member"
          }
        }
        adapter = described_class.new(congress_config)
        evidence = adapter.build_official_evidence(payload)

        expect(evidence.publisher).to eq("congress.gov")
        expect(evidence.jurisdiction).to eq("us_congress")
        expect(evidence.source_url).to eq("https://api.congress.gov/v3/member")
        expect(evidence.payload_hash).to eq(expected_digest)
      end

      it "populates custom arbitrary jurisdiction attribution dynamically from config" do
        payload = '{"members":[{"id":"M001","name":"Test Member"}]}'
        expected_digest = Digest::SHA256.hexdigest(payload)
        custom_config = {
          evidence_publisher: "delaware.gov",
          evidence_jurisdiction: "state_of_delaware",
          evidence_source_url: "https://api.delaware.gov/v1/roster"
        }
        adapter = described_class.new(custom_config)
        evidence = adapter.build_official_evidence(payload)

        expect(evidence.publisher).to eq("delaware.gov")
        expect(evidence.jurisdiction).to eq("state_of_delaware")
        expect(evidence.source_url).to eq("https://api.delaware.gov/v1/roster")
        expect(evidence.payload_hash).to eq(expected_digest)
      end
    end

    context "when OfficialEvidence class is defined" do
      it "instantiates OfficialEvidence with expected attributes" do
        dummy_class = Class.new do
          attr_reader :publisher, :jurisdiction, :source_url, :retrieved_at, :payload, :payload_hash, :fact_type, :fact_presence, :date_precision, :external_record_id, :sway_locale_id, :parsed_values, :date_semantics

          def initialize(attrs = {})
            attrs.each { |k, v| instance_variable_set("@#{k}", v) }
          end
        end
        stub_const("OfficialEvidence", dummy_class)

        adapter = described_class.new(
          evidence_publisher: "congress.gov",
          evidence_jurisdiction: "us_congress",
          evidence_source_url: "https://api.congress.gov/v3/member"
        )
        payload = '{"members":[{"id":"M001","name":"Test Member"}]}'
        expected_digest = Digest::SHA256.hexdigest(payload)
        custom_time = Time.zone.parse("2026-09-19 12:00:00 UTC")
        evidence = adapter.build_official_evidence(
          payload,
          retrieved_at: custom_time,
          fact_type: "custom_roster",
          fact_presence: "present",
          date_precision: "exact"
        )

        expect(evidence).to be_a(dummy_class)
        expect(evidence.publisher).to eq("congress.gov")
        expect(evidence.jurisdiction).to eq("us_congress")
        expect(evidence.source_url).to eq("https://api.congress.gov/v3/member")
        expect(evidence.retrieved_at).to eq(custom_time)
        expect(evidence.payload).to eq(payload)
        expect(evidence.payload_hash).to eq(expected_digest)
        expect(evidence.fact_type).to eq("custom_roster")
        expect(evidence.fact_presence).to eq("present")
        expect(evidence.date_precision).to eq("exact")
      end
    end

    context "payload digest calculation" do
      it "computes SHA-256 hexdigest of payload converting non-string payloads with to_s" do
        adapter = described_class.new(evidence_publisher: "test.gov")
        hash_payload = {key: "value"}
        evidence = adapter.build_official_evidence(hash_payload)

        expect(evidence.payload).to eq(hash_payload.to_s)
        expect(evidence.payload_hash).to eq(Digest::SHA256.hexdigest(hash_payload.to_s))
      end
    end

    context "deep JSONPath array indexing in #parse_generic_items" do
      it "extracts fields using nested JSON paths and array indexing and skips blank records" do
        payload = {
          "legislators" => [
            {
              "id_info" => {"primary_id" => "M001"},
              "profile" => {
                "names" => [{"full" => "Delegate Daisy"}],
                "affiliations" => [{"party_name" => "Green"}]
              },
              "jurisdiction" => {"district_num" => "42B"},
              "media" => {"headshot" => {"url" => "https://example.com/daisy.png"}}
            },
            {"id_info" => {"primary_id" => ""}, "profile" => {"names" => [{"full" => ""}]}}
          ]
        }

        adapter = described_class.new(
          retrieval: "generic_rest",
          parsing: "generic_json",
          metadata_mapping: {
            external_id: "$.id_info.primary_id",
            full_name: "profile.names[0].full",
            party: "profile.affiliations[0].party_name",
            district: "jurisdiction.district_num",
            photo_url: "media.headshot.url"
          }
        )

        items = adapter.send(:parse_generic_items, payload)
        expect(items.size).to eq(1)
        expect(items.first).to include(
          external_id: "M001",
          full_name: "Delegate Daisy",
          party: "Green",
          district: "42B",
          photo_url: "https://example.com/daisy.png"
        )
      end
    end
  end
end
