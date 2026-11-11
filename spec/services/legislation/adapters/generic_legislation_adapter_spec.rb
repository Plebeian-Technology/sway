# frozen_string_literal: true

require "rails_helper"

RSpec.describe Legislation::Adapters::GenericLegislationAdapter do
  let(:maryland) do
    loc = create(:sway_locale, :maryland)
    create(
      :legislative_session,
      sway_locale: loc,
      name: "2025RS",
      start_date: Date.new(2025, 1, 8),
      end_date: Date.new(2025, 4, 7),
      active: true
    )
    loc.reload
  end
  let(:current_session_name) { maryland.current_legislative_session&.name || "2025RS" }
  let(:baltimore) { create(:sway_locale, :baltimore) }
  let(:current_session_name) do
    active = maryland.current_legislative_session
    if active
      (active.respond_to?(:upstream_name) && active.upstream_name.present?) ? active.upstream_name : active.name
    else
      doc = SwayLocale::DocumentReader.find(maryland.name)
      active_def = doc&.legislative_sessions&.find(&:active?)
      if active_def
        (active_def.respond_to?(:upstream_name) && active_def.upstream_name.present?) ? active_def.upstream_name : active_def.name
      else
        "2026RS"
      end
    end
  end
  let(:pdf_fixture) { "%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n" }

  around do |example|
    Dir.mktmpdir("generic_leg_spec") do |tmp|
      @tmp_root = Pathname.new(tmp)
      example.run
    end
  end

  before do
    allow(Legislation::Paths).to receive(:root).and_return(@tmp_root) if @tmp_root
  end

  describe "initialization" do
    it "initializes from a raw config Hash" do
      adapter = described_class.new({
        engine: "generic_rest",
        base_url: "https://api.example.gov",
        metadata_mapping: {external_id: "$.id", title: "$.name"}
      })
      expect(adapter.engine).to eq(:generic_rest)
      expect(adapter.base_url).to eq("https://api.example.gov")
    end

    it "initializes from a SwayLocale instance extracting legislation_rules" do
      adapter = described_class.new(maryland)
      expect(adapter.engine).to eq(:generic_html)
      expect(adapter.base_url).to eq("https://mgaleg.maryland.gov")
    end

    it "initializes from an object directly responding to legislation_rules" do
      duck_double = double(
        "LegislationRuleHolder",
        legislation_rules: {
          retrieval: "generic_rest",
          parsing: "generic_rest",
          base_url: "https://duck.example.gov",
          metadata_mapping: {external_id: "$.id"}
        }
      )
      adapter = described_class.new(duck_double)
      expect(adapter.retrieval).to eq(:generic_rest)
      expect(adapter.parsing).to eq(:generic_rest)
      expect(adapter.base_url).to eq("https://duck.example.gov")
    end

    it "initializes from an object responding to jurisdiction_rules" do
      rules_obj = double(
        "JurisdictionRulesHolder",
        jurisdiction_rules: double(
          "JurisdictionRules",
          legislation_rules: {
            retrieval: "generic_html",
            parsing: "generic_html",
            base_url: "https://rules.example.gov"
          }
        )
      )
      adapter = described_class.new(rules_obj)
      expect(adapter.retrieval).to eq(:generic_html)
      expect(adapter.parsing).to eq(:generic_html)
      expect(adapter.base_url).to eq("https://rules.example.gov")
    end
  end

  describe "#discover error reporting" do
    it "raises BillProcessingError reporting unsupported legislation retrieval when retrieval is unrecognized" do
      adapter = described_class.new({
        retrieval: "unsupported_transport",
        parsing: "generic_rest",
        engine: "generic_rest"
      })
      test_locale = instance_double(SwayLocale, name: "test-locale")
      expect {
        adapter.discover(sway_locale: test_locale)
      }.to raise_error(BillProcessingError, "fetch_bills: unsupported legislation retrieval :unsupported_transport")
    end
  end

  describe "#discover with generic_rest engine" do
    it "discovers bills from REST API response and maps metadata" do
      stubs = Faraday::Adapter::Test::Stubs.new
      json_body = {
        bills: [
          {number: "HB101", title: "Test Health Bill", originChamber: "House", introDate: "2026-01-15"}
        ]
      }.to_json
      stubs.get("/bills") { [200, {"content-type" => "application/json"}, json_body] }

      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_rest",
        base_url: "https://api.example.gov",
        endpoints: {bills: "/bills"},
        metadata_mapping: {
          external_id: "$.number",
          title: "$.title",
          chamber: "$.originChamber",
          introduction_date: "$.introDate"
        }
      }, connection: conn)

      results = adapter.discover(sway_locale: maryland)
      expect(results.size).to eq(1)
      first = results.first
      expect(first[:external_id]).to eq("HB101")
      expect(first[:title]).to eq("Test Health Bill")
      expect(first[:chamber]).to eq("House")
      expect(first[:introduction_date]).to eq("2026-01-15")
      expect(first[:matter_id]).to be_a(Integer)
    end

    it "filters to single bill when run_bill is specified" do
      stubs = Faraday::Adapter::Test::Stubs.new
      json_body = {
        bills: [
          {number: "HB101", title: "Test Health Bill", originChamber: "House"},
          {number: "SB202", title: "Test Education Bill", originChamber: "Senate"}
        ]
      }.to_json
      stubs.get("/bills") { [200, {"content-type" => "application/json"}, json_body] }

      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_rest",
        base_url: "https://api.example.gov",
        endpoints: {bills: "/bills"},
        metadata_mapping: {
          external_id: "$.number",
          title: "$.title",
          chamber: "$.originChamber"
        }
      }, connection: conn)

      run_bill = double("PipelineRunBill", external_id: "SB202")
      results = adapter.discover(sway_locale: maryland, run_bill: run_bill)
      expect(results.size).to eq(1)
      expect(results.first[:external_id]).to eq("SB202")
    end

    it "enforces time budget limits when budget_seconds is exceeded" do
      stubs = Faraday::Adapter::Test::Stubs.new
      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({engine: "generic_rest", base_url: "https://api.example.gov"}, connection: conn)

      results = adapter.discover(sway_locale: maryland, start_time: Time.current.to_f - 100, budget_seconds: 1)
      expect(results).to eq([])
    end

    it "raises BillProcessingError on upstream HTTP 500 error" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/bills") { [500, {}, "Server Error"] }
      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({engine: "generic_rest", base_url: "https://api.example.gov", endpoints: {bills: "/bills"}}, connection: conn)

      expect {
        adapter.discover(sway_locale: maryland)
      }.to raise_error(BillProcessingError, /fetch_bills.*500/)
    end

    it "safely skips null, string, and integer elements in bill arrays without raising NoMethodError" do
      stubs = Faraday::Adapter::Test::Stubs.new
      json_body = {
        bills: [
          nil,
          "invalid string",
          12345,
          {number: "HB101", title: "Valid Health Bill", originChamber: "House"},
          nil,
          {number: "HB102", title: "Valid Education Bill", originChamber: "Senate"}
        ]
      }.to_json
      stubs.get("/bills") { [200, {"content-type" => "application/json"}, json_body] }

      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_rest",
        base_url: "https://api.example.gov",
        endpoints: {bills: "/bills"},
        metadata_mapping: {external_id: "$.number", title: "$.title", chamber: "$.originChamber"}
      }, connection: conn)

      results = adapter.discover(sway_locale: maryland)
      expect(results.size).to eq(2)
      expect(results.pluck(:external_id)).to eq(["HB101", "HB102"])
    end

    it "returns empty array on empty REST response {}" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/bills") { [200, {"content-type" => "application/json"}, "{}"] }

      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_rest",
        base_url: "https://api.example.gov",
        endpoints: {bills: "/bills"}
      }, connection: conn)

      results = adapter.discover(sway_locale: maryland)
      expect(results).to eq([])
    end

    it "returns empty array on sparse array containing only null elements [null, null]" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/bills") { [200, {"content-type" => "application/json"}, "[null, null]"] }

      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_rest",
        base_url: "https://api.example.gov",
        endpoints: {bills: "/bills"}
      }, connection: conn)

      results = adapter.discover(sway_locale: maryland)
      expect(results).to eq([])
    end

    it "skips bill items missing external_id or with blank external_id" do
      stubs = Faraday::Adapter::Test::Stubs.new
      json_body = {
        bills: [
          {title: "Missing ID"},
          {number: "", title: "Blank ID"},
          {number: "   ", title: "Whitespace ID"},
          {number: "HB200", title: "Valid Bill"}
        ]
      }.to_json
      stubs.get("/bills") { [200, {"content-type" => "application/json"}, json_body] }

      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_rest",
        base_url: "https://api.example.gov",
        endpoints: {bills: "/bills"},
        metadata_mapping: {external_id: "$.number", title: "$.title"}
      }, connection: conn)

      results = adapter.discover(sway_locale: maryland)
      expect(results.size).to eq(1)
      expect(results.first[:external_id]).to eq("HB200")
    end
  end

  describe "#discover with unavailable engine" do
    it "returns empty array without network calls" do
      adapter = described_class.new({engine: "unavailable"})
      expect(adapter.discover(sway_locale: maryland)).to eq([])
    end
  end

  describe "#backfill_bill" do
    let(:bill) { create(:bill, external_id: "HB101", sway_locale: maryland, title: "Test Bill") }

    it "downloads PDF and attaches to bill artifacts, appending to ready" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/bills/hb101.pdf") { [200, {"content-type" => "application/pdf"}, pdf_fixture] }

      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({engine: "generic_rest", base_url: "https://api.example.gov"}, connection: conn)

      ready = []
      undiscovered = []

      meta_dir = Legislation::Paths.bill_artifact_dir(bill.external_id, sway_locale: maryland.name)
      FileUtils.mkdir_p(meta_dir)
      File.write(meta_dir.join("metadata.json"), {
        external_id: "HB101",
        matter_id: 100101,
        title: "Test Bill",
        pdf_url: "https://api.example.gov/bills/hb101.pdf",
        pdf_filename: "hb101.pdf"
      }.to_json)

      adapter.backfill_bill(bill, ready: ready, undiscovered: undiscovered)

      expect(ready).to eq([["HB101", maryland.name, 100101]])
      expect(undiscovered).to be_empty

      downloaded_pdf = meta_dir.join("hb101.pdf")
      expect(downloaded_pdf).to exist
      expect(downloaded_pdf.binread).to start_with("%PDF")
    end

    it "appends to undiscovered when PDF download fails" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/bills/hb101.pdf") { [404, {}, "Not Found"] }

      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({engine: "generic_rest", base_url: "https://api.example.gov"}, connection: conn)

      ready = []
      undiscovered = []

      meta_dir = Legislation::Paths.bill_artifact_dir(bill.external_id, sway_locale: maryland.name)
      FileUtils.mkdir_p(meta_dir)
      File.write(meta_dir.join("metadata.json"), {
        external_id: "HB101",
        pdf_url: "https://api.example.gov/bills/hb101.pdf",
        pdf_filename: "hb101.pdf"
      }.to_json)

      adapter.backfill_bill(bill, ready: ready, undiscovered: undiscovered)

      expect(ready).to be_empty
      expect(undiscovered).to eq([["HB101", maryland.name]])
    end

    it "guards against corrupted metadata.json without raising NoMethodError" do
      adapter = described_class.new({engine: "generic_rest", base_url: "https://api.example.gov"})
      meta_dir = Legislation::Paths.bill_artifact_dir(bill.external_id, sway_locale: maryland.name)
      FileUtils.mkdir_p(meta_dir)
      File.write(meta_dir.join("metadata.json"), "{corrupt json")

      ready = []
      undiscovered = []

      expect {
        adapter.backfill_bill(bill, ready: ready, undiscovered: undiscovered)
      }.not_to raise_error

      expect(ready).to be_empty
      expect(undiscovered).to eq([["HB101", maryland.name]])
    end

    it "handles empty metadata.json file without raising NoMethodError" do
      adapter = described_class.new({engine: "generic_rest", base_url: "https://api.example.gov"})
      meta_dir = Legislation::Paths.bill_artifact_dir(bill.external_id, sway_locale: maryland.name)
      FileUtils.mkdir_p(meta_dir)
      File.write(meta_dir.join("metadata.json"), "")

      ready = []
      undiscovered = []

      expect {
        adapter.backfill_bill(bill, ready: ready, undiscovered: undiscovered)
      }.not_to raise_error

      expect(undiscovered).to eq([["HB101", maryland.name]])
    end
  end

  describe "#discover with generic_html engine" do
    [
      {configured: "2026Special", upstream: "2025RS", name: "2025 Regular Session", expected: "2026Special"},
      {configured: " \t ", upstream: "2025RS", name: "2025 Regular Session", expected: "2025RS"},
      {configured: nil, upstream: " \t ", name: "2025RS", expected: "2025RS"}
    ].each do |scenario|
      # @lat: [[generic-html-session-tests#Session precedence]]
      it "discovers bills using session #{scenario[:expected]} with config #{scenario[:configured].inspect} and upstream #{scenario[:upstream].inspect}" do
        session = instance_double(LegislativeSession, name: scenario[:name], upstream_name: scenario[:upstream])
        locale = instance_double(SwayLocale, current_legislative_session: session)
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/mgawebsite/Legislation/Index?ys=#{scenario[:expected]}") do
          [200, {"content-type" => "text/html"}, '<table id="billIndex"><tbody><tr><td><a>HB0001</a></td><td>Session bill</td></tr></tbody></table>']
        end
        connection = Faraday.new("https://example.gov") { |faraday| faraday.adapter :test, stubs }
        adapter = described_class.new({retrieval: "generic_html", base_url: "https://example.gov", session: scenario[:configured]}, connection: connection)

        results = adapter.discover(sway_locale: locale)

        expect(results.pluck(:external_id)).to eq(["HB0001"])
        expect(results.first[:pdf_url]).to eq("https://example.gov/#{scenario[:expected]}/bills/hb/hb0001f.pdf")
      end
    end

    # @lat: [[generic-html-session-tests#Locale documents cannot supply missing sessions]]
    it "rejects HTML discovery when only the locale document provides an active session" do
      empty_locale = create(:sway_locale, city: "empty-city", state: "maryland", country: "united_states")
      document = SwayLocale::DocumentReader::Document.new({
        "source_rules" => {"legislation_rules" => {"retrieval" => "generic_html"}},
        "legislative_sessions" => [{
          "name" => "2028 Regular Session",
          "upstream_name" => "2028RS",
          "start_date" => "2028-01-01",
          "end_date" => "2028-12-31",
          "active" => true
        }]
      })
      allow(SwayLocale::DocumentReader).to receive(:find).with(empty_locale.name).and_return(document)
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mgawebsite/Legislation/Index?ys=2028RS") do
        [200, {"content-type" => "text/html"}, '<table id="billIndex"><tbody><tr><td><a>HB0001</a></td><td>Document session bill</td></tr></tbody></table>']
      end
      connection = Faraday.new("https://example.gov") { |faraday| faraday.adapter :test, stubs }
      html_adapter = described_class.new({retrieval: "generic_html", base_url: "https://example.gov"}, connection: connection)

      expect {
        html_adapter.discover(sway_locale: empty_locale)
      }.to raise_error(BillProcessingError, "No active session found for HTML legislation discovery")
    end

    # @lat: [[generic-html-session-tests#Missing locale rejects discovery]]
    it "raises BillProcessingError in discover_html_bills when sway_locale is nil" do
      html_adapter = described_class.new({retrieval: "generic_html", base_url: "https://example.gov"})

      expect {
        html_adapter.discover(sway_locale: nil)
      }.to raise_error(BillProcessingError, "No active session found for HTML legislation discovery")
    end

    # @lat: [[generic-html-session-tests#Whitespace names reject discovery]]
    it "rejects HTML discovery when configured and database session names are whitespace" do
      session = instance_double(LegislativeSession, name: " \t ", upstream_name: " \n ")
      locale = instance_double(SwayLocale, current_legislative_session: session)
      html_adapter = described_class.new({retrieval: "generic_html", base_url: "https://example.gov", session: " \t "})

      expect {
        html_adapter.discover(sway_locale: locale)
      }.to raise_error(BillProcessingError, "No active session found for HTML legislation discovery")
    end

    it "discovers bills from MGA HTML index table" do
      stubs = Faraday::Adapter::Test::Stubs.new
      html_body = <<~HTML
        <html>
          <body>
            <table id="billIndex">
              <tbody>
                <tr>
                  <td><a href="/details/hb0001">HB0001</a></td>
                  <td>An Act concerning Public Health</td>
                </tr>
                <tr>
                  <td><a href="/details/sb0002">SB0002</a></td>
                  <td>An Act concerning Education</td>
                </tr>
              </tbody>
            </table>
          </body>
        </html>
      HTML
      stubs.get("/mgawebsite/Legislation/Index?ys=#{current_session_name}") { [200, {"content-type" => "text/html"}, html_body] }

      conn = Faraday.new("https://mgaleg.maryland.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_html",
        base_url: "https://mgaleg.maryland.gov",
        endpoints: {index: "/mgawebsite/Legislation/Index?ys=:session"}
      }, connection: conn)

      results = adapter.discover(sway_locale: maryland)
      expect(results.size).to eq(2)
      expect(results.first[:external_id]).to eq("HB0001")
      expect(results.first[:title]).to eq("An Act concerning Public Health")
      expect(results.first[:matter_id]).to eq(100_001)
      expect(results.first[:pdf_url]).to include("/#{current_session_name}/bills/hb/hb0001f.pdf")
    end

    it "discovers single bill when run_bill is provided" do
      stubs = Faraday::Adapter::Test::Stubs.new
      html_body = <<~HTML
        <html>
          <body>
            <h1 class="bill-title">Public Health Standards Act</h1>
            <a href="/#{current_session_name}/bills/hb/hb0001f.pdf">PDF Version</a>
          </body>
        </html>
      HTML
      stubs.get("/mgawebsite/Legislation/Details/hb0001?ys=#{current_session_name}") { [200, {"content-type" => "text/html"}, html_body] }

      conn = Faraday.new("https://mgaleg.maryland.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_html",
        base_url: "https://mgaleg.maryland.gov",
        endpoints: {details: "/mgawebsite/Legislation/Details/:external_id?ys=:session"}
      }, connection: conn)

      run_bill = double("PipelineRunBill", external_id: "HB0001")
      results = adapter.discover(sway_locale: maryland, run_bill: run_bill)
      expect(results.size).to eq(1)
      expect(results.first[:external_id]).to eq("HB0001")
      expect(results.first[:title]).to eq("Public Health Standards Act")
      expect(results.first[:pdf_url]).to eq("https://mgaleg.maryland.gov/#{current_session_name}/bills/hb/hb0001f.pdf")
    end
  end

  describe "URL token interpolation and pagination in generic_rest" do
    it "interpolates URL tokens in endpoints" do
      stubs = Faraday::Adapter::Test::Stubs.new
      json_body = {bills: [{number: "SB500", title: "Session Bill"}]}.to_json
      stubs.get("/api/v1/2026/senate/bills") { [200, {"content-type" => "application/json"}, json_body] }

      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_rest",
        base_url: "https://api.example.gov",
        session: "2026",
        chamber: "senate",
        endpoints: {bills: "/api/v1/:session/:chamber/bills"},
        metadata_mapping: {external_id: "$.number", title: "$.title"}
      }, connection: conn)

      results = adapter.discover(sway_locale: maryland)
      expect(results.size).to eq(1)
      expect(results.first[:external_id]).to eq("SB500")
    end

    it "interpolates :external_id when run_bill is provided" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/bills/HB999") do
        [200, {"content-type" => "application/json"}, {bills: [{number: "HB999", title: "Single Bill"}]}.to_json]
      end

      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_rest",
        base_url: "https://api.example.gov",
        endpoints: {bills: "/bills/:external_id"},
        metadata_mapping: {external_id: "$.number", title: "$.title"}
      }, connection: conn)

      run_bill = double("PipelineRunBill", external_id: "HB999")
      results = adapter.discover(sway_locale: maryland, run_bill: run_bill)
      expect(results.size).to eq(1)
      expect(results.first[:external_id]).to eq("HB999")
    end

    it "paginates across multiple pages following next links" do
      stubs = Faraday::Adapter::Test::Stubs.new
      page1 = {bills: [{number: "HB101", title: "Bill 1"}], pagination: {next: "/bills?page=2"}}.to_json
      page2 = {bills: [{number: "HB102", title: "Bill 2"}], pagination: {next: nil}}.to_json

      stubs.get("/bills") { [200, {"content-type" => "application/json"}, page1] }
      stubs.get("/bills?page=2") { [200, {"content-type" => "application/json"}, page2] }

      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_rest",
        base_url: "https://api.example.gov",
        endpoints: {bills: "/bills"},
        metadata_mapping: {external_id: "$.number", title: "$.title"}
      }, connection: conn)

      results = adapter.discover(sway_locale: maryland)
      expect(results.pluck(:external_id)).to eq(["HB101", "HB102"])
    end

    it "stops pagination early when budget_seconds is exceeded during multi-page fetching" do
      stubs = Faraday::Adapter::Test::Stubs.new
      page1 = {
        bills: [{number: "HB101", title: "Bill Page 1"}],
        pagination: {next: "/bills?page=2"}
      }.to_json

      stubs.get("/bills") { [200, {"content-type" => "application/json"}, page1] }

      conn = Faraday.new("https://api.example.gov") { |f| f.adapter :test, stubs }
      adapter = described_class.new({
        engine: "generic_rest",
        base_url: "https://api.example.gov",
        endpoints: {bills: "/bills"},
        metadata_mapping: {external_id: "$.number", title: "$.title"}
      }, connection: conn)

      allow(adapter).to receive(:budget_exceeded?).and_return(false, false, true)

      results = adapter.discover(sway_locale: maryland, start_time: Time.current.to_f, budget_seconds: 5)
      expect(results.size).to eq(1)
      expect(results.first[:external_id]).to eq("HB101")
    end
  end

  describe ".matter_id_for" do
    it "hashes external IDs deterministically into positive integers" do
      id1 = described_class.matter_id_for("HB101")
      id2 = described_class.matter_id_for("HB101")
      expect(id1).to eq(id2)
      expect(id1).to be_a(Integer)
      expect(id1).to be > 0
    end
  end

  describe "Removal of fallback checks for legacy source properties (TASK-ok5ox.27: Remove fallback checks for legacy source properties in GenericLegislationAdapter)" do
    it "strictly obeys legislation_rules and ignores legacy legislation_source" do
      rules = double(
        "JurisdictionRules",
        legislation_rules: {engine: "generic_rest", base_url: "https://example.gov"},
        legislation_source: :legistar
      )
      adapter = described_class.new(rules)
      expect(adapter.engine).to eq(:generic_rest)
    end

    it "does not fall back to legislation_source when legislation_rules is empty" do
      rules = double(
        "JurisdictionRules",
        legislation_rules: {},
        legislation_source: :unavailable
      )
      adapter = described_class.new(rules)
      expect(adapter.engine).to eq(:generic_rest)
    end
  end

  describe "Legistar discovery and upstream querying (TASK-ok5ox.21)" do
    it "scopes legistar_client to the effective locale's declared namespace" do
      adapter = described_class.new(baltimore)
      client = adapter.legistar_client(baltimore)
      expect(client).to be_a(Legistar::Client)
      expect(client.client).to eq("baltimore")
    end

    it "raises ArgumentError when target locale does not declare a Legistar client" do
      adapter = described_class.new({engine: "legistar"})
      congress_locale = SwayLocale.find_by(city: "congress", state: "congress") ||
        create(:sway_locale, city: "congress", state: "congress", country: "united_states")

      expect { adapter.legistar_client(congress_locale) }.to raise_error(
        ArgumentError,
        /No client configured for Legistar legislation adapter/
      )
    end

    it "does not fall back to target_locale.city when client is not declared in rules" do
      rules = instance_double(
        SwayLocale::JurisdictionRules,
        legislation_rules: {retrieval: "legistar"}
      )
      locale = instance_double(SwayLocale, name: "baltimore-maryland-united_states", city: "baltimore", jurisdiction_rules: rules)
      adapter = described_class.new({engine: "legistar"})

      expect { adapter.legistar_client(locale) }.to raise_error(
        ArgumentError,
        "No client configured for Legistar legislation adapter"
      )
    end

    it "memoizes client per namespace without leaking across locales" do
      adapter = described_class.new({engine: "legistar"})
      second_rules = instance_double(
        SwayLocale::JurisdictionRules,
        legislation_rules: {client: "seattle"},
        accepted_matter_types: ["Bill"]
      )
      second_locale = instance_double(SwayLocale, name: "seattle-washington-united_states", jurisdiction_rules: second_rules)

      client1 = adapter.legistar_client(baltimore)
      client2 = adapter.legistar_client(second_locale)

      expect(client1.client).to eq("baltimore")
      expect(client2.client).to eq("seattle")
      expect(adapter.legistar_client(baltimore)).to be(client1)
      expect(adapter.legistar_client(second_locale)).to be(client2)
      expect(client1).not_to be(client2)
    end

    it "uses the locale's accepted_matter_types in fetch_all_legistar_matters filter" do
      custom_rules = instance_double(
        SwayLocale::JurisdictionRules,
        legislation_rules: {engine: "legistar", client: "baltimore", accepted_matter_types: %w[Ordinance CouncilBill]},
        accepted_matter_types: %w[Ordinance CouncilBill]
      )
      custom_locale = instance_double(SwayLocale, name: "custom-locale", jurisdiction_rules: custom_rules)
      adapter = described_class.new(custom_rules)

      legistar_mock = instance_double(Legistar::Client)
      allow(Legistar::Client).to receive(:new).and_return(legistar_mock)

      expect(legistar_mock).to receive(:get).with(
        "Matters",
        hash_including(filter: a_string_including("(MatterTypeName eq 'Ordinance' or MatterTypeName eq 'CouncilBill')"))
      ).and_return([])

      adapter.send(:fetch_all_legistar_matters, nil, custom_locale)
    end
  end

  describe "jurisdiction decoupling (TASK-ok5ox.44: Remove jurisdiction hardcoding from GenericLegislationAdapter)" do
    describe "base_url requirement for HTML engines" do
      it "raises BillProcessingError when base_url is blank in generic_html discovery" do
        stubs = Faraday::Adapter::Test::Stubs.new
        html_body = <<~HTML
          <html><body><table id="billIndex"><tbody><tr><td><a href="/details/hb0001">HB0001</a></td><td>Title</td></tr></tbody></table></body></html>
        HTML
        stubs.get("/mgawebsite/Legislation/Index?ys=#{current_session_name}") { [200, {"content-type" => "text/html"}, html_body] }
        conn = Faraday.new { |f| f.adapter :test, stubs }

        adapter = described_class.new({
          engine: "generic_html",
          base_url: nil,
          endpoints: {index: "/mgawebsite/Legislation/Index?ys=:session"}
        }, connection: conn)

        expect {
          adapter.discover(sway_locale: maryland)
        }.to raise_error(BillProcessingError, /fetch_bills: base_url is required for legislation engine :generic_html/)
      end

      it "raises BillProcessingError in backfill_bill when base_url is blank without defaulting to Maryland" do
        bill = create(:bill, sway_locale: maryland, external_id: "HB0001", title: "Test")
        adapter = described_class.new({
          engine: "generic_html",
          base_url: nil
        })
        allow(adapter).to receive(:load_metadata).and_return(nil)

        expect {
          adapter.backfill_bill(bill)
        }.to raise_error(BillProcessingError, /fetch_bills: base_url is required for legislation engine :generic_html/)
      end
    end

    describe "congress discovery routing" do
      let(:congress_locale) { create(:sway_locale, city: "congress", state: "congress", country: "united_states") }
      let(:other_locale) { create(:sway_locale, city: "other", state: "somewhere", country: "united_states") }

      it "routes to discover_congress_bills when engine is congress_dot_gov regardless of locale name" do
        adapter = described_class.new({engine: "congress_dot_gov"})
        allow(adapter).to receive(:discover_congress_bills).and_return([])

        adapter.discover(sway_locale: other_locale)
        expect(adapter).to have_received(:discover_congress_bills)
      end

      it "routes to discover_rest_bills when engine is generic_rest even if locale name starts with congress" do
        adapter = described_class.new({engine: "generic_rest"})
        allow(adapter).to receive(:discover_rest_bills).and_return([])
        allow(adapter).to receive(:discover_congress_bills)

        adapter.discover(sway_locale: congress_locale)
        expect(adapter).to have_received(:discover_rest_bills)
        expect(adapter).not_to have_received(:discover_congress_bills)
      end
    end
  end

  describe "Retrieval and parsing rules migration (TASK-ok5ox.46: Migrate GenericLegislationAdapter to new retrieval and parsing rules)" do
    describe "configuration extraction and fallback derivation" do
      it "derives @retrieval and @parsing from explicit retrieval and parsing keys" do
        adapter = described_class.new({
          retrieval: "generic_html",
          parsing: "generic_html",
          base_url: "https://example.gov"
        })
        expect(adapter.retrieval).to eq(:generic_html)
        expect(adapter.parsing).to eq(:generic_html)
        expect(adapter.engine).to eq(:generic_html)
      end

      it "derives @retrieval and @parsing from alias keys retrieval_strategy and parser_format" do
        adapter = described_class.new({
          retrieval_strategy: "congress_dot_gov",
          parser_format: "congress_dot_gov",
          base_url: "https://api.congress.gov"
        })
        expect(adapter.retrieval).to eq(:congress_dot_gov)
        expect(adapter.parsing).to eq(:congress_dot_gov)
        expect(adapter.engine).to eq(:congress_dot_gov)
      end

      it "falls back @retrieval and @parsing to legacy engine parameter" do
        adapter = described_class.new({
          engine: "legistar",
          client: "baltimore"
        })
        expect(adapter.engine).to eq(:legistar)
        expect(adapter.retrieval).to eq(:legistar)
        expect(adapter.parsing).to eq(:legistar)
      end

      it "defaults to :generic_rest when config is empty" do
        adapter = described_class.new({})
        expect(adapter.engine).to eq(:generic_rest)
        expect(adapter.retrieval).to eq(:generic_rest)
        expect(adapter.parsing).to eq(:generic_rest)
      end

      it "supports decoupled retrieval and parsing configurations" do
        adapter = described_class.new({
          retrieval: "generic_rest",
          parsing: "congress_dot_gov",
          base_url: "https://api.example.gov"
        })
        expect(adapter.retrieval).to eq(:generic_rest)
        expect(adapter.parsing).to eq(:congress_dot_gov)
        expect(adapter.engine).to eq(:generic_rest)
      end

      it "extracts retrieval and parsing from SwayLocale instance" do
        adapter = described_class.new(baltimore)
        expect(adapter.retrieval).to eq(:legistar)
        expect(adapter.parsing).to eq(:legistar)
        expect(adapter.engine).to eq(:legistar)
      end
    end

    describe "discovery branching on @retrieval" do
      it "branches discover to discover_rest_bills when retrieval is generic_rest" do
        adapter = described_class.new({retrieval: "generic_rest", parsing: "generic_rest", base_url: "https://api.example.gov"})
        allow(adapter).to receive(:discover_rest_bills).and_return([])
        allow(adapter).to receive(:discover_congress_bills)

        adapter.discover(sway_locale: maryland)
        expect(adapter).to have_received(:discover_rest_bills)
        expect(adapter).not_to have_received(:discover_congress_bills)
      end

      it "branches discover to discover_congress_bills when retrieval is congress_dot_gov" do
        adapter = described_class.new({retrieval: "congress_dot_gov", parsing: "congress_dot_gov", base_url: "https://api.congress.gov"})
        allow(adapter).to receive(:discover_congress_bills).and_return([])

        adapter.discover(sway_locale: maryland)
        expect(adapter).to have_received(:discover_congress_bills)
      end

      it "branches discover to discover_html_bills when retrieval is generic_html" do
        adapter = described_class.new({retrieval: "generic_html", parsing: "generic_html", base_url: "https://mgaleg.maryland.gov"})
        allow(adapter).to receive(:discover_html_bills).and_return([])

        adapter.discover(sway_locale: maryland)
        expect(adapter).to have_received(:discover_html_bills)
      end

      it "branches discover to discover_legistar when retrieval is legistar" do
        adapter = described_class.new({retrieval: "legistar", parsing: "legistar", client: "baltimore"})
        allow(adapter).to receive(:discover_legistar).and_return([])

        adapter.discover(sway_locale: maryland)
        expect(adapter).to have_received(:discover_legistar)
      end

      it "returns empty array when retrieval is unavailable without issuing network calls" do
        adapter = described_class.new({retrieval: "unavailable", parsing: "unavailable"})
        expect(adapter.discover(sway_locale: maryland)).to eq([])
      end
    end

    describe "repair_missing_metadata branching on @retrieval" do
      it "returns false immediately when retrieval is not legistar" do
        adapter = described_class.new({retrieval: "generic_rest", parsing: "legistar"})
        expect(adapter.repair_missing_metadata("1001", baltimore)).to be(false)
      end

      it "executes repair when retrieval is legistar" do
        adapter = described_class.new({retrieval: "legistar", parsing: "legistar", client: "baltimore"})
        client_double = instance_double(Legistar::Client)
        allow(adapter).to receive(:legistar_client).and_return(client_double)
        allow(client_double).to receive(:get).and_return([])

        expect(adapter.repair_missing_metadata("1001", baltimore)).to be(false)
        expect(client_double).to have_received(:get)
      end
    end

    describe "status mapping branching on @parsing" do
      it "delegates to Legistar::StatusMapper when parsing is legistar" do
        adapter = described_class.new({retrieval: "generic_rest", parsing: "legistar"})
        expect(adapter.map_status("Adopted")).to eq(Bill::Status::PASSED)
        expect(adapter.map_status("In Committee")).to eq(Bill::Status::COMMITTEE)
        expect(adapter.map_status("Vetoed by Mayor")).to eq(Bill::Status::VETOED)
        expect(adapter.map_status("Failed")).to eq(Bill::Status::FAILED)
      end

      it "passes through raw status and skips Legistar mapper when parsing is generic_rest" do
        adapter = described_class.new({retrieval: "generic_rest", parsing: "generic_rest"})
        expect(adapter.map_status("Under Review")).to eq("Under Review")
      end

      it "applies custom status_mapping when parsing is generic_rest" do
        adapter = described_class.new({
          retrieval: "generic_rest",
          parsing: "generic_rest",
          status_mapping: {
            "under review" => Bill::Status::COMMITTEE,
            "enacted into law" => Bill::Status::PASSED
          }
        })
        expect(adapter.map_status("under review")).to eq(Bill::Status::COMMITTEE)
        expect(adapter.map_status("Enacted Into Law")).to eq(Bill::Status::PASSED)
      end

      it "returns canonical Bill::STATUSES without mapping regardless of parser" do
        adapter = described_class.new({retrieval: "generic_rest", parsing: "generic_rest"})
        Bill::STATUSES.each do |st|
          expect(adapter.map_status(st)).to eq(st)
        end
      end
    end

    describe "Legistar client clean config extraction without top-level client key" do
      it "extracts client cleanly from sway_locale legislation_rules without requiring top-level client key" do
        locale_rules = instance_double(
          SwayLocale::JurisdictionRules,
          legislation_rules: {retrieval: "legistar", parsing: "legistar", client: "annapolis"}
        )
        locale = instance_double(SwayLocale, name: "annapolis-maryland-united_states", jurisdiction_rules: locale_rules)

        adapter = described_class.new({retrieval: "legistar", parsing: "legistar"})
        client = adapter.legistar_client(locale)

        expect(client).to be_a(Legistar::Client)
        expect(client.client).to eq("annapolis")
      end

      it "does not leak client when adapter initialized with one locale is queried with another" do
        baltimore_rules = instance_double(
          SwayLocale::JurisdictionRules,
          legislation_rules: {retrieval: "legistar", parsing: "legistar", client: "baltimore"}
        )
        baltimore_loc = instance_double(SwayLocale, name: "baltimore", jurisdiction_rules: baltimore_rules)

        annapolis_rules = instance_double(
          SwayLocale::JurisdictionRules,
          legislation_rules: {retrieval: "legistar", parsing: "legistar", client: "annapolis"}
        )
        annapolis_loc = instance_double(SwayLocale, name: "annapolis", jurisdiction_rules: annapolis_rules)

        # Initialized with Baltimore
        adapter = described_class.new(baltimore_loc)

        client1 = adapter.legistar_client(baltimore_loc)
        client2 = adapter.legistar_client(annapolis_loc)

        expect(client1.client).to eq("baltimore")
        expect(client2.client).to eq("annapolis")
        expect(client1).not_to be(client2)
      end
    end
  end

  describe "#determine_session" do
    let(:adapter) { described_class.new({retrieval: "generic_html", base_url: "https://mgaleg.maryland.gov"}) }

    it "uses @config[:session] when explicitly configured" do
      config_adapter = described_class.new({session: "2026Special"})
      expect(config_adapter.send(:determine_session, nil)).to eq("2026Special")
    end

    it "prioritizes locale.current_legislative_session.upstream_name when present" do
      session = instance_double(LegislativeSession, name: "2025 Regular Session", upstream_name: "2025RS")
      locale = instance_double(SwayLocale, current_legislative_session: session)
      test_adapter = described_class.new({})
      expect(test_adapter.send(:determine_session, locale)).to eq("2025RS")
    end

    it "returns the active legislative session name from the locale database record" do
      test_locale = create(:sway_locale, city: "testloc", state: "maryland", country: "united_states")
      create(:legislative_session, :active, sway_locale: test_locale, name: "2027Special")
      expect(adapter.send(:determine_session, test_locale)).to eq("2027Special")
    end

    it "returns nil when the database has no active legislative session" do
      empty_locale = create(:sway_locale, city: "empty", state: "maryland", country: "united_states")
      expect(adapter.send(:determine_session, empty_locale)).to be_nil
    end

    it "uses adapter config when locale has no active session" do
      config_adapter = described_class.new({
        retrieval: "generic_html",
        base_url: "https://example.gov",
        session: "2024Special"
      })
      expect(config_adapter.send(:determine_session, baltimore)).to eq("2024Special")
    end

    it "returns nil when there is no active session config" do
      empty_adapter = described_class.new({})
      expect(empty_adapter.send(:determine_session, nil)).to be_nil
    end
  end

  describe "discover_html_bills session presence enforcement" do
    it "rejects discovery when session cannot be determined" do
      empty_locale = create(:sway_locale, city: "nosession", state: "maryland", country: "united_states")
      html_adapter = described_class.new({retrieval: "generic_html", base_url: "https://example.gov"})
      expect {
        html_adapter.discover(sway_locale: empty_locale)
      }.to raise_error(BillProcessingError, "No active session found for HTML legislation discovery")
    end
  end

  describe "Legistar exception encapsulation" do
    let(:adapter) { described_class.new({retrieval: "legistar", parsing: "legistar", client: "baltimore"}) }
    let(:client_double) { instance_double(Legistar::Client) }

    before do
      allow(adapter).to receive(:legistar_client).and_return(client_double)
    end

    it "encapsulates Legistar::Client::Error in BillProcessingError during discover" do
      allow(client_double).to receive(:get).and_raise(Legistar::Client::Error.new("connection reset"))
      expect {
        adapter.discover(sway_locale: baltimore)
      }.to raise_error(BillProcessingError, /fetch_bills: Legistar::Client::Error: connection reset/)
    end

    it "encapsulates Faraday::Error in BillProcessingError during discover" do
      allow(client_double).to receive(:get).and_raise(Faraday::ConnectionFailed.new("failed to connect"))
      expect {
        adapter.discover(sway_locale: baltimore)
      }.to raise_error(BillProcessingError, /fetch_bills: Faraday::ConnectionFailed: failed to connect/)
    end

    it "encapsulates Legistar::Client::HttpError in BillProcessingError during discover" do
      allow(adapter).to receive(:fetch_all_legistar_matters).and_raise(Legistar::Client::HttpError.new(status: 500, path: "Matters", body: "error"))
      expect {
        adapter.discover(sway_locale: baltimore)
      }.to raise_error(BillProcessingError, /fetch_bills: Legistar::Client::HttpError/)
    end

    it "safely returns false from repair_missing_metadata on Legistar::Client::Error" do
      allow(client_double).to receive(:get).and_raise(Legistar::Client::Error.new("timeout"))
      expect(adapter.repair_missing_metadata("1001", baltimore)).to be(false)
    end

    it "safely returns false from repair_missing_metadata on Faraday::Error" do
      allow(client_double).to receive(:get).and_raise(Faraday::TimeoutError.new("timeout"))
      expect(adapter.repair_missing_metadata("1001", baltimore)).to be(false)
    end

    it "safely returns empty array from fetch_attachments on Legistar::Client::Error" do
      allow(client_double).to receive(:matter_attachments).and_raise(Legistar::Client::Error.new("transport error"))
      expect(adapter.fetch_attachments(12345, baltimore)).to eq([])
    end

    it "safely returns empty array from fetch_attachments on Faraday::Error" do
      allow(client_double).to receive(:matter_attachments).and_raise(Faraday::ConnectionFailed.new("connection failed"))
      expect(adapter.fetch_attachments(12345, baltimore)).to eq([])
    end
  end

  describe "#api_params" do
    it "dynamically reads secret via EnvSecret.read using @config[:api_key_secret]" do
      adapter = described_class.new({api_key_secret: "STATE_CUSTOM_KEY"})
      allow(EnvSecret).to receive(:read).with("STATE_CUSTOM_KEY").and_return("state_token_123")

      params = adapter.send(:api_params)
      expect(params[:api_key]).to eq("state_token_123")
      expect(params[:format]).to eq("json")
    end

    it "does not fall back to CONGRESS_GOV_API_KEY when api_key_secret is nil or absent" do
      adapter = described_class.new({})
      allow(EnvSecret).to receive(:read)

      params = adapter.send(:api_params)
      expect(params).to eq({format: "json"})
      expect(EnvSecret).not_to have_received(:read)
    end
  end

  describe "#published_pdf_urls" do
    let(:conn) { instance_double(Faraday::Connection) }
    let(:response) { instance_double(Faraday::Response, status: 200, body: {textVersions: []}.to_json) }

    it "uses declared api_key_secret when present" do
      adapter = described_class.new({api_key_secret: "MY_SECRET"})
      allow(EnvSecret).to receive(:read).with("MY_SECRET").and_return("secret_value")
      expect(conn).to receive(:get).with("bill/119/hr/1/text", {format: "json", api_key: "secret_value"}).and_return(response)

      urls = adapter.published_pdf_urls(conn, "119", "hr", "1")
      expect(urls).to eq([])
    end

    it "does not fall back to CONGRESS_GOV_API_KEY when api_key_secret is absent" do
      adapter = described_class.new({})
      allow(EnvSecret).to receive(:read)
      expect(conn).to receive(:get).with("bill/119/hr/1/text", {format: "json"}).and_return(response)

      urls = adapter.published_pdf_urls(conn, "119", "hr", "1")
      expect(urls).to eq([])
      expect(EnvSecret).not_to have_received(:read)
    end
  end

  describe "#discover retrieval handling" do
    let(:conn) { instance_double(Faraday::Connection) }

    before do
      @locale = instance_double(SwayLocale)
    end

    it "routes :generic_html to discover_html_bills" do
      adapter = described_class.new({retrieval: "generic_html"})
      allow(adapter).to receive(:default_connection).and_return(conn)
      allow(adapter).to receive(:discover_html_bills).and_return([])

      adapter.discover(sway_locale: @locale)
      expect(adapter).to have_received(:discover_html_bills)
    end

    it "raises BillProcessingError for unmapped legacy :maryland_general_assembly symbol" do
      adapter = described_class.new({retrieval: "maryland_general_assembly"})
      allow(adapter).to receive(:default_connection).and_return(conn)

      expect { adapter.discover(sway_locale: @locale) }
        .to raise_error(BillProcessingError, /unsupported legislation retrieval :maryland_general_assembly/)
    end
  end

  describe "#parse_html_details_page" do
    it "resolves relative PDF links using declared base_url" do
      doc = Nokogiri::HTML(<<~HTML)
        <html>
          <body>
            <h1 class="bill-title">Solar Energy Act</h1>
            <a href="/docs/bills/2026/hb0088.pdf">Download PDF</a>
          </body>
        </html>
      HTML
      adapter = described_class.new({engine: "generic_html", base_url: "https://assembly.state.org"})
      meta = adapter.send(:parse_html_details_page, doc, "HB0088", "2026RS")
      expect(meta[:pdf_url]).to eq("https://assembly.state.org/docs/bills/2026/hb0088.pdf")
    end

    it "preserves absolute PDF links as-is" do
      doc = Nokogiri::HTML(<<~HTML)
        <html>
          <body>
            <h1 class="bill-title">Solar Energy Act</h1>
            <a href="https://cdn.external-host.com/files/hb0088.pdf">Download PDF</a>
          </body>
        </html>
      HTML
      adapter = described_class.new({engine: "generic_html", base_url: "https://assembly.state.org"})
      meta = adapter.send(:parse_html_details_page, doc, "HB0088", "2026RS")
      expect(meta[:pdf_url]).to eq("https://cdn.external-host.com/files/hb0088.pdf")
    end

    it "constructs fallback PDF path with declared base_url when no PDF link in HTML" do
      doc = Nokogiri::HTML("<html><body><h1 class='bill-title'>Text Only</h1></body></html>")
      adapter = described_class.new({engine: "generic_html", base_url: "https://assembly.state.org"})
      meta = adapter.send(:parse_html_details_page, doc, "HB0088", "2026RS")
      expect(meta[:pdf_url]).to eq("https://assembly.state.org/2026RS/bills/hb/hb0088f.pdf")
    end
  end
end
