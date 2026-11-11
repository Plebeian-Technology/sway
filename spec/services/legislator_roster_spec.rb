# frozen_string_literal: true

require "rails_helper"

RSpec.describe LegislatorRoster do
  let(:congress) do
    SwayLocale.find_by(city: "congress", state: "congress", country: "united_states") ||
      create(:sway_locale, city: "congress", state: "congress", country: "united_states")
  end

  # Congress names a seat for its state: "MD0" is the statewide Senate seat,
  # "MD7" a House district.
  let(:senate_seat) { create(:district, sway_locale: congress, name: "MD0") }
  let(:house_seat) { create(:district, sway_locale: congress, name: "MD7") }

  def roster_member(last_name:, external_id:, seat:, title:, from:, to:)
    create(
      :legislator,
      district: seat,
      external_id: external_id,
      first_name: "Formal",
      last_name: last_name,
      party: "D"
    ).tap do |person|
      create(
        :legislator_term,
        legislator: person,
        district: seat,
        title: title,
        term_start_year: from,
        term_end_year: to
      )
    end
  end

  # @lat: [[congress-roll-calls#The roster a roll call is matched against is the vote day's]]
  describe "who is in it" do
    it "holds a person whose term is running that day" do
      roster_member(last_name: "Serving", external_id: "S000001", seat: senate_seat,
        title: "Sen.", from: 2023, to: 2025)

      roster = described_class.new(sway_locale: congress, on: Date.new(2024, 6, 18))

      expect(roster.with_external_id("S000001")).to be_present
    end

    it "leaves out a person whose term had already ended" do
      roster_member(last_name: "Departed", external_id: "D000001", seat: senate_seat,
        title: "Sen.", from: 2019, to: 2023)

      roster = described_class.new(sway_locale: congress, on: Date.new(2024, 6, 18))

      expect(roster.with_external_id("D000001")).to be_nil
    end

    it "leaves out a person whose term had not yet begun" do
      roster_member(last_name: "Elect", external_id: "E000001", seat: senate_seat,
        title: "Sen.", from: 2025, to: 2027)

      roster = described_class.new(sway_locale: congress, on: Date.new(2024, 6, 18))

      expect(roster.with_external_id("E000001")).to be_nil
    end

    it "answers with the term running that day when a person has several" do
      person = roster_member(last_name: "Long", external_id: "L000001", seat: senate_seat,
        title: "Sen.", from: 2019, to: 2025)
      create(:legislator_term, legislator: person, district: senate_seat,
        title: "Sen.", term_start_year: 2025, term_end_year: 2031)

      roster = described_class.new(sway_locale: congress, on: Date.new(2024, 6, 18))

      expect(roster.with_external_id("L000001")&.term_start_year).to eq(2019)
    end
  end

  # Sway stores the formal given name and the Senate prints the everyday one —
  # "Margaret Wood" against "Maggie" — so about 28 of every 99 senators went
  # unmatched. Surname and state match 99 of 99.
  describe "#senator_named" do
    it "finds a senator by surname and state, whatever the given name" do
      roster_member(last_name: "Hassan", external_id: "H000001", seat: senate_seat,
        title: "Sen.", from: 2023, to: 2029)

      roster = described_class.new(sway_locale: congress, on: Date.new(2024, 6, 18))

      expect(roster.senator_named("Hassan", "MD")&.legislator&.external_id).to eq("H000001")
    end

    it "ignores case and stray spacing in what the record prints" do
      roster_member(last_name: "Hassan", external_id: "H000001", seat: senate_seat,
        title: "Sen.", from: 2023, to: 2029)

      roster = described_class.new(sway_locale: congress, on: Date.new(2024, 6, 18))

      expect(roster.senator_named(" hassan ", "md")&.legislator&.external_id).to eq("H000001")
    end

    it "does not answer with a senator from another state" do
      roster_member(last_name: "Hassan", external_id: "H000001", seat: senate_seat,
        title: "Sen.", from: 2023, to: 2029)

      roster = described_class.new(sway_locale: congress, on: Date.new(2024, 6, 18))

      expect(roster.senator_named("Hassan", "CA")).to be_nil
    end

    # Eight of the senators voting on one 2024 roll call have terms with no
    # title. Refusing them would drop their votes a second time.
    it "takes the only person of that surname even when the term states no title" do
      roster_member(last_name: "Untitled", external_id: "U000001", seat: senate_seat,
        title: nil, from: 2019, to: 2025)

      roster = described_class.new(sway_locale: congress, on: Date.new(2024, 6, 18))

      expect(roster.senator_named("Untitled", "MD")&.legislator&.external_id).to eq("U000001")
    end

    it "never answers with a House seat" do
      roster_member(last_name: "Mfume", external_id: "M000687", seat: house_seat,
        title: "Rep.", from: 2023, to: 2025)

      roster = described_class.new(sway_locale: congress, on: Date.new(2024, 6, 18))

      expect(roster.senator_named("Mfume", "MD")).to be_nil
    end

    # A senator and a representative of one surname: the title is the only
    # thing that tells them apart, so it decides.
    it "separates a senator from a representative of the same surname" do
      roster_member(last_name: "Shared", external_id: "S000002", seat: senate_seat,
        title: "Sen.", from: 2021, to: 2027)
      roster_member(last_name: "Shared", external_id: "S000003", seat: house_seat,
        title: "Rep.", from: 2023, to: 2025)

      roster = described_class.new(sway_locale: congress, on: Date.new(2024, 6, 18))

      expect(roster.senator_named("Shared", "MD")&.legislator&.external_id).to eq("S000002")
    end

    # Arizona's 7th changed hands mid-term, father to daughter. Whole-year
    # terms make predecessor and successor overlap — 2025-2026 against
    # 2025-2027 — and both are representatives, so neither may be taken.
    it "answers with nobody when two representatives share a surname and state" do
      roster_member(last_name: "Grijalva", external_id: "G000551", seat: house_seat,
        title: "Rep.", from: 2025, to: 2026)
      roster_member(last_name: "Grijalva", external_id: "G000606", seat: house_seat,
        title: "Rep.", from: 2025, to: 2027)

      roster = described_class.new(sway_locale: congress, on: Date.new(2025, 6, 18))

      expect(roster.senator_named("Grijalva", "MD")).to be_nil
    end

    # @lat: [[congress-roll-calls#Nobody is the honest answer when two people cannot be told apart]]
    it "answers with nobody when two senators share a surname and state" do
      roster_member(last_name: "Graham", external_id: "G000359", seat: senate_seat,
        title: "Sen.", from: 2021, to: 2027)
      roster_member(last_name: "Graham", external_id: "G000608", seat: senate_seat,
        title: "Sen.", from: 2026, to: 2027)

      roster = described_class.new(sway_locale: congress, on: Date.new(2026, 6, 18))

      expect(roster.senator_named("Graham", "MD")).to be_nil
    end

    it "answers with nobody when two untitled people share a surname and state" do
      roster_member(last_name: "Untold", external_id: "U000001", seat: senate_seat,
        title: nil, from: 2021, to: 2027)
      roster_member(last_name: "Untold", external_id: "U000002", seat: house_seat,
        title: nil, from: 2023, to: 2025)

      roster = described_class.new(sway_locale: congress, on: Date.new(2024, 6, 18))

      expect(roster.senator_named("Untold", "MD")).to be_nil
    end

    it "answers with nobody when the record prints no surname" do
      expect(described_class.new(sway_locale: congress, on: Date.current).senator_named(nil, "MD"))
        .to be_nil
    end
  end
end
