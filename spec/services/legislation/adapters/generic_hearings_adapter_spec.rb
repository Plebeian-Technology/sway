# frozen_string_literal: true

require "rails_helper"

RSpec.describe Legislation::Adapters::GenericHearingsAdapter do
  let(:maryland) { create(:sway_locale, :maryland) }
  let(:bill) { create(:bill, external_id: "SB0001", sway_locale: maryland) }

  around do |example|
    Dir.mktmpdir("generic_hearings_spec") do |tmp|
      @tmp_root = Pathname.new(tmp)
      example.run
    end
  end

  before do
    allow(Legislation::Paths).to receive(:root).and_return(@tmp_root) if @tmp_root
  end

  describe "initialization" do
    it "initializes from raw config hash" do
      adapter = described_class.new({engine: "generic_html", base_url: "https://example.gov"})
      expect(adapter.engine).to eq(:generic_html)
      expect(adapter.base_url).to eq("https://example.gov")
    end

    it "initializes from SwayLocale instance" do
      adapter = described_class.new(maryland)
      expect(adapter.engine).to eq(:generic_html)
      expect(adapter.base_url).to eq("https://mgaleg.maryland.gov")
    end

    it "does not populate config[:client] from jurisdiction property in extract_config" do
      rules = instance_double(
        SwayLocale::JurisdictionRules,
        hearings_rules: {retrieval: "legistar", parsing: "legistar", jurisdiction: "baltimore"},
        legislation_rules: {}
      )
      adapter = described_class.new(rules)
      expect(adapter.config[:client]).to be_nil
      expect(adapter.config[:jurisdiction]).to eq("baltimore")
    end
  end

  describe "#discover_hearings with generic_html engine" do
    it "extracts hearings from HTML, writes hearings.json artifact, and updates bill provisioning" do
      html_with_hearings = <<~HTML
        <html><body>
          <div class="hearing-entry">
            <span class="committee">Judicial Proceedings</span>
            <span class="date">1/22/2026</span>
            <span class="time">1:00 PM</span>
            <span class="location">West Committee Room</span>
          </div>
        </body></html>
      HTML

      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/details/sb0001") { [200, {"content-type" => "text/html"}, html_with_hearings] }

      conn = Faraday.new("https://example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_html",
        base_url: "https://example.gov",
        endpoints: {details: "/details/:external_id"}
      }, connection: conn)

      hearings = adapter.discover_hearings(bill: bill, sway_locale: maryland)
      expect(hearings.size).to eq(1)
      first = hearings.first
      expect(first["EventBodyName"]).to eq("Judicial Proceedings")
      expect(first["EventDate"]).to eq("1/22/2026")
      expect(first["EventTime"]).to eq("1:00 PM")
      expect(first["EventLocation"]).to eq("West Committee Room")

      artifact = Legislation::Paths.hearings_file(bill.external_id, sway_locale: maryland.name)
      expect(artifact).to exist
      parsed = JSON.parse(artifact.read)
      expect(parsed["events"].size).to eq(1)

      expect(bill.reload.bill_llm_provisioning&.testimony_fetched_at).not_to be_nil
    end

    it "returns empty array and writes empty artifact when no hearings are found" do
      html_without_hearings = "<html><body><div>No scheduled hearings</div></body></html>"

      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/details/sb0001") { [200, {"content-type" => "text/html"}, html_without_hearings] }

      conn = Faraday.new("https://example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_html",
        base_url: "https://example.gov",
        endpoints: {details: "/details/:external_id"}
      }, connection: conn)

      hearings = adapter.discover_hearings(bill: bill, sway_locale: maryland)
      expect(hearings).to be_empty

      artifact = Legislation::Paths.hearings_file(bill.external_id, sway_locale: maryland.name)
      expect(artifact).to exist
      parsed = JSON.parse(artifact.read)
      expect(parsed["events"]).to eq([])
    end

    it "raises BillProcessingError on HTTP failure" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/details/sb0001") { [500, {}, "Server Error"] }

      conn = Faraday.new("https://example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_html",
        base_url: "https://example.gov",
        endpoints: {details: "/details/:external_id"}
      }, connection: conn)

      expect {
        adapter.discover_hearings(bill: bill, sway_locale: maryland)
      }.to raise_error(BillProcessingError, /fetch_hearings.*500/)
    end
  end

  describe "#discover_hearings with generic_rest engine" do
    it "extracts hearings from REST endpoint" do
      json_hearings = {
        hearings: [
          {
            id: 101,
            committee: "Ways and Means",
            date: "2026-02-15",
            time: "10:00 AM",
            room: "Room 120"
          }
        ]
      }.to_json

      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/hearings/SB0001") { [200, {"content-type" => "application/json"}, json_hearings] }

      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_rest",
        base_url: "https://api.example.gov",
        endpoints: {hearings: "/hearings/:external_id"}
      }, connection: conn)

      hearings = adapter.discover_hearings(bill: bill, sway_locale: maryland)
      expect(hearings.size).to eq(1)
      expect(hearings.first["EventBodyName"]).to eq("Ways and Means")
      expect(hearings.first["EventDate"]).to eq("2026-02-15")
    end

    it "returns empty array and does not generate phantom hearing on empty REST response {}" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/hearings/SB0001") { [200, {"content-type" => "application/json"}, "{}"] }

      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_rest",
        base_url: "https://api.example.gov",
        endpoints: {hearings: "/hearings/:external_id"}
      }, connection: conn)

      hearings = adapter.discover_hearings(bill: bill, sway_locale: maryland)
      expect(hearings).to eq([])

      artifact = Legislation::Paths.hearings_file(bill.external_id, sway_locale: maryland.name)
      expect(artifact).to exist
      parsed = JSON.parse(artifact.read)
      expect(parsed["events"]).to eq([])
    end

    it "returns empty array when upstream returns empty hearings list '{\"hearings\":[]}'" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/hearings/SB0001") { [200, {"content-type" => "application/json"}, {hearings: []}.to_json] }

      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_rest",
        base_url: "https://api.example.gov",
        endpoints: {hearings: "/hearings/:external_id"}
      }, connection: conn)

      hearings = adapter.discover_hearings(bill: bill, sway_locale: maryland)
      expect(hearings).to eq([])
    end

    it "safely returns empty array when upstream returns non-JSON or invalid JSON" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/hearings/SB0001") { [200, {"content-type" => "application/json"}, "not json"] }

      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_rest",
        base_url: "https://api.example.gov",
        endpoints: {hearings: "/hearings/:external_id"}
      }, connection: conn)

      hearings = adapter.discover_hearings(bill: bill, sway_locale: maryland)
      expect(hearings).to eq([])
    end
  end

  describe "#discover_hearings with unavailable engine" do
    it "returns empty array without network request" do
      adapter = described_class.new({engine: "unavailable"})
      hearings = adapter.discover_hearings(bill: bill, sway_locale: maryland)
      expect(hearings).to eq([])
    end
  end

  describe "Removal of fallback checks for legacy source properties (TASK-ok5ox.28)" do
    it "strictly obeys hearings_rules and ignores legacy hearings_source" do
      rules = double(
        "JurisdictionRules",
        hearings_rules: {engine: "generic_html", base_url: "https://example.gov"},
        hearings_source: :legistar
      )
      adapter = described_class.new(rules)
      expect(adapter.engine).to eq(:generic_html)
    end

    it "does not fall back to hearings_source when hearings_rules is empty" do
      rules = double(
        "JurisdictionRules",
        hearings_rules: {},
        hearings_source: :unavailable
      )
      adapter = described_class.new(rules)
      expect(adapter.engine).to eq(:generic_html)
    end
  end

  describe "Upstream querying methods (TASK-ok5ox.22)" do
    let(:legistar_opts) do
      {engine: "legistar", client: "baltimore", base_url: "https://webapi.legistar.com/v1"}
    end

    it "provides matter_attachments delegating to Legistar client" do
      adapter = described_class.new({engine: "legistar", client: "baltimore", base_url: "https://webapi.legistar.com/v1"})
      mock_client = instance_double(Legistar::Client)
      allow(mock_client).to receive(:matter_attachments).with(1234).and_return([{"Id" => 1}])
      allow(adapter).to receive(:legistar_client).and_return(mock_client)

      expect(adapter.matter_attachments(1234)).to eq([{"Id" => 1}])
    end

    it "provides matter_histories delegating to Legistar client" do
      adapter = described_class.new({engine: "legistar", client: "baltimore", base_url: "https://webapi.legistar.com/v1"})
      mock_client = instance_double(Legistar::Client)
      allow(mock_client).to receive(:matter_histories).with(1234).and_return([{"MatterHistoryEventId" => 500}])
      allow(adapter).to receive(:legistar_client).and_return(mock_client)

      expect(adapter.matter_histories(1234)).to eq([{"MatterHistoryEventId" => 500}])
    end

    it "provides matter_exists? returning true when matter exists" do
      adapter = described_class.new({engine: "legistar", client: "baltimore", base_url: "https://webapi.legistar.com/v1"})
      mock_client = instance_double(Legistar::Client)
      allow(mock_client).to receive(:get).with("Matters/1234").and_return({"MatterId" => 1234})
      allow(adapter).to receive(:legistar_client).and_return(mock_client)

      expect(adapter.matter_exists?(1234)).to be true
    end

    it "provides matter_exists? returning false on 404" do
      adapter = described_class.new({engine: "legistar", client: "baltimore", base_url: "https://webapi.legistar.com/v1"})
      mock_client = instance_double(Legistar::Client)
      allow(mock_client).to receive(:get).with("Matters/9999").and_raise(Legistar::Client::HttpError.new(status: 404, path: "Matters/9999"))
      allow(adapter).to receive(:legistar_client).and_return(mock_client)

      expect(adapter.matter_exists?(9999)).to be false
    end

    it "provides hearing_event returning event data" do
      adapter = described_class.new({engine: "legistar", client: "baltimore", base_url: "https://webapi.legistar.com/v1"})
      mock_client = instance_double(Legistar::Client)
      allow(mock_client).to receive(:get).with("Events/555").and_return({"EventId" => 555})
      allow(adapter).to receive(:legistar_client).and_return(mock_client)

      expect(adapter.hearing_event(555)).to eq({"EventId" => 555})
    end

    it "provides event_items returning event items array" do
      adapter = described_class.new({engine: "legistar", client: "baltimore", base_url: "https://webapi.legistar.com/v1"})
      mock_client = instance_double(Legistar::Client)
      allow(mock_client).to receive(:get_raw).with("Events/555/EventItems", {"Attachments" => 1}).and_return([{"Item" => 1}])
      allow(adapter).to receive(:legistar_client).and_return(mock_client)

      expect(adapter.event_items(555)).to eq([{"Item" => 1}])
    end

    it "provides attachment_fetch returning Legistar::AttachmentFetch" do
      adapter = described_class.new({engine: "legistar", client: "baltimore", base_url: "https://webapi.legistar.com/v1"})
      expect(adapter.attachment_fetch).to be_a(Legistar::AttachmentFetch)
    end
  end

  describe "TASK-ok5ox.47: Decoupled retrieval and parsing configuration" do
    describe "initialization with explicit retrieval and parsing" do
      it "derives @retrieval, @parsing, and fallback @engine from explicit configuration" do
        adapter = described_class.new({
          retrieval: "generic_rest",
          parsing: "generic_rest",
          base_url: "https://api.example.gov"
        })
        expect(adapter.retrieval).to eq(:generic_rest)
        expect(adapter.parsing).to eq(:generic_rest)
        expect(adapter.engine).to eq(:generic_rest)
      end

      it "supports alias keys retrieval_strategy and parser_format" do
        adapter = described_class.new({
          retrieval_strategy: "generic_rest",
          parser_format: "generic_html"
        })
        expect(adapter.retrieval).to eq(:generic_rest)
        expect(adapter.parsing).to eq(:generic_html)
        expect(adapter.engine).to eq(:generic_rest)
      end

      it "falls back to @engine when retrieval and parsing are omitted" do
        adapter = described_class.new({engine: "generic_html"})
        expect(adapter.engine).to eq(:generic_html)
        expect(adapter.retrieval).to eq(:generic_html)
        expect(adapter.parsing).to eq(:generic_html)
      end

      it "preserves distinct values under dual definition" do
        adapter = described_class.new({
          engine: "legacy_name",
          retrieval: "generic_rest",
          parsing: "generic_html"
        })
        expect(adapter.engine).to eq(:legacy_name)
        expect(adapter.retrieval).to eq(:generic_rest)
        expect(adapter.parsing).to eq(:generic_html)
      end

      it "defaults retrieval and parsing to generic_html when config is empty" do
        adapter = described_class.new({})
        expect(adapter.retrieval).to eq(:generic_html)
        expect(adapter.parsing).to eq(:generic_html)
        expect(adapter.engine).to eq(:generic_html)
      end
    end

    describe "discover_hearings branching on retrieval and parsing" do
      it "discovers hearings with decoupled retrieval: :generic_rest and parsing: :generic_rest" do
        json_data = {
          hearings: [
            {id: 201, committee: "Finance", date: "2026-03-01", time: "2:00 PM", room: "Room 300"}
          ]
        }.to_json

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/hearings/SB0001") { [200, {"content-type" => "application/json"}, json_data] }
        conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }

        adapter = described_class.new({
          retrieval: "generic_rest",
          parsing: "generic_rest",
          base_url: "https://api.example.gov",
          endpoints: {hearings: "/hearings/:external_id"}
        }, connection: conn)

        hearings = adapter.discover_hearings(bill: bill, sway_locale: maryland)
        expect(hearings.size).to eq(1)
        expect(hearings.first["EventBodyName"]).to eq("Finance")
        expect(hearings.first["EventDate"]).to eq("2026-03-01")
        expect(hearings.first["EventTime"]).to eq("2:00 PM")
        expect(hearings.first["EventLocation"]).to eq("Room 300")
      end

      it "discovers hearings with decoupled retrieval: :generic_html and parsing: :generic_html" do
        html_data = <<~HTML
          <html><body>
            <div class="hearing-entry">
              <span class="committee">Budget and Taxation</span>
              <span class="date">3/10/2026</span>
              <span class="time">10:00 AM</span>
              <span class="location">Room 100</span>
            </div>
          </body></html>
        HTML

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/details/sb0001") { [200, {"content-type" => "text/html"}, html_data] }
        conn = Faraday.new("https://example.gov") { |f| f.adapter :test, stubs }

        adapter = described_class.new({
          retrieval: "generic_html",
          parsing: "generic_html",
          base_url: "https://example.gov",
          endpoints: {details: "/details/:external_id"}
        }, connection: conn)

        hearings = adapter.discover_hearings(bill: bill, sway_locale: maryland)
        expect(hearings.size).to eq(1)
        expect(hearings.first["EventBodyName"]).to eq("Budget and Taxation")
        expect(hearings.first["EventDate"]).to eq("3/10/2026")
      end

      it "discovers hearings when retrieval: :legistar directly without requiring FetchHearingsService" do
        meta_path = Legislation::Paths.bill_metadata_file(bill.external_id, sway_locale: maryland.name)
        meta_path.dirname.mkpath
        meta_path.write({"matter_id" => 1234}.to_json)

        mock_client = instance_double(Legistar::Client)
        allow(mock_client).to receive(:matter_histories).with(1234).and_return([{"MatterHistoryEventId" => 999}])
        allow(mock_client).to receive(:get).with("Events/999").and_return({
          "EventId" => 999,
          "EventDate" => "2026-03-20T00:00:00",
          "EventTime" => "10:00 AM",
          "EventLocation" => "Council Chambers",
          "EventBodyName" => "Judiciary Committee"
        })
        allow(mock_client).to receive(:get_raw).with("Events/999/EventItems", {"Attachments" => 1}).and_return([])

        adapter = described_class.new({
          retrieval: "legistar",
          parsing: "legistar",
          client: "baltimore"
        })
        allow(adapter).to receive(:legistar_client).and_return(mock_client)

        hearings = adapter.discover_hearings(bill: bill, sway_locale: maryland)
        expect(hearings.size).to eq(1)
        expect(hearings.first["EventId"]).to eq(999)
        expect(hearings.first["EventBodyName"]).to eq("Judiciary Committee")

        artifact = Legislation::Paths.hearings_file(bill.external_id, sway_locale: maryland.name)
        expect(artifact).to exist
        parsed = JSON.parse(artifact.read)
        expect(parsed["events"].size).to eq(1)
        expect(bill.reload.bill_llm_provisioning&.testimony_fetched_at).not_to be_nil
      end

      it "discovers hearings when retrieval: :legistar by delegating to service when service is provided" do
        mock_service = double("FetchHearingsService")
        allow(mock_service).to receive(:discover_legistar_hearings).with(bill, maryland).and_return([{"EventId" => 999}])

        adapter = described_class.new({
          retrieval: "legistar",
          parsing: "legistar",
          client: "baltimore"
        }, service: mock_service)

        hearings = adapter.discover_hearings(bill: bill, sway_locale: maryland, service: mock_service)
        expect(hearings).to eq([{"EventId" => 999}])
      end

      it "probes matter existence when histories are empty and raises BillProcessingError if matter does not exist upstream" do
        meta_path = Legislation::Paths.bill_metadata_file(bill.external_id, sway_locale: maryland.name)
        meta_path.dirname.mkpath
        meta_path.write({"matter_id" => 1234}.to_json)

        mock_client = instance_double(Legistar::Client)
        allow(mock_client).to receive(:matter_histories).with(1234).and_return([])
        allow(mock_client).to receive(:get).with("Matters/1234").and_raise(
          Legistar::Client::HttpError.new(status: 404, path: "Matters/1234")
        )

        adapter = described_class.new({
          retrieval: "legistar",
          parsing: "legistar",
          client: "baltimore"
        })
        allow(adapter).to receive(:legistar_client).and_return(mock_client)

        expect {
          adapter.discover_hearings(bill: bill, sway_locale: maryland)
        }.to raise_error(BillProcessingError, /matter_id 1234 does not exist upstream/)
      end

      it "encapsulates Legistar::Client::Error as BillProcessingError during discovery" do
        meta_path = Legislation::Paths.bill_metadata_file(bill.external_id, sway_locale: maryland.name)
        meta_path.dirname.mkpath
        meta_path.write({"matter_id" => 1234}.to_json)

        mock_client = instance_double(Legistar::Client)
        allow(mock_client).to receive(:matter_histories).with(1234).and_raise(
          Legistar::Client::Error.new("connection timeout")
        )

        adapter = described_class.new({
          retrieval: "legistar",
          parsing: "legistar",
          client: "baltimore"
        })
        allow(adapter).to receive(:legistar_client).and_return(mock_client)

        expect {
          adapter.discover_hearings(bill: bill, sway_locale: maryland)
        }.to raise_error(BillProcessingError, /fetch_hearings: Legistar::Client::Error: connection timeout/)
      end

      it "encapsulates Faraday::Error as BillProcessingError during discovery" do
        meta_path = Legislation::Paths.bill_metadata_file(bill.external_id, sway_locale: maryland.name)
        meta_path.dirname.mkpath
        meta_path.write({"matter_id" => 1234}.to_json)

        mock_client = instance_double(Legistar::Client)
        allow(mock_client).to receive(:matter_histories).with(1234).and_raise(
          Faraday::ConnectionFailed.new("connection refused")
        )

        adapter = described_class.new({
          retrieval: "legistar",
          parsing: "legistar",
          client: "baltimore"
        })
        allow(adapter).to receive(:legistar_client).and_return(mock_client)

        expect {
          adapter.discover_hearings(bill: bill, sway_locale: maryland)
        }.to raise_error(BillProcessingError, /fetch_hearings: Faraday::ConnectionFailed: connection refused/)
      end

      it "returns empty array without network request when retrieval: :unavailable" do
        adapter = described_class.new({retrieval: "unavailable", parsing: "unavailable"})
        hearings = adapter.discover_hearings(bill: bill, sway_locale: maryland)
        expect(hearings).to eq([])
      end
    end

    describe "Legistar query methods guarding on retrieval == :legistar" do
      it "allows Legistar query methods when retrieval: :legistar" do
        mock_client = instance_double(Legistar::Client)
        adapter = described_class.new({
          retrieval: "legistar",
          parsing: "legistar",
          client: "baltimore",
          base_url: "https://webapi.legistar.com/v1"
        })
        allow(adapter).to receive(:legistar_client).and_return(mock_client)
        allow(mock_client).to receive(:matter_attachments).with(101).and_return([{"Id" => 1}])
        allow(mock_client).to receive(:matter_histories).with(101).and_return([{"MatterHistoryEventId" => 1}])
        allow(mock_client).to receive(:get).with("Matters/101").and_return({"MatterId" => 101})
        allow(mock_client).to receive(:get).with("Events/202").and_return({"EventId" => 202})
        allow(mock_client).to receive(:get_raw).with("Events/202/EventItems", {"Attachments" => 1}).and_return([{"Item" => 1}])

        expect(adapter.matter_attachments(101)).to eq([{"Id" => 1}])
        expect(adapter.matter_histories(101)).to eq([{"MatterHistoryEventId" => 1}])
        expect(adapter.matter_exists?(101)).to be true
        expect(adapter.hearing_event(202)).to eq({"EventId" => 202})
        expect(adapter.event_items(202)).to eq([{"Item" => 1}])
      end

      it "guards Legistar query methods when retrieval is not :legistar" do
        adapter = described_class.new({
          retrieval: "generic_rest",
          parsing: "generic_rest",
          base_url: "https://api.example.gov"
        })

        expect(adapter.matter_attachments(101)).to eq([])
        expect(adapter.matter_histories(101)).to eq([])
        expect(adapter.matter_exists?(101)).to be false
        expect(adapter.hearing_event(202)).to be_nil
        expect(adapter.event_items(202)).to eq([])
      end
    end

    describe "Exception encapsulation in query methods" do
      let(:adapter) do
        described_class.new({
          retrieval: "legistar",
          parsing: "legistar",
          client: "baltimore",
          base_url: "https://webapi.legistar.com/v1"
        })
      end

      it "safely returns empty array in matter_attachments on Legistar::Client::Error or Faraday::Error" do
        mock_client = instance_double(Legistar::Client)
        allow(adapter).to receive(:legistar_client).and_return(mock_client)
        allow(mock_client).to receive(:matter_attachments).with(101).and_raise(Legistar::Client::Error.new("failed"))
        expect(adapter.matter_attachments(101)).to eq([])

        allow(mock_client).to receive(:matter_attachments).with(101).and_raise(Faraday::ConnectionFailed.new("failed"))
        expect(adapter.matter_attachments(101)).to eq([])
      end

      it "safely returns empty array in matter_histories on Legistar::Client::Error or Faraday::Error" do
        mock_client = instance_double(Legistar::Client)
        allow(adapter).to receive(:legistar_client).and_return(mock_client)
        allow(mock_client).to receive(:matter_histories).with(101).and_raise(Legistar::Client::Error.new("failed"))
        expect(adapter.matter_histories(101)).to eq([])

        allow(mock_client).to receive(:matter_histories).with(101).and_raise(Faraday::ConnectionFailed.new("failed"))
        expect(adapter.matter_histories(101)).to eq([])
      end

      it "safely returns nil in hearing_event on Legistar::Client::Error or Faraday::Error" do
        mock_client = instance_double(Legistar::Client)
        allow(adapter).to receive(:legistar_client).and_return(mock_client)
        allow(mock_client).to receive(:get).with("Events/202").and_raise(Legistar::Client::Error.new("failed"))
        expect(adapter.hearing_event(202)).to be_nil

        allow(mock_client).to receive(:get).with("Events/202").and_raise(Faraday::ConnectionFailed.new("failed"))
        expect(adapter.hearing_event(202)).to be_nil
      end

      it "safely returns empty array in event_items on Legistar::Client::Error or Faraday::Error" do
        mock_client = instance_double(Legistar::Client)
        allow(adapter).to receive(:legistar_client).and_return(mock_client)
        allow(mock_client).to receive(:get_raw).with("Events/202/EventItems", {"Attachments" => 1}).and_raise(Legistar::Client::Error.new("failed"))
        expect(adapter.event_items(202)).to eq([])

        allow(mock_client).to receive(:get_raw).with("Events/202/EventItems", {"Attachments" => 1}).and_raise(Faraday::ConnectionFailed.new("failed"))
        expect(adapter.event_items(202)).to eq([])
      end
    end

    describe "Legistar client instantiation without requiring top-level client key" do
      it "extracts client from params[:client]" do
        adapter = described_class.new({
          retrieval: "legistar",
          parsing: "legistar",
          params: {client: "baltimore"},
          base_url: "https://webapi.legistar.com/v1"
        })
        expect(adapter.legistar_client.client).to eq("baltimore")
      end

      it "extracts client from jurisdiction key" do
        adapter = described_class.new({
          retrieval: "legistar",
          parsing: "legistar",
          jurisdiction: "annapolis",
          base_url: "https://webapi.legistar.com/v1"
        })
        expect(adapter.legistar_client.client).to eq("annapolis")
      end

      it "extracts client from legislation_rules fallback in JurisdictionRules" do
        rules = double(
          "JurisdictionRules",
          hearings_rules: {retrieval: "legistar", parsing: "legistar"},
          legislation_rules: {client: "baltimore"}
        )
        adapter = described_class.new(rules)
        expect(adapter.legistar_client.client).to eq("baltimore")
      end

      it "prioritizes target_locale over @config[:client]" do
        adapter = described_class.new({
          retrieval: "legistar",
          parsing: "legistar",
          client: "baltimore",
          base_url: "https://webapi.legistar.com/v1"
        })
        annapolis_locale = instance_double(
          SwayLocale,
          name: "annapolis-maryland-united_states",
          jurisdiction_rules: instance_double(
            SwayLocale::JurisdictionRules,
            hearings_rules: {retrieval: "legistar", parsing: "legistar", client: "annapolis"},
            legislation_rules: {client: "annapolis"}
          )
        )
        expect(adapter.legistar_client(annapolis_locale).client).to eq("annapolis")
      end

      it "prioritizes target_locale legislation_rules over @config[:client] when hearings_rules lacks client" do
        adapter = described_class.new({
          retrieval: "legistar",
          parsing: "legistar",
          client: "baltimore",
          base_url: "https://webapi.legistar.com/v1"
        })
        annapolis_locale = instance_double(
          SwayLocale,
          name: "annapolis-maryland-united_states",
          jurisdiction_rules: instance_double(
            SwayLocale::JurisdictionRules,
            hearings_rules: {retrieval: "legistar", parsing: "legistar"},
            legislation_rules: {client: "annapolis"}
          )
        )
        expect(adapter.legistar_client(annapolis_locale).client).to eq("annapolis")
      end

      it "does not fall back to target_locale.city and raises ArgumentError when client is not configured" do
        locale_with_only_city = instance_double(
          SwayLocale,
          city: "baltimore",
          jurisdiction_rules: instance_double(
            SwayLocale::JurisdictionRules,
            hearings_rules: {retrieval: "legistar", parsing: "legistar"},
            legislation_rules: {}
          )
        )
        adapter = described_class.new({
          retrieval: "legistar",
          parsing: "legistar",
          base_url: "https://webapi.legistar.com/v1"
        })
        expect { adapter.legistar_client(locale_with_only_city) }.to raise_error(
          ArgumentError, /No client configured for Legistar hearings adapter/
        )
      end

      it "extracts client from hearings_rules jurisdiction key in target_locale" do
        baltimore_locale = instance_double(
          SwayLocale,
          jurisdiction_rules: instance_double(
            SwayLocale::JurisdictionRules,
            hearings_rules: {retrieval: "legistar", parsing: "legistar", jurisdiction: "baltimore"},
            legislation_rules: {}
          )
        )
        adapter = described_class.new({
          retrieval: "legistar",
          parsing: "legistar",
          base_url: "https://webapi.legistar.com/v1"
        })
        expect(adapter.legistar_client(baltimore_locale).client).to eq("baltimore")
      end

      it "raises ArgumentError when client cannot be resolved" do
        adapter = described_class.new({
          retrieval: "legistar",
          parsing: "legistar",
          base_url: "https://webapi.legistar.com/v1"
        })
        expect { adapter.legistar_client }.to raise_error(ArgumentError, /No client configured for Legistar hearings adapter/)
      end
    end

    describe "#coerce_matter_id! and #discover_legistar_hearings error handling" do
      let(:adapter) do
        described_class.new({
          retrieval: "legistar",
          parsing: "legistar",
          client: "baltimore",
          base_url: "https://webapi.legistar.com/v1"
        })
      end

      it "accepts positive integers and numeric strings within 31-bit range and rejects out-of-bounds or non-numeric inputs" do
        expect(adapter.send(:coerce_matter_id!, 1)).to eq(1)
        expect(adapter.send(:coerce_matter_id!, (2**31) - 1)).to eq(2_147_483_647)
        expect(adapter.send(:coerce_matter_id!, "12345")).to eq(12_345)

        [0, -1, 2**31, "0", "-1", "123; DROP TABLE bills;", "12345678901", "2147483648", nil, [123], {id: 123}].each do |invalid_id|
          expect {
            adapter.send(:coerce_matter_id!, invalid_id)
          }.to raise_error(BillProcessingError)
        end
      end

      it "probes matter existence on ParseError during matter_histories and raises BillProcessingError on 404, 500, or transport failure" do
        mock_client = instance_double(Legistar::Client)
        legistar_bill = double("Bill", id: 1, external_id: "SB0001", metadata: {"MatterId" => 1234}, sway_locale: maryland)
        allow(adapter).to receive(:legistar_client).and_return(mock_client)
        allow(mock_client).to receive(:matter_histories).with(1234).and_raise(
          Legistar::Client::ParseError.new("Invalid JSON returned from Histories")
        )

        allow(mock_client).to receive(:get).with("Matters/1234").and_return({"MatterId" => 1234})
        expect(adapter.discover_legistar_hearings(legistar_bill, maryland)).to eq([])

        allow(mock_client).to receive(:get).with("Matters/1234").and_raise(
          Legistar::Client::HttpError.new(status: 404, path: "Matters/1234")
        )
        expect {
          adapter.discover_legistar_hearings(legistar_bill, maryland)
        }.to raise_error(BillProcessingError, /matter_id 1234 does not exist upstream/)

        allow(mock_client).to receive(:get).with("Matters/1234").and_raise(
          Legistar::Client::HttpError.new(status: 500, path: "Matters/1234")
        )
        expect {
          adapter.discover_legistar_hearings(legistar_bill, maryland)
        }.to raise_error(BillProcessingError, /HTTP 500 probing Matters\/1234/)

        allow(mock_client).to receive(:get).with("Matters/1234").and_raise(
          Faraday::ConnectionFailed.new("network down")
        )
        expect {
          adapter.discover_legistar_hearings(legistar_bill, maryland)
        }.to raise_error(BillProcessingError, /Faraday::ConnectionFailed: network down probing Matters\/1234/)
      end
    end
  end
end
