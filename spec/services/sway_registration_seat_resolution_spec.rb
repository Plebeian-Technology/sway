# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "legislator")

RSpec.describe SwayRegistrationService, "seat resolution" do
  let(:user) { create(:user) }
  let(:congress) { create(:sway_locale, :congress) }
  let(:address) { create(:address, region_code: "MD") }
  let(:district) { create(:district, sway_locale: congress, name: "MD0") }
  let(:maryland_locale) { create(:sway_locale, :maryland) }

  def create_seat_term(district:, office_identity:, last_name:, years: [2025, 2027])
    seat = Seat.create!(
      district:,
      seat_identifier: office_identity,
      title: "United States Senator",
      chamber: "Senate"
    )
    legislator = create(:legislator, sway_locale: district.sway_locale, last_name:)
    term = create(
      :legislator_term,
      legislator:,
      district:,
      seat:,
      term_start_year: years[0],
      term_end_year: years[1]
    )
    [legislator, term, seat]
  end

  # @lat: [[representative-resolution-tests#Representative resolution tests#Registration seat resolution#Resolves state delegation of senators and house representative]]
  it "resolves state delegation of senators and house representative" do
    house_district = create(:district, sway_locale: congress, name: "MD3")
    house_rep, = create_seat_term(
      district: house_district,
      office_identity: "md-house-district-3",
      last_name: "Representative",
      years: [2025, 2027]
    )
    senator_a, = create_seat_term(
      district:,
      office_identity: "md-senate-class-1",
      last_name: "SenatorA",
      years: [2025, 2031]
    )
    senator_b, = create_seat_term(
      district:,
      office_identity: "md-senate-class-3",
      last_name: "SenatorB",
      years: [2023, 2029]
    )

    create(:user_address, user:, address:)
    allow(SwayGeocode).to receive(:build).and_return(double(districts: [0, 3]))

    service = described_class.new(user, address, congress, invited_by_id: nil, async: false)
    allow(service).to receive(:districts).and_return([0, 3])

    expect(service.district_legislators).to contain_exactly(house_rep, senator_a, senator_b)

    expect { ReconcileUserDistrictsService.new(user, congress).call }.not_to raise_error
    expect(user.user_legislators.where(active: true).pluck(:legislator_id))
      .to match_array([house_rep.id, senator_a.id, senator_b.id])
    expect(user.user_districts.where(active: true).pluck(:district_id))
      .to match_array([district.id, house_district.id])
  end

  # @lat: [[representative-resolution-tests#Registration seat resolution#Resolves Maryland statewide executives and district delegation]]
  it "resolves Maryland statewide executives and district delegation" do
    maryland = create(:sway_locale, :maryland)
    SeedLegislator.run([maryland])

    district_md46 = maryland.districts.find_by!(name: "MD46")
    district_md0 = maryland.districts.find_by!(name: "MD0")

    create(:user_address, user:, address:)
    allow(SwayGeocode).to receive(:build).and_return(double(districts: [0, 46]))

    md46_delegation = maryland.legislators.where(
      last_name: ["Ferguson", "Clippinger", "Edelson", "Lewis"]
    ).to_a
    allow_any_instance_of(described_class)
      .to receive(:find_legislators_from_open_states_geo_endpoint)
      .and_return(md46_delegation)

    service = described_class.new(user, address, maryland, invited_by_id: nil, async: false)
    allow(service).to receive(:districts).and_return([0, 46])

    reps = service.district_legislators
    expect(reps.count).to eq(5)
    expect(reps.map(&:last_name)).to include("Moore")
    expect(reps.map { |r| [r.first_name, r.last_name] }).not_to include(["Aruna", "Miller"], ["Anthony", "Brown"])
    expect(reps.map(&:last_name)).to include("Ferguson", "Clippinger", "Edelson", "Lewis")

    expect { ReconcileUserDistrictsService.new(user, maryland).call }.not_to raise_error
    expect(user.user_legislators.where(active: true).pluck(:legislator_id))
      .to match_array(reps.map(&:id))
    expect(user.user_districts.where(active: true).pluck(:district_id))
      .to match_array([district_md0.id, district_md46.id])
  end

  def create_unseated_md0_term(maryland, title:, last_name:)
    md0 = maryland.districts.find_by(name: "MD0") || create(:district, sway_locale: maryland, name: "MD0")
    legislator = create(:legislator, sway_locale: maryland, last_name:)
    create(:legislator_term, legislator:, district: md0, title:, term_start_year: 2023, term_end_year: 2027)
    legislator
  end

  def maryland_service(maryland, geo_candidates: [])
    create(:user_address, user:, address:)
    allow(SwayGeocode).to receive(:build).and_return(double(districts: [0]))
    allow_any_instance_of(described_class)
      .to receive(:find_legislators_from_open_states_geo_endpoint)
      .and_return(geo_candidates)
    described_class.new(user, address, maryland, invited_by_id: nil, async: false)
  end

  # @lat: [[representative-resolution-tests#Registration seat resolution#Skips unconfigured locale-wide offices]]
  it "skips the unconfigured locale-wide office and resolves the rest" do
    SeedLegislator.run([maryland_locale])
    attorney_general = create_unseated_md0_term(maryland_locale, title: "Attorney General", last_name: "HoldoverAg")
    service = maryland_service(maryland_locale)

    expect { service.district_legislators }.not_to raise_error
    reps = service.district_legislators
    expect(reps.map(&:last_name)).to include("Moore")
    expect(reps).not_to include(attorney_general)
    expect { ReconcileUserDistrictsService.new(user, maryland_locale).call }.not_to raise_error
  end

  # @lat: [[representative-resolution-tests#Registration seat resolution#Skips unconfigured geographic offices]]
  it "skips an unconfigured office holder returned by the regional source" do
    lt_governor = create_unseated_md0_term(maryland_locale, title: "Lt_Governor", last_name: "HoldoverLtGov")
    service = maryland_service(maryland_locale, geo_candidates: [lt_governor])

    expect { service.district_legislators }.not_to raise_error
    expect(service.district_legislators).to be_empty
  end

  # @lat: [[representative-resolution-tests#Registration seat resolution#Refuses untitled unseated terms]]
  it "still refuses an unseated locale-wide term with no title" do
    create_unseated_md0_term(maryland_locale, title: nil, last_name: "Untitled")

    expect { maryland_service(maryland_locale).district_legislators }
      .to raise_error(Seats::UnresolvedSeatError, /no persisted seat identity/)
  end

  # @lat: [[representative-resolution-tests#Registration seat resolution#Retains co-serving distinct seats]]
  it "keeps co-serving officials in distinct seats of the same geographic district" do
    senator_a, = create_seat_term(
      district:,
      office_identity: "md-senate-class-1",
      last_name: "A",
      years: [2021, 2027]
    )
    senator_b, = create_seat_term(
      district:,
      office_identity: "md-senate-class-3",
      last_name: "B",
      years: [2023, 2029]
    )
    service = described_class.new(user, address, congress, invited_by_id: nil, async: false)
    allow(service).to receive(:districts).and_return([0])

    expect(service.district_legislators).to contain_exactly(senator_a, senator_b)
  end

  # @lat: [[representative-resolution-tests#Registration seat resolution#Returns all supported delegates in one district]]
  it "returns every supported delegate seat in a shared Maryland district" do
    state_locale = create(:sway_locale, city: "maryland", state: "MD", country: "united_states")
    shared_district = create(:district, sway_locale: state_locale, name: "MD43")
    delegate_a, = create_seat_term(
      district: shared_district,
      office_identity: "md-house-43a",
      last_name: "DelegateA"
    )
    delegate_b, = create_seat_term(
      district: shared_district,
      office_identity: "md-house-43b",
      last_name: "DelegateB"
    )
    service = described_class.new(user, address, state_locale, invited_by_id: nil, async: false)
    allow(service).to receive(:find_legislators_from_open_states_geo_endpoint)
      .and_return([delegate_a, delegate_b])

    expect(service.district_legislators).to contain_exactly(delegate_a, delegate_b)
  end

  # @lat: [[representative-resolution-tests#Registration seat resolution#Refuses missing seat identity]]
  it "refuses a current geographic candidate without a persisted seat identity" do
    legislator = create(:legislator, sway_locale: congress)
    create(:legislator_term, legislator:, district:)
    service = described_class.new(user, address, congress, invited_by_id: nil, async: false)
    allow(service).to receive(:districts).and_return([0])

    expect { service.district_legislators }
      .to raise_error(Seats::UnresolvedSeatError, /seat/i)
  end

  # @lat: [[representative-resolution-tests#Registration seat resolution#Selects the exact Congress locale-wide district]]
  it "attaches the configured locale-wide Congress seat independently of geocoded district" do
    us_district = create(:district, sway_locale: congress, name: "US0")
    president, = create_seat_term(
      district: us_district,
      office_identity: "us-president",
      last_name: "President"
    )
    state_senate_district = create(:district, sway_locale: congress, name: "MD0")
    state_senator, = create_seat_term(
      district: state_senate_district,
      office_identity: "md-senate-class-3",
      last_name: "StateSenator"
    )
    geo_district = create(:district, sway_locale: congress, name: "MD7")
    district_senator, = create_seat_term(
      district: geo_district,
      office_identity: "md-congress-district-7",
      last_name: "Senator"
    )
    service = described_class.new(user, address, congress, invited_by_id: nil, async: false)
    allow(service).to receive(:districts).and_return([7])

    expect(service.district_legislators).to contain_exactly(president, district_senator)
    expect(president).not_to eq(state_senator)
  end

  # @lat: [[representative-resolution-tests#Registration seat resolution#Includes locale-wide occupants through geography]]
  it "includes the configured locale-wide occupant and the geographic district-zero occupant" do
    us_district = create(:district, sway_locale: congress, name: "US0")
    president, = create_seat_term(
      district: us_district,
      office_identity: "us-president",
      last_name: "President"
    )
    md_zero = create(:district, sway_locale: congress, name: "MD0")
    district_zero_rep, = create_seat_term(
      district: md_zero,
      office_identity: "md-congress-district-zero",
      last_name: "DistrictZero"
    )
    service = described_class.new(user, address, congress, invited_by_id: nil, async: false)
    allow(service).to receive(:districts).and_return([0])

    expect(service.district_legislators).to contain_exactly(president, district_zero_rep)
  end

  # @lat: [[representative-resolution-tests#Registration seat resolution#Adds Maryland locale-wide seats to regional results]]
  it "includes the Maryland locale-wide seat when OpenStates returns no geographic candidate" do
    state_locale = create(:sway_locale, city: "maryland", state: "MD", country: "united_states")
    state_wide = create(:district, sway_locale: state_locale, name: "MD0")
    governor, = create_seat_term(
      district: state_wide,
      office_identity: "maryland-governor",
      last_name: "Governor"
    )
    service = described_class.new(user, address, state_locale, invited_by_id: nil, async: false)
    allow(service).to receive(:find_legislators_from_open_states_geo_endpoint).and_return([])

    expect(service.district_legislators).to contain_exactly(governor)
  end

  # @lat: [[representative-resolution-tests#Registration seat resolution#Uses exact locale-wide names]]
  it "keeps an exact locale-wide district separate from other district-zero names" do
    us_district = create(:district, sway_locale: congress, name: "US0")
    president, = create_seat_term(
      district: us_district,
      office_identity: "us-president",
      last_name: "President"
    )
    ohio_district = create(:district, sway_locale: congress, name: "OH0")
    ohio_official, = create_seat_term(
      district: ohio_district,
      office_identity: "ohio-at-large",
      last_name: "Ohio"
    )
    maryland_zero_district = create(:district, sway_locale: congress, name: "MD0")
    maryland_zero_official, = create_seat_term(
      district: maryland_zero_district,
      office_identity: "maryland-geographic-zero",
      last_name: "MarylandZero"
    )
    service = described_class.new(user, address, congress, invited_by_id: nil, async: false)
    allow(service).to receive(:districts).and_return([0])

    expect(service.district_legislators).to contain_exactly(president, maryland_zero_official)
    expect(service.district_legislators).not_to include(ohio_official)
  end

  # @lat: [[representative-resolution-tests#Registration seat resolution#Checks omitted current occupants]]
  it "checks all current rows for a selected seat even when the geo candidate list omits one" do
    state_locale = create(:sway_locale, city: "maryland", state: "MD", country: "united_states")
    state_district = create(:district, sway_locale: state_locale, name: "MD1")
    selected, _term, seat = create_seat_term(
      district: state_district,
      office_identity: "md-senate-class-1",
      last_name: "Selected"
    )
    duplicate = create(:legislator, sway_locale: state_locale, last_name: "Duplicate")
    now = Time.current
    LegislatorTerm.insert_all!([
      {
        legislator_id: duplicate.id,
        district_id: district.id,
        seat_id: seat.id,
        term_start_year: 2025,
        term_end_year: 2027,
        created_at: now,
        updated_at: now
      }
    ])
    service = described_class.new(user, address, state_locale, invited_by_id: nil, async: false)
    allow(service).to receive(:find_legislators_from_open_states_geo_endpoint).and_return([selected])

    expect { service.district_legislators }
      .to raise_error(Seats::OverlapValidator::OverlapError, /multiple current occupants/)
    expect(selected).to be_present
  end

  # @lat: [[representative-resolution-tests#Registration seat resolution#Rejects duplicate rows for one person]]
  it "rejects overlapping current rows for one person and one seat" do
    selected, _term, seat = create_seat_term(
      district:,
      office_identity: "md-senate-class-1",
      last_name: "DoubleTerm"
    )
    now = Time.current
    LegislatorTerm.insert_all!([
      {
        legislator_id: selected.id,
        district_id: district.id,
        seat_id: seat.id,
        term_start_year: 2023,
        term_end_year: 2029,
        created_at: now,
        updated_at: now
      }
    ])
    service = described_class.new(user, address, congress, invited_by_id: nil, async: false)
    allow(service).to receive(:districts).and_return([0])

    expect { service.district_legislators }
      .to raise_error(Seats::OverlapValidator::OverlapError, /multiple current occupants/)
  end

  # @lat: [[representative-resolution-tests#Registration seat resolution#Leaves expired seats vacant]]
  it "does not resolve an expired seat during the exact vacancy boundary" do
    vacancy = Date.current
    seat = Seat.create!(
      district:,
      seat_identifier: "md-senate-class-1",
      title: "United States Senator",
      chamber: "Senate"
    )
    predecessor = create(:legislator, sway_locale: congress)
    create(
      :legislator_term,
      legislator: predecessor,
      district:,
      seat:,
      term_start_year: 2023,
      term_end_year: 2029,
      ended_on: vacancy,
      ended_on_source: LegislatorTerm::DateSource::PUBLISHED
    )
    service = described_class.new(user, address, congress, invited_by_id: nil, async: false)
    allow(service).to receive(:districts).and_return([0])

    expect(service.district_legislators).to be_empty
  end

  # @lat: [[representative-resolution-tests#Reconciliation refusal#Preserves links on unresolved reconciliation]]
  it "leaves existing links active when seat resolution refuses a legacy term" do
    legislator = create(:legislator, sway_locale: congress)
    create(:legislator_term, legislator:, district: create(:district, sway_locale: congress, name: "MD7"))
    create(:user_address, user:, address:)
    stored_legislator = create(:user_legislator, user:, legislator:)
    stored_district = create(:user_district, user:, district: legislator.active_term.district)
    allow(SwayGeocode).to receive(:build).and_return(double(districts: [7]))

    expect {
      ReconcileUserDistrictsService.new(user, congress).call
    }.to raise_error(Seats::UnresolvedSeatError)

    expect(stored_legislator.reload.active).to be(true)
    expect(stored_district.reload.active).to be(true)
  end

  # @lat: [[representative-resolution-tests#Reconciliation refusal#Preserves links on locale-wide conflict]]
  it "leaves links active when locale-wide occupancy is ambiguous" do
    locale_wide = create(:district, sway_locale: congress, name: "US0")
    seat = Seat.create!(
      district: locale_wide,
      seat_identifier: "us-president",
      title: "President",
      chamber: "Executive"
    )
    president = create(:legislator, sway_locale: congress, last_name: "President")
    create(:legislator_term, legislator: president, district: locale_wide, seat:)
    now = Time.current
    LegislatorTerm.insert_all!([
      {
        legislator_id: create(:legislator, sway_locale: congress, last_name: "Duplicate").id,
        district_id: locale_wide.id,
        seat_id: seat.id,
        term_start_year: 2025,
        term_end_year: 2027,
        created_at: now,
        updated_at: now
      }
    ])
    create(:user_address, user:, address:)
    stored_legislator = create(:user_legislator, user:, legislator: president)
    stored_district = create(:user_district, user:, district: locale_wide)
    allow(SwayGeocode).to receive(:build).and_return(double(districts: [7]))

    expect {
      ReconcileUserDistrictsService.new(user, congress).call
    }.to raise_error(Seats::OverlapValidator::OverlapError)

    expect(stored_legislator.reload.active).to be(true)
    expect(stored_district.reload.active).to be(true)
  end
end
