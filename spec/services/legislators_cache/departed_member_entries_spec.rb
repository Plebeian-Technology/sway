# frozen_string_literal: true

require "rails_helper"

# @lat: [[current-legislator-term#Departed members are put back before term history is asked]]
RSpec.describe LegislatorsCache::DepartedMemberEntries do
  let(:congress) { create(:sway_locale, city: "congress", state: "congress", country: "United States") }

  # The default span always covers today, whatever day the suite runs —
  # fixed years would quietly stop meaning in office once the clock passed
  # them.
  def seat_member(
    external_id:,
    district_name:,
    start_year: Date.current.year - 1,
    end_year: Date.current.year + 1,
    **attrs
  )
    legislator = create(:legislator, sway_locale: congress, external_id: external_id, **attrs)
    create(
      :legislator_term,
      legislator: legislator,
      district: District.find_or_create_by!(name: district_name, sway_locale: congress),
      term_start_year: start_year,
      term_end_year: end_year
    )
    legislator
  end

  def built_entries(listed_bioguide_ids)
    described_class.for(sway_locale: congress, listed_bioguide_ids: listed_bioguide_ids)
  end

  it "returns an entry for somebody still in office whom the fetch did not name" do
    seat_member(external_id: "R000595", district_name: "FL0", first_name: "Marco", last_name: "Rubio", party: "R")

    result = built_entries(["A000001"])

    expect(result.pluck("bioguideId")).to eq(["R000595"])
    expect(result.first).to include(
      "name" => "Rubio, Marco",
      "firstName" => "Marco",
      "lastName" => "Rubio",
      "partyName" => "R",
      "state" => "Florida",
      "district" => "0",
      "currentMember" => false
    )
  end

  # The mark the seeder reads before writing a fallback current term.
  # Without it, adding these people back would hand each a fresh term
  # running to next year — the very row this work removes.
  it "never carries terms of its own" do
    seat_member(external_id: "W000823", district_name: "FL6")

    expect(built_entries([]).first).not_to have_key("terms")
  end

  it "leaves out anybody the fetch already named" do
    seat_member(external_id: "A000001", district_name: "MD1")

    expect(built_entries(["A000001"])).to be_empty
  end

  # Somebody whose last term has run out already reads as out of office, so
  # their row needs no correction. Leaving them out stops the roster growing
  # with every Congress.
  it "leaves out anybody whose terms have already run out" do
    seat_member(
      external_id: "X000001",
      district_name: "MD2",
      start_year: Date.current.year - 4,
      end_year: Date.current.year - 2
    )

    expect(built_entries([])).to be_empty
  end

  it "leaves out a person from another locale" do
    baltimore = create(:sway_locale, city: "baltimore", state: "maryland", country: "United States")
    other = create(:legislator, sway_locale: baltimore, external_id: "BALT001")
    create(
      :legislator_term,
      legislator: other,
      district: District.find_or_create_by!(name: "MD1", sway_locale: baltimore),
      term_start_year: 2024,
      term_end_year: 2028
    )

    expect(built_entries([])).to be_empty
  end

  # A seat name with no state letters gives the seed preparer nothing to
  # build a district from, and it raises rather than skipping the row,
  # which would stop the whole seed.
  it "leaves out a person whose seat names no state" do
    seat_member(external_id: "Y000001", district_name: "404")

    expect(built_entries([])).to be_empty
  end

  it "sorts by id so an unchanged roster is written the same way twice" do
    seat_member(external_id: "C000003", district_name: "TX1")
    seat_member(external_id: "A000002", district_name: "TX2")

    expect(built_entries([]).pluck("bioguideId")).to eq(["A000002", "C000003"])
  end
end
