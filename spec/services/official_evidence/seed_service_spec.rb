# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "seed_legislator_terms")

RSpec.describe OfficialEvidence::SeedService do
  let(:locale) { create(:sway_locale, :congress) }
  let!(:district) { create(:district, sway_locale: locale, name: "US0") }
  let(:profile) do
    {
      capability: "supported",
      publisher: "records.example.gov",
      jurisdiction: "example_executive",
      source_url: "https://records.example.gov/service",
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

  let(:service_result_for) do
    lambda do |records|
      payload = {records: records}.to_json
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/service") { [200, {"Content-Type" => "application/json"}, payload] }
      end
      connection = Faraday.new("https://records.example.gov") { |faraday| faraday.adapter :test, stubs }
      Legislation::Adapters::GenericRosterAdapter.new(
        {roster_rules: {official_service: profile}}, connection:
      ).fetch_official_service(sway_locale: locale)
    end
  end

  let(:record_factory) do
    lambda do |id:, start_date: "2024-01-20", end_date: "2028-01-20", title: "President", office_id: "us-president"|
      {
        id:, office_id:, first_name: "Alex", last_name: "Example", title:,
        chamber: "Executive", district: "US0", start_date:, end_date:, presence: "present"
      }
    end
  end

  # @lat: [[lat.md/reference/official-service-evidence-tests#Official service evidence tests#Official service facts seed through the existing term writer#Fresh official service fact creates a person and term without votes]]
  it "creates a source-qualified person, identifier, seat, and exact term without votes" do
    result = service_result_for.call([record_factory.call(id: "fixture-person")])

    seeded = described_class.new(sway_locale: locale, result:).call

    legislator = Legislator.find_by!(sway_locale: locale, external_id: "us_executive:fixture-person")
    term = legislator.legislator_terms.sole
    expect(seeded.coverage_gaps).to be_empty
    expect(legislator.legislator_identifiers.pluck(:source, :value)).to eq([["us_executive", "fixture-person"]])
    expect(term.district).to eq(district)
    expect(term.seat&.seat_identifier).to eq("us-president")
    expect(term.title).to eq("President")
    expect(term.began_on).to eq(Date.new(2024, 1, 20))
    expect(term.ended_on).to eq(Date.new(2028, 1, 20))
    expect(legislator.legislator_votes).to be_empty
  end

  # @lat: [[lat.md/reference/official-service-evidence-tests#Official service evidence tests#Official service facts seed through the existing term writer#Conflicting facts for one seat are refused together]]
  it "refuses overlapping occupants of one office before making civic rows" do
    result = service_result_for.call([
      record_factory.call(id: "fixture-first", start_date: "2024-01-20", end_date: "2027-01-20"),
      record_factory.call(id: "fixture-second", start_date: "2026-01-20", end_date: "2028-01-20")
    ])

    seeded = described_class.new(sway_locale: locale, result:).call

    expect(seeded.coverage_gaps).to include(hash_including(reason: :ambiguous_office_service))
    expect(Legislator.where(sway_locale: locale)).to be_empty
    expect(Seat.find_by(district:)).to be_nil
    expect(LegislatorTerm.joins(:legislator).where(legislators: {sway_locale_id: locale.id})).to be_empty
  end

  # @lat: [[lat.md/reference/official-service-evidence-tests#Official service evidence tests#Official service facts seed through the existing term writer#Unrelated source identifiers do not collide]]
  it "uses a source-qualified external id when another source has the same raw value" do
    other_source = create(:legislator, sway_locale: locale, external_id: "fixture-person")
    LegislatorIdentifier.record!(
      legislator: other_source,
      identity: LegislatorIdentity.new(source: "open_states", value: "fixture-person")
    )
    result = service_result_for.call([record_factory.call(id: "fixture-person")])

    described_class.new(sway_locale: locale, result:).call

    expect(Legislator.where(sway_locale: locale)).to contain_exactly(other_source,
      have_attributes(external_id: "us_executive:fixture-person"))
  end
end
