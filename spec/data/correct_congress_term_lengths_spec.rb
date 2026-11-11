# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20260731000002_correct_congress_term_lengths")

# Rebuilds the shape production is in and checks the migration puts
# it right: the phase 65 backfill gave the whole of Congress a two-year span
# and no title, senators included.
RSpec.describe "CorrectCongressTermLengths data migration", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:congress_locale) do
    create(:sway_locale, city: "congress", state: "congress", country: "United States")
  end
  let(:district) { create(:district, name: "OH0", sway_locale: congress_locale) }

  let(:roster_file) do
    file = Tempfile.new(["roster", ".json"])
    file.write(
      [
        {"bioguideId" => "SEN001", "terms" => {"item" => [{"startYear" => 2019, "chamber" => "Senate"}]}},
        {"bioguideId" => "REP001", "terms" => {"item" => [{"startYear" => 2019, "chamber" => "House of Representatives"}]}},
        {"bioguideId" => "MOVE001", "terms" => {"item" => [
          {"startYear" => 2019, "endYear" => 2024, "chamber" => "House of Representatives"},
          {"startYear" => 2024, "chamber" => "Senate"}
        ]}},
        {"bioguideId" => "POTUS", "terms" => {"item" => [{"startYear" => 2025, "chamber" => "White House"}]}}
      ].to_json
    )
    file.flush
    file
  end

  before { allow(CongressRoster).to receive(:new).and_return(CongressRoster.new(Pathname.new(roster_file.path.to_s))) }

  after { roster_file.close! }

  # A member carrying the defect: the two-year span and blank title the phase 65
  # backfill wrote for everybody.
  def member_with(external_id:, term_start_year: 2025, term_end_year: 2027, title: nil)
    legislator = create(:legislator, sway_locale: congress_locale, external_id: external_id)
    term = create(:legislator_term, legislator:, district:,
      term_start_year:, term_end_year:, title:)
    [legislator, term]
  end

  it "runs a senator's term the six years the Senate sets" do
    _legislator, term = member_with(external_id: "SEN001")

    CorrectCongressTermLengths.new.up

    expect(term.reload).to have_attributes(term_start_year: 2025, term_end_year: 2031, title: "Sen.")
  end

  it "leaves a representative's two-year term at two years" do
    _legislator, term = member_with(external_id: "REP001")

    CorrectCongressTermLengths.new.up

    expect(term.reload).to have_attributes(term_start_year: 2025, term_end_year: 2027, title: "Rep.")
  end

  it "keeps the senator in office once their real term is restored" do
    legislator, _term = member_with(external_id: "SEN001")

    travel_to Date.new(2027, 3, 1) do
      expect(legislator.reload.active_term).to be_nil # the defect, before

      CorrectCongressTermLengths.new.up

      expect(legislator.reload.active_term).to be_present
      expect(Legislator.serving).to include(legislator)
    end
  end

  # The roster holds only sitting members, so a term belonging to somebody who
  # has left cannot be classified. Guessing is how the original defect happened.
  it "leaves a departed member's term exactly as it is" do
    _legislator, term = member_with(external_id: "GONE001")

    expect { CorrectCongressTermLengths.new.up }
      .not_to(change { term.reload.attributes.slice("term_start_year", "term_end_year", "title") })
  end

  # Somebody who moved to the Senate mid-decade did not finish the House term
  # they were sitting in.
  it "stops a term at the year that stretch of service ended" do
    _legislator, term = member_with(external_id: "MOVE001", term_start_year: 2023, term_end_year: 2025)

    CorrectCongressTermLengths.new.up

    expect(term.reload).to have_attributes(term_end_year: 2024, title: "Rep.")
  end

  # The President is in the roster but is not a member of Congress. Reading his
  # chamber as if it were one made him a representative on a two-year term, and
  # that is what the production copy said until this stopped it. Whether he
  # should hold a term at all is a separate question this must not answer.
  it "leaves the President's term exactly as it is" do
    _legislator, term = member_with(external_id: "POTUS")

    expect { CorrectCongressTermLengths.new.up }
      .not_to(change { term.reload.attributes.slice("term_start_year", "term_end_year", "title") })
  end

  it "changes nothing on a second run" do
    _legislator, term = member_with(external_id: "SEN001")
    CorrectCongressTermLengths.new.up

    expect { CorrectCongressTermLengths.new.up }
      .not_to(change { term.reload.attributes.slice("term_start_year", "term_end_year", "title") })
  end

  it "leaves every other locale's terms alone" do
    baltimore = create(:sway_locale, city: "baltimore", state: "maryland", country: "United States")
    baltimore_district = create(:district, name: "MD1", sway_locale: baltimore)
    legislator = create(:legislator, sway_locale: baltimore, external_id: "SEN001")
    term = create(:legislator_term, legislator:, district: baltimore_district,
      term_start_year: 2024, term_end_year: 2028, title: "Council Member")

    expect { CorrectCongressTermLengths.new.up }
      .not_to(change { term.reload.attributes.slice("term_end_year", "title") })
  end
end
