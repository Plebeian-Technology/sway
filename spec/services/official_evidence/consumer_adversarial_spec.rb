# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "seed_legislator_terms")

RSpec.describe OfficialEvidence::SeedService, "adversarial consumer contracts" do
  let(:locale) { create(:sway_locale, :congress) }
  let(:district) { create(:district, sway_locale: locale, name: "US0") }

  def read_result(records)
    profile = {
      capability: "supported", publisher: "records.example.gov", jurisdiction: "fixture_executive",
      source_url: "https://records.example.gov/service", identity_source: "us_executive",
      office_identity: "us-president", fact_type: "executive_service", records_path: "records",
      date_semantics: {start: "inclusive", end: "exclusive"},
      fields: %i[id office_identity first_name last_name party title chamber district start_date end_date presence]
        .to_h { |key| [key, key.to_s] }
    }
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/service") { [200, {"Content-Type" => "application/json"}, {records:}.to_json] }
    end
    connection = Faraday.new { |faraday| faraday.adapter :test, stubs }
    Legislation::Adapters::GenericRosterAdapter.new({roster_rules: {official_service: profile}}, connection:)
      .fetch_official_service(sway_locale: locale)
  end

  def consumer_record(id: "fixture-person", title: "Fixture President", start_date: "2024-01-20", end_date: "2028-01-20")
    {id:, office_identity: "us-president", first_name: "Fixture", last_name: "President",
     party: "Independent", title:, chamber: "Executive", district: "US0",
     start_date:, end_date:, presence: "present"}
  end

  def seed_result(result)
    district
    described_class.new(sway_locale: locale, result:).call
  end

  # @lat: [[official-service-consumer-adversarial-tests#Official service consumer adversarial tests#Exact executive boundaries remain exact]]
  it "persists January 20 boundaries without substituting the congressional calendar" do
    result = read_result([consumer_record])
    seed_result(result)
    term = LegislatorTerm.sole

    expect(term.began_on).to eq(Date.new(2024, 1, 20))
    expect(term.ended_on).to eq(Date.new(2028, 1, 20))
    expect(term.seat&.seat_identifier).to eq("us-president")
    expect(TermWindow.running_on(Date.new(2024, 1, 19), [term])).to be_nil
    expect(TermWindow.running_on(Date.new(2024, 1, 20), [term])).to eq(term)
    expect(TermWindow.running_on(Date.new(2028, 1, 20), [term])).to be_nil
    expect(LegislatorVote.count).to eq(0)
    expect(UserLegislatorTermScore.count).to eq(0)
  end

  # @lat: [[official-service-consumer-adversarial-tests#Official service consumer adversarial tests#Person identity keeps its publisher scheme]]
  it "creates a distinct official person when an unrelated identity shares the raw value" do
    unrelated = create(:legislator, sway_locale: locale, external_id: "fixture-person")
    LegislatorIdentifier.record!(legislator: unrelated, identity: LegislatorIdentity.new(source: "curated_person", value: "fixture-person"))
    result = read_result([consumer_record])

    seed_result(result)
    official = LegislatorIdentifier.legislator_for(sway_locale: locale, identity: result.facts.fetch(0).person_identity || raise("fixture lacks an evidenced person"))
    expect(official).to be_present
    expect(official.id).not_to eq(unrelated.id)
    expect(unrelated.reload.legislator_terms).to be_empty
    expect(official&.legislator_terms&.sole&.seat&.seat_identifier).to eq("us-president")
  end

  # @lat: [[official-service-consumer-adversarial-tests#Official service consumer adversarial tests#Conflicting seeding leaves no orphan person]]
  it "rolls back the new person and identifier when the seat is already occupied" do
    seed_result(read_result([consumer_record(id: "fixture-incumbent")]))
    counts = [Legislator.count, LegislatorIdentifier.count, LegislatorTerm.count, Seat.count]
    conflict = seed_result(read_result([consumer_record(id: "fixture-conflict")]))

    expect([Legislator.count, LegislatorIdentifier.count, LegislatorTerm.count, Seat.count]).to eq(counts)
    expect(conflict.coverage_gaps).not_to be_empty
  end

  # @lat: [[official-service-consumer-adversarial-tests#Official service consumer adversarial tests#Unsupported prepared facts cannot enter a legacy writer]]
  it "refuses a prepared official fact whose evidence was altered before term creation" do
    result = read_result([consumer_record])
    fact = result.facts.fetch(0)
    district
    person = create(:legislator, sway_locale: locale)
    LegislatorIdentifier.record!(legislator: person, identity: fact.person_identity || raise("fixture lacks an evidenced person"))
    prepared = OfficialEvidence::PreparedServiceEntry.new(official_fact: fact, official_service_result: result, district:)
    fact.instance_variable_set(:@title, "Substituted title")

    expect { SeedLegislatorTerms.new(person, prepared).call }.not_to change(LegislatorTerm, :count)
    expect(Seat.count).to eq(0)
  end

  # @lat: [[official-service-consumer-adversarial-tests#Official service consumer adversarial tests#Ambiguous title facts cannot authorize a write]]
  it "leaves a blank title untouched when the response disagrees about that exact term" do
    seed_result(read_result([consumer_record]))
    term = LegislatorTerm.sole
    term.update_columns(title: nil)
    before = term.reload.attributes
    ambiguous = read_result([consumer_record, consumer_record(title: "Conflicting fixture title")])
    prepared = OfficialEvidence::PreparedServiceEntry.new(official_fact: ambiguous.facts.first, official_service_result: ambiguous, district:)

    expect(SeedLegislatorTerms.fill_missing_title!(term, prepared:)).to be(false)
    expect(term.reload.attributes).to eq(before)
  end
  # @lat: [[official-service-consumer-adversarial-tests#Official service consumer adversarial tests#Ambiguous source occupancy leaves civic tables empty]]
  it "does not pick the first of two overlapping officeholders in one source response" do
    result = read_result([consumer_record(id: "fixture-a"), consumer_record(id: "fixture-b")])
    outcome = seed_result(result)

    expect(Legislator.count).to eq(0)
    expect(LegislatorIdentifier.count).to eq(0)
    expect(LegislatorTerm.count).to eq(0)
    expect(Seat.count).to eq(0)
    expect(outcome.coverage_gaps).not_to be_empty
  end
end
