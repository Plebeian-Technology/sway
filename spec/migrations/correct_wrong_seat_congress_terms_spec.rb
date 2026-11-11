# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20260807000001_correct_wrong_seat_congress_terms")

# The migration repoints four named term rows to the seat the
# published history proves. What these examples pin is not the four names —
# the production-snapshot spec does that — but the guards: only a term filed
# under the WRONG seat moves, and everything nearby stays put.
RSpec.describe "CorrectWrongSeatCongressTerms data migration", type: :model do
  let(:migration) { CorrectWrongSeatCongressTerms.new }

  let(:congress) do
    SwayLocale.find_or_create_by!(city: "congress", state: "congress", country: "united_states")
  end

  # @lat: [[production-term-seats-spec-design#What spec/migrations/correct_wrong_seat_congress_terms_spec.rb pins]]
  def run_seat_correction
    ActiveRecord::Migration.suppress_messages { migration.up }
  end

  def wrong_seat_district(name)
    District.find_or_create_by!(name:, sway_locale: congress)
  end

  def wrong_seat_member(bioguide)
    create(:legislator, external_id: bioguide, sway_locale: congress)
  end

  it "repoints a term filed under the wrong seat to the seat the history proves" do
    hinson = wrong_seat_member("H001091")
    term = hinson.legislator_terms.create!(term_start_year: 2021, term_end_year: 2023, district: wrong_seat_district("IA2"))

    run_seat_correction

    expect(term.reload.district.name).to eq("IA1")
  end

  it "leaves the same person's genuinely-held term in that seat alone" do
    curtis = wrong_seat_member("C001114")
    house = curtis.legislator_terms.create!(term_start_year: 2023, term_end_year: 2025, district: wrong_seat_district("UT0"))
    senate = curtis.legislator_terms.create!(term_start_year: 2025, term_end_year: 2031, district: wrong_seat_district("UT0"))

    run_seat_correction

    expect(house.reload.district.name).to eq("UT3")
    expect(senate.reload.district.name).to eq("UT0")
  end

  it "leaves a term somebody already filed correctly alone" do
    hinson = wrong_seat_member("H001091")
    term = hinson.legislator_terms.create!(term_start_year: 2021, term_end_year: 2023, district: wrong_seat_district("IA1"))

    run_seat_correction

    expect(term.reload.district.name).to eq("IA1")
  end

  it "keeps a locale score row's counts through the repoint" do
    schiff = wrong_seat_member("S001150")
    term = schiff.legislator_terms.create!(term_start_year: 2023, term_end_year: 2025, district: wrong_seat_district("CA0"))
    score = create(:legislator_locale_score, legislator_term: term, count_agreed: 3, count_disagreed: 0)

    run_seat_correction

    expect(term.reload.district.name).to eq("CA30")
    expect(score.reload.count_agreed).to eq(3)
    expect(score.count_disagreed).to eq(0)
  end

  it "does nothing on a database with no congress locale" do
    expect { run_seat_correction }.not_to change(District, :count)
  end

  it "does nothing for a person this database does not hold" do
    wrong_seat_district("NV0")

    expect { run_seat_correction }.not_to change(LegislatorTerm, :count)
  end

  it "changes nothing on a second run" do
    rosen = wrong_seat_member("R000608")
    term = rosen.legislator_terms.create!(term_start_year: 2017, term_end_year: 2019, district: wrong_seat_district("NV0"))

    run_seat_correction
    first_pass = term.reload.attributes

    run_seat_correction

    expect(term.reload.attributes).to eq(first_pass)
  end
end
