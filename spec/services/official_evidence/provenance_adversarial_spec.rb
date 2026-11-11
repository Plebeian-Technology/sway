# frozen_string_literal: true

require "rails_helper"

RSpec.describe Legislation::Adapters::GenericRosterAdapter, "official service provenance" do
  let(:locale) { create(:sway_locale, :congress) }
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

  def provenance_record(id: "fixture-person-1", start_date: "2024-01-20", end_date: "2028-01-20")
    {
      id:,
      office_id: "us-president",
      first_name: "Fixture",
      last_name: "Officeholder",
      title: "Fixture Executive",
      chamber: "Executive",
      district: "US0",
      start_date:,
      end_date:,
      presence: "present"
    }
  end

  def reader_connection(payload, base_url: "https://records.example.gov")
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/service") { [200, {"Content-Type" => "application/json"}, payload] }
    end
    Faraday.new(base_url) { |faraday| faraday.adapter :test, stubs }
  end

  # @lat: [[official-service-adversarial-tests#Official service adversarial tests#Configured source controls retrieval]]
  it "retrieves from the declared official origin when injected transport has a different base URL" do
    payload = {records: [provenance_record]}.to_json
    connection = reader_connection(payload, base_url: "https://mirror.example")
    requested_urls = []
    allow(connection).to receive(:get).and_wrap_original do |original, *args, **kwargs|
      response = original.call(*args, **kwargs)
      requested_urls << response.env.url.to_s
      response
    end

    described_class.new({roster_rules: {official_service: profile}}, connection:)
      .fetch_official_service(sway_locale: locale)
    expect(requested_urls).to eq([profile[:source_url]])
  end

  # @lat: [[official-service-adversarial-tests#Official service adversarial tests#One response supports multiple retained records]]
  it "retains two disjoint officeholders from one response and reuses stable evidence on repeat" do
    payload = {records: [
      provenance_record(id: "fixture-predecessor", start_date: "2020-01-20", end_date: "2024-01-20"),
      provenance_record(id: "fixture-successor")
    ]}.to_json
    adapter = described_class.new({roster_rules: {official_service: profile}}, connection: reader_connection(payload))

    first = adapter.fetch_official_service(sway_locale: locale)
    first_ids = first.facts.map { |fact| fact.evidence.id }
    expect(first.facts.map(&:person_identity).map(&:value)).to contain_exactly("fixture-predecessor", "fixture-successor")
    expect(first.facts.map(&:supported_service?)).to all(be(true))
    expect(first.facts.map { |fact| fact.evidence.payload }).to all(eq(payload))
    expect { adapter.fetch_official_service(sway_locale: locale) }.not_to change(OfficialEvidence, :count)
    expect(adapter.fetch_official_service(sway_locale: locale).facts.map { |fact| fact.evidence.id }).to eq(first_ids)
  end

  # @lat: [[official-service-adversarial-tests#Official service adversarial tests#Fact values agree with retained evidence]]
  it "rejects a fact whose title was substituted after parsing" do
    payload = {records: [provenance_record]}.to_json
    adapter = described_class.new({roster_rules: {official_service: profile}}, connection: reader_connection(payload))
    fact = adapter.fetch_official_service(sway_locale: locale).facts.fetch(0).dup
    fact.instance_variable_set(:@title, "Substituted title")

    expect(fact.supported_service?).to be(false)
  end

  # @lat: [[official-service-adversarial-tests#Official service adversarial tests#Dirty evidence cannot authorize a fact]]
  it "rejects matching fact and evidence edits that have not been persisted" do
    payload = {records: [provenance_record]}.to_json
    adapter = described_class.new({roster_rules: {official_service: profile}}, connection: reader_connection(payload))
    fact = adapter.fetch_official_service(sway_locale: locale).facts.fetch(0).dup
    altered_values = fact.evidence.parsed_values.deep_dup
    altered_values.fetch("facts").fetch(0)["title"] = "Substituted title"
    fact.evidence.parsed_values = altered_values
    fact.instance_variable_set(:@title, "Substituted title")

    expect(fact.supported_service?).to be(false)
    expect(fact.evidence.reload.parsed_values.fetch("facts").fetch(0)["title"]).to eq("Fixture Executive")
  end

  # @lat: [[official-service-adversarial-tests#Official service adversarial tests#Persisted third-party provenance is unsupported]]
  it "does not treat persisted third-party evidence as official merely because its profile claims support" do
    payload = {records: [provenance_record]}.to_json
    adapter = described_class.new({roster_rules: {official_service: profile}}, connection: reader_connection(payload))
    fact = adapter.fetch_official_service(sway_locale: locale).facts.fetch(0).dup
    unofficial_profile = profile.merge(publisher: "openstates.org", source_url: "https://openstates.org/service")
    unofficial = OfficialEvidence.create!(**fact.evidence.attributes.except("id", "created_at", "updated_at").merge(
      "publisher" => unofficial_profile[:publisher],
      "source_url" => unofficial_profile[:source_url]
    ))
    fact.instance_variable_set(:@evidence, unofficial)
    fact.instance_variable_set(:@source_profile, unofficial_profile)

    expect(fact.supported_service?).to be(false)
  end

  # @lat: [[official-service-adversarial-tests#Official service adversarial tests#Unknown boundary meaning refuses service]]
  it "does not support service dates with an undeclared boundary meaning" do
    payload = {records: [provenance_record]}.to_json
    unknown_profile = profile.merge(date_semantics: {start: "inclusive", end: "unknown"})
    adapter = described_class.new({roster_rules: {official_service: unknown_profile}}, connection: reader_connection(payload))

    result = adapter.fetch_official_service(sway_locale: locale)

    expect(result.facts).to be_empty
    expect(result.unsupported? || result.coverage_gaps.any?).to be(true)
  end
  # @lat: [[official-service-adversarial-tests#Official service adversarial tests#Malformed configuration is explicitly unsupported]]
  it "returns unsupported for malformed profile shapes without retrieving a source" do
    connection = instance_double(Faraday::Connection)
    expect(connection).not_to receive(:get)
    [profile.merge(fields: "invalid"), profile.merge(date_semantics: "invalid")].each do |malformed|
      result = described_class.new({roster_rules: {official_service: malformed}}, connection:)
        .fetch_official_service(sway_locale: locale)
      expect(result).to be_unsupported
      expect(result.facts).to be_empty
    end
  end

  # @lat: [[official-service-adversarial-tests#Official service adversarial tests#Reading evidence does not create a locale]]
  it "retains evidence without persisting an unsaved civic locale" do
    unsaved_locale = locale.dup
    payload = {records: [provenance_record]}.to_json
    adapter = described_class.new({roster_rules: {official_service: profile}}, connection: reader_connection(payload))

    expect { adapter.fetch_official_service(sway_locale: unsaved_locale) }
      .not_to change(SwayLocale, :count)
    expect(unsaved_locale.new_record?).to be(true)
  end
end
