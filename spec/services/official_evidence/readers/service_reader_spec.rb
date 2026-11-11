# frozen_string_literal: true

require "rails_helper"

RSpec.describe Legislation::Adapters::GenericRosterAdapter do
  let(:profile) do
    {
      capability: "supported",
      publisher: "records.example.gov",
      jurisdiction: "example_executive",
      source_url: "https://records.example.gov/service",
      path: "/service",
      identity_source: "us_executive",
      office_identity: "us-president",
      fact_type: "executive_service",
      records_path: "records",
      fields: {
        id: "id",
        office_identity: "office_id",
        first_name: "first_name",
        last_name: "last_name",
        title: "title",
        chamber: "chamber",
        district: "district",
        start_date: "start_date",
        end_date: "end_date",
        presence: "presence"
      },
      date_semantics: {start: "inclusive", end: "exclusive"}
    }
  end

  let(:connection_for) do
    lambda do |body|
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/service") { [200, {"Content-Type" => "application/json"}, body] }
      end
      Faraday.new("https://records.example.gov") { |faraday| faraday.adapter :test, stubs }
    end
  end

  it "returns unsupported without making a request when no official-service profile is declared" do
    connection = double("connection")
    expect(connection).not_to receive(:get)
    adapter = described_class.new({roster_rules: {retrieval: "generic_rest"}}, connection:)

    result = adapter.fetch_official_service(sway_locale: build(:sway_locale))

    expect(result).to be_unsupported
    expect(result.facts).to be_empty
  end

  # @lat: [[lat.md/reference/official-service-evidence-tests#Official service evidence tests#Configured reader returns exact facts]]
  it "reads a configured official record into an evidence-backed exact service fact" do
    payload = Rails.root.join("spec", "fixtures", "official_evidence", "configured_service_record.json").read
    connection = connection_for.call(payload)
    adapter = described_class.new({roster_rules: {official_service: profile}}, connection:)

    result = adapter.fetch_official_service(sway_locale: build(:sway_locale))

    fact = result.facts.fetch(0)
    expect(result).to be_supported
    expect(fact.person_identity).to eq(LegislatorIdentity.new(source: "us_executive", value: "example-person-001"))
    expect(fact.office_identity).to eq("us-president")
    expect(fact.title).to eq("President of the Example Republic")
    expect(fact.chamber).to eq("Executive")
    expect(fact.district).to eq("US0")
    expect(fact.start_date).to eq(Date.new(2024, 1, 20))
    expect(fact.end_date).to eq(Date.new(2028, 1, 20))
    expect(fact.supported_service?).to be(true)
    expect(fact.evidence).to be_persisted
    expect(fact.evidence.publisher).to eq("records.example.gov")
    expect(fact.evidence.source_url).to eq("https://records.example.gov/service")
    expect(fact.evidence.parsed_values.fetch("facts")).to include(
      a_hash_including(
        "person_identity_source" => "us_executive",
        "person_identity_value" => "example-person-001",
        "office_identity" => "us-president",
        "title" => "President of the Example Republic",
        "start_date" => "2024-01-20",
        "end_date" => "2028-01-20"
      )
    )
  end

  it "rejects a non-ISO service date instead of coercing or accepting it" do
    payload = {records: [{
      id: "example-person-001",
      office_id: "us-president",
      first_name: "Alex",
      last_name: "Example",
      title: "President of the Example Republic",
      chamber: "Executive",
      district: "US0",
      start_date: "2024/01/20",
      end_date: "2028-01-20",
      presence: "present"
    }]}.to_json
    adapter = described_class.new({roster_rules: {official_service: profile}}, connection: connection_for.call(payload))

    result = adapter.fetch_official_service(sway_locale: build(:sway_locale))

    expect(result.facts).to be_empty
    expect(result.coverage_gaps).not_to be_empty
  end

  # @lat: [[lat.md/reference/official-service-evidence-tests#Official service evidence tests#Vacancy differs from a failed source read]]
  it "retains a published office vacancy separately from a failed source read" do
    payload = {records: [{office_id: "us-president", chamber: "Executive", district: "US0", presence: "vacant"}]}.to_json
    adapter = described_class.new({roster_rules: {official_service: profile}}, connection: connection_for.call(payload))

    result = adapter.fetch_official_service(sway_locale: build(:sway_locale))

    vacancy = result.facts.fetch(0)
    expect(result).to be_supported
    expect(vacancy.vacant?).to be(true)
    expect(vacancy.office_identity).to eq("us-president")
    expect(vacancy.chamber).to eq("Executive")
    expect(vacancy.district).to eq("US0")
    expect(vacancy.start_date).to be_nil
    expect(vacancy.end_date).to be_nil
    expect(vacancy.person_identity).to be_nil
    expect(vacancy.evidence).to be_persisted

    failed_stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/service") { [503, {}, "unavailable"] }
    end
    failed_connection = Faraday.new("https://records.example.gov") { |faraday| faraday.adapter :test, failed_stubs }
    failed = described_class.new({roster_rules: {official_service: profile}}, connection: failed_connection)
      .fetch_official_service(sway_locale: build(:sway_locale))

    expect(failed.facts).to be_empty
    expect(failed.coverage_gaps).to include(a_hash_including(reason: :source_request_failed))
  end
end
