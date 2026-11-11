# frozen_string_literal: true

require "rails_helper"
require "support/open_legislator_fixture_helpers"

RSpec.describe OpenLegislator::Client do
  include OpenLegislatorFixtureHelpers

  subject(:client) { described_class.new(base_url: base_url) }

  let(:base_url) { "https://api.open-legislator.test/api/v1" }

  def fixture_content(name)
    Rails.root.join("spec", "fixtures", "open_legislator", name).read
  end

  def stub_api(path, body:, status: 200, query: nil)
    clean_path = path.sub(%r{\A/}, "")
    clean_path = "api/v1/#{clean_path}" unless clean_path.start_with?("api/v1/")
    full_url = "https://api.open-legislator.test/#{clean_path}"

    stub = stub_request(:get, full_url)
    stub = stub.with(query: query) if query
    stub.to_return(
      status: status,
      body: body,
      headers: {"Content-Type" => "application/json"}
    )
  end

  describe "initialization and connection" do
    it "uses default base URL when unspecified" do
      default_client = described_class.new
      expect(default_client.base_url).to eq("http://localhost:3000/api/v1")
    end

    it "accepts custom base URL and chomp trailing slashes" do
      custom = described_class.new(base_url: "https://open-leg.example.org/api/v1/")
      expect(custom.base_url).to eq("https://open-leg.example.org/api/v1")
    end

    it "accepts injected connection" do
      conn = instance_double(Faraday::Connection)
      custom = described_class.new(connection: conn)
      expect(custom.conn).to eq(conn)
    end
  end

  describe "#get and #get_raw" do
    it "hits /api/v1/<resource> and parses the JSON response" do
      stub_api(
        "matters",
        body: fixture_content("matters_index_by_file_number.json")
      )

      result = client.get("matters")
      expect(result["data"].first["slug"]).to eq("ordinance-24-0001-housing-affordability")
      expect(result["page"]["last"]).to eq(1)
    end

    it "cleans nil parameters from the query string" do
      stub = stub_api(
        "matters",
        query: {"page" => "2", "limit" => "20"},
        body: fixture_content("matters_index_empty.json")
      )

      client.get("matters", page: 2, limit: 20, file_number: nil)
      expect(stub).to have_been_requested
    end

    it "raises HttpError carrying status, path, and sanitized body on non-2xx response" do
      stub_api("matters/nonexistent", status: 404, body: '{"error":"not_found"}')

      expect {
        client.get("matters/nonexistent")
      }.to raise_error(OpenLegislator::Client::HttpError) do |error|
        expect(error.status).to eq(404)
        expect(error.path).to eq("/api/v1/matters/nonexistent")
        expect(error.message).to include("Open Legislator API HTTP 404")
      end
    end

    it "raises ParseError on non-JSON 2xx body" do
      stub_api("matters", body: "<html>gateway error</html>", status: 200)

      expect {
        client.get("matters")
      }.to raise_error(OpenLegislator::Client::ParseError, /returned a non-JSON body/)
    end

    it "wraps Faraday transport errors in OpenLegislator::Client::Error" do
      stub_request(:get, "https://api.open-legislator.test/api/v1/matters").to_raise(Faraday::ConnectionFailed.new("connection refused"))

      expect {
        client.get("matters")
      }.to raise_error(OpenLegislator::Client::Error, /transport error for \/api\/v1\/matters/)
    end
  end

  describe "#matter" do
    it "raises ArgumentError when slug is blank" do
      expect { client.matter("") }.to raise_error(ArgumentError, "slug is required")
      expect { client.matter(nil) }.to raise_error(ArgumentError, "slug is required")
    end

    it "fetches composite matter and unwraps data hash" do
      stub_api(
        "matters/ordinance-24-0001-housing-affordability",
        body: fixture_content("matter_show_passed.json")
      )

      result = client.matter("ordinance-24-0001-housing-affordability")
      expect(result["slug"]).to eq("ordinance-24-0001-housing-affordability")
      expect(result["file_number"]).to eq("24-0001")
      expect(result["actions"].first["result"]).to eq("pass")
      expect(result["actions"].first["tally"]).to eq("yes" => 14, "no" => 0, "abstain" => 0, "absent" => 1)
    end
  end

  describe "#matter_by_file_number" do
    it "returns nil when file_number is blank" do
      expect(client.matter_by_file_number("")).to be_nil
      expect(client.matter_by_file_number(nil)).to be_nil
    end

    it "resolves index summary to full composite show payload" do
      stub_api(
        "matters",
        query: {"file_number" => "24-0001", "limit" => "1", "page" => "1"},
        body: fixture_content("matters_index_by_file_number.json")
      )

      stub_api(
        "matters/ordinance-24-0001-housing-affordability",
        body: fixture_content("matter_show_passed.json")
      )

      record = client.matter_by_file_number("24-0001")
      expect(record).to be_a(Hash)
      expect(record["slug"]).to eq("ordinance-24-0001-housing-affordability")
      expect(record["status"]["outcome"]).to eq("enacted")
      expect(record["actions"].size).to eq(1)
      expect(record["actions"].first["action_name"]).to eq("Passed")
    end

    it "returns nil when no matching matter exists" do
      stub_api(
        "matters",
        query: {"file_number" => "99-9999", "limit" => "1", "page" => "1"},
        body: fixture_content("matters_index_empty.json")
      )

      expect(client.matter_by_file_number("99-9999")).to be_nil
    end

    it "returns nil when composite show returns 404" do
      stub_api(
        "matters",
        query: {"file_number" => "24-0001", "limit" => "1", "page" => "1"},
        body: fixture_content("matters_index_by_file_number.json")
      )
      stub_api("matters/ordinance-24-0001-housing-affordability", status: 404, body: '{"error":"not_found"}')

      expect(client.matter_by_file_number("24-0001")).to be_nil
    end
  end

  describe "#matters" do
    it "queries collection with page, limit, and filters" do
      stub = stub_api(
        "matters",
        query: {"page" => "2", "limit" => "25", "body_slug" => "city-council"},
        body: fixture_content("matters_page_2.json")
      )

      envelope = client.matters(page: 2, limit: 25, body_slug: "city-council")
      expect(stub).to have_been_requested
      expect(envelope["data"]).to be_an(Array)
      expect(envelope["page"]["last"]).to eq(2)
      expect(envelope["jurisdiction"]["name"]).to eq("Baltimore City Council")
    end
  end

  describe "#all_matters" do
    it "iterates multi-page Pagy envelopes until last page is reached" do
      stub_api(
        "matters",
        query: {"page" => "1", "limit" => "2"},
        body: fixture_content("matters_page_1.json")
      )

      stub_api(
        "matters",
        query: {"page" => "2", "limit" => "2"},
        body: fixture_content("matters_page_2.json")
      )

      rows = client.all_matters(page_size: 2)
      expect(rows.pluck("id")).to eq([101, 102, 103])
    end

    it "terminates early when empty page is encountered" do
      stub_api(
        "matters",
        query: {"page" => "1", "limit" => "50"},
        body: fixture_content("matters_index_empty.json")
      )

      rows = client.all_matters
      expect(rows).to eq([])
    end

    it "bounds iteration by max_pages" do
      stub_api(
        "matters",
        query: {"page" => "1", "limit" => "50"},
        body: fixture_content("matters_page_1.json")
      )

      rows = client.all_matters(max_pages: 1)
      expect(rows.size).to eq(2)
    end
  end

  describe "#matter_actions" do
    it "returns actions array from resolved composite record" do
      stub_api(
        "matters",
        query: {"file_number" => "24-0001", "limit" => "1", "page" => "1"},
        body: fixture_content("matters_index_by_file_number.json")
      )
      stub_api(
        "matters/ordinance-24-0001-housing-affordability",
        body: fixture_content("matter_show_passed.json")
      )

      actions = client.matter_actions("24-0001")
      expect(actions.size).to eq(1)
      expect(actions.first["action_name"]).to eq("Passed")
      expect(actions.first["result"]).to eq("pass")
    end

    it "returns empty array when matter is not found or parameter is blank" do
      expect(client.matter_actions("")).to eq([])
      expect(client.matter_actions(nil)).to eq([])
    end
  end

  describe "#meetings" do
    it "queries meetings collection with page, limit, and filters" do
      stub = stub_api(
        "meetings",
        query: {"page" => "1", "limit" => "20", "body_slug" => "city-council"},
        body: fixture_content("meetings_page_1.json")
      )

      envelope = client.meetings(page: 1, limit: 20, body_slug: "city-council")
      expect(stub).to have_been_requested
      expect(envelope["data"]).to be_an(Array)
      expect(envelope["data"].first["slug"]).to eq("city-council-hearing-2026-05-15")
      expect(envelope["page"]["last"]).to eq(1)
    end
  end

  describe "#meeting" do
    it "raises ArgumentError when slug is blank" do
      expect { client.meeting("") }.to raise_error(ArgumentError, "slug is required")
      expect { client.meeting(nil) }.to raise_error(ArgumentError, "slug is required")
    end

    it "fetches composite meeting detail and unwraps data hash" do
      stub_api(
        "meetings/city-council-hearing-2026-05-15",
        body: fixture_content("meeting_detail.json")
      )

      result = client.meeting("city-council-hearing-2026-05-15")
      expect(result["slug"]).to eq("city-council-hearing-2026-05-15")
      expect(result["agenda_items"].first["votes"].first["value"]).to eq("yes")
    end
  end

  describe "fixture schema invariants (OL-34d.11.7)" do
    it "conforms strictly to Open Legislator page envelope, outcome enums, action results, and includes meetings fixtures" do
      verify_open_legislator_fixture_invariants!
    end
  end
end
