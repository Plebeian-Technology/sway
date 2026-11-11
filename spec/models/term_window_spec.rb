# frozen_string_literal: true

require "rails_helper"

# @lat: [[term-window-design#Why term_window_spec.rb tests against Struct stand-ins, not real LegislatorTerm records]]
TermWindowCandidate = Struct.new(:term_start_year, :sway_locale, :began_on)

# @lat: [[term-window-design#Why term_window_spec.rb tests against Struct stand-ins, not real LegislatorTerm records]]
BoundedTermWindowCandidate = Struct.new(:term_start_year, :term_end_year, :sway_locale, :ended_on, :began_on)

RSpec.describe TermWindow do
  let(:congress_locale) do
    create(:sway_locale, city: "congress", state: "congress", country: "United States")
  end
  let(:maryland_regional_locale) do
    create(:sway_locale, city: "maryland", state: "maryland", country: "United States")
  end
  let(:baltimore_local_locale) do
    create(:sway_locale, city: "baltimore", state: "maryland", country: "United States")
  end

  describe ".convening_date" do
    it "returns the fixed Jan 3 constant for Congress (20th Amdt §1)" do
      expect(described_class.convening_date(congress_locale, 2025)).to eq(Date.new(2025, 1, 3))
      expect(described_class.convening_date(congress_locale, 2023)).to eq(Date.new(2023, 1, 3))
    end

    it "computes the second Wednesday of January for Maryland 2023 (Md. Const. Art. III §14)" do
      expect(described_class.convening_date(maryland_regional_locale, 2023)).to eq(Date.new(2023, 1, 11))
    end

    it "proves the Maryland date is COMPUTED, not a fixed Jan-11 constant (2025 -> Jan 8)" do
      expect(described_class.convening_date(maryland_regional_locale, 2025)).to eq(Date.new(2025, 1, 8))
    end

    # @lat: [[current-legislator-term#Declared calendars]]
    it "computes the Thursday after the first Monday of December for Baltimore 2024 (Charter Art. III § 2(a)(2))" do
      expect(described_class.convening_date(baltimore_local_locale, 2024)).to eq(Date.new(2024, 12, 5))
    end

    it "proves the Baltimore date is COMPUTED, not a fixed Dec-5 constant (2028 -> Dec 7)" do
      expect(described_class.convening_date(baltimore_local_locale, 2028)).to eq(Date.new(2028, 12, 7))
    end

    # @lat: [[term-window-design#Why term_window_spec.rb tests against Struct stand-ins, not real LegislatorTerm records]]
    it "refuses a locale with no declared rule instead of using another locale's" do
      undeclared = create(:sway_locale, city: "austin", state: "TX", country: "United States")

      expect { described_class.convening_date(undeclared, 2024) }
        .to raise_error(SwayLocale::TermRules::Undeclared, /austin/)
    end
  end

  describe ".covering" do
    let(:term_2023_congress) { TermWindowCandidate.new(2023, congress_locale) }
    let(:term_2025_congress) { TermWindowCandidate.new(2025, congress_locale) }
    let(:balt_term_2020) { TermWindowCandidate.new(2020, baltimore_local_locale) }
    let(:balt_term_2024) { TermWindowCandidate.new(2024, baltimore_local_locale) }

    it "returns the 118th Congress term for a 2024 vote" do
      result = described_class.covering(Date.new(2024, 6, 1), [term_2023_congress, term_2025_congress])
      expect(result).to eq(term_2023_congress)
    end

    it "returns the 119th Congress term for a 2025 vote" do
      result = described_class.covering(Date.new(2025, 3, 1), [term_2023_congress, term_2025_congress])
      expect(result).to eq(term_2025_congress)
    end

    it "buckets a Nov 2024 Baltimore vote to the 2020 term (before the Dec 5 2024 convening)" do
      result = described_class.covering(Date.new(2024, 11, 15), [balt_term_2020, balt_term_2024])
      expect(result).to eq(balt_term_2020)
    end

    # The three days the old first-Monday rule filed under the wrong term: Dec 2-4,
    # 2024 come after the first Monday but before the charter's Thursday start, so they
    # still belong to the 2020 term.
    it "buckets a Dec 4 2024 Baltimore vote to the OLD term and a Dec 5 vote to the new one (Charter Art. III § 2(a)(2) boundary)" do
      expect(described_class.covering(Date.new(2024, 12, 4), [balt_term_2020, balt_term_2024]))
        .to eq(balt_term_2020)
      expect(described_class.covering(Date.new(2024, 12, 5), [balt_term_2020, balt_term_2024]))
        .to eq(balt_term_2024)
    end

    it "returns nil when the vote precedes every term's convening date" do
      result = described_class.covering(Date.new(2019, 1, 1), [term_2023_congress])
      expect(result).to be_nil
    end

    # @lat: [[current-legislator-term#A term carries the day it really began]]
    describe "a term that carries the day it really began" do
      let(:arrived_mid_cycle) do
        TermWindowCandidate.new(2025, congress_locale, Date.new(2025, 9, 2))
      end

      it "holds no vote cast before that day" do
        expect(described_class.covering(Date.new(2025, 9, 1), [arrived_mid_cycle])).to be_nil
        expect(described_class.covering(Date.new(2025, 9, 2), [arrived_mid_cycle]))
          .to eq(arrived_mid_cycle)
      end

      it "reads from the handover day when no start date was recorded" do
        expect(described_class.covering(Date.new(2025, 9, 1), [term_2025_congress]))
          .to eq(term_2025_congress)
      end

      # The predecessor keeps the part of the cycle they served, so no vote in
      # it falls outside every term.
      it "leaves the earlier part of the cycle with whoever really held the seat" do
        predecessor = TermWindowCandidate.new(2023, congress_locale)

        expect(described_class.covering(Date.new(2025, 3, 1), [predecessor, arrived_mid_cycle]))
          .to eq(predecessor)
      end
    end
  end

  # .covering asks only whether a term has begun, which is right for
  # attributing a vote and wrong for "is this person in office today".
  # .running_on asks both ends.
  describe ".running_on" do
    let(:congress_2023) { BoundedTermWindowCandidate.new(2023, 2025, congress_locale) }
    let(:congress_2025) { BoundedTermWindowCandidate.new(2025, 2027, congress_locale) }
    let(:senate_2025) { BoundedTermWindowCandidate.new(2025, 2031, congress_locale) }
    let(:balt_2020) { BoundedTermWindowCandidate.new(2020, 2024, baltimore_local_locale) }
    let(:balt_2024) { BoundedTermWindowCandidate.new(2024, 2028, baltimore_local_locale) }

    it "returns the term running on the date" do
      expect(described_class.running_on(Date.new(2026, 6, 1), [congress_2023, congress_2025]))
        .to eq(congress_2025)
    end

    # The defect itself: .covering returns the ended term, .running_on returns nothing.
    it "returns nil once the only term has ended, where .covering still returns it" do
      expect(described_class.covering(Date.new(2026, 6, 1), [congress_2023])).to eq(congress_2023)
      expect(described_class.running_on(Date.new(2026, 6, 1), [congress_2023])).to be_nil
    end

    # @lat: [[term-window-design#Why a term carrying its real end day matters]]
    describe "a term that carries the day it really ended" do
      let(:graham_left_early) do
        BoundedTermWindowCandidate.new(2025, 2027, congress_locale, Date.new(2026, 7, 11))
      end

      it "stops running on that day, not at the next handover" do
        expect(described_class.running_on(Date.new(2026, 7, 10), [graham_left_early]))
          .to eq(graham_left_early)
        expect(described_class.running_on(Date.new(2026, 7, 11), [graham_left_early])).to be_nil
        expect(described_class.running_on(Date.new(2026, 12, 1), [graham_left_early])).to be_nil
      end

      it "keeps reading to the handover day when no date was published" do
        no_date = BoundedTermWindowCandidate.new(2025, 2027, congress_locale)

        expect(described_class.running_on(Date.new(2026, 12, 1), [no_date])).to eq(no_date)
        expect(described_class.running_on(Date.new(2027, 1, 3), [no_date])).to be_nil
      end

      # Widening is what put two people in one seat. The successor is seated
      # while the person who left has not stopped, so both read as running.
      it "leaves one person in a seat once the person who left has a real end date" do
        successor = BoundedTermWindowCandidate.new(2026, 2027, congress_locale)

        expect(described_class.running_on(Date.new(2026, 8, 1), [graham_left_early, successor]))
          .to eq(successor)
      end

      # Attribution is unchanged: a vote cast during the term still belongs to
      # it. Narrowing the window for .covering would drop those votes outside
      # every term the person holds, which is the worse error.
      it "still holds every vote cast while the person was there" do
        expect(described_class.covering(Date.new(2026, 3, 1), [graham_left_early]))
          .to eq(graham_left_early)
      end
    end

    # A person is not in office before the day they arrived, so a
    # term recording that day must not report them as serving beforehand.
    it "does not report somebody as serving before the day their term began" do
      arrived_mid_cycle =
        BoundedTermWindowCandidate.new(2025, 2027, congress_locale, nil, Date.new(2025, 9, 2))

      expect(described_class.running_on(Date.new(2025, 9, 1), [arrived_mid_cycle])).to be_nil
      expect(described_class.running_on(Date.new(2025, 9, 2), [arrived_mid_cycle]))
        .to eq(arrived_mid_cycle)
    end

    it "returns nil for a Baltimore member who left when the 2024 term convened" do
      expect(described_class.running_on(Date.new(2026, 6, 1), [balt_2020])).to be_nil
      expect(described_class.running_on(Date.new(2024, 6, 1), [balt_2020])).to eq(balt_2020)
    end

    # Back-to-back terms must never both be running: one ends exactly where the
    # next convenes, so the boundary day belongs to the new term only.
    it "hands the boundary day to the incoming term, never to both" do
      handover = Date.new(2024, 12, 5) # the 2024 Baltimore convening
      expect(described_class.running_on(handover - 1, [balt_2020, balt_2024])).to eq(balt_2020)
      expect(described_class.running_on(handover, [balt_2020, balt_2024])).to eq(balt_2024)
    end

    it "keeps a senator through the middle of a six-year term where a two-year span would not" do
      mid_term = Date.new(2029, 6, 1)
      expect(described_class.running_on(mid_term, [senate_2025])).to eq(senate_2025)
      expect(described_class.running_on(mid_term, [congress_2025])).to be_nil
    end

    it "returns nil before any term has begun" do
      expect(described_class.running_on(Date.new(2019, 1, 1), [congress_2023])).to be_nil
    end
  end

  describe ".cycle_start_year multi-cycle boundaries" do
    it "steps back to the previous cycle before convening day and advances on convening day across all locales" do
      expect(described_class.cycle_start_year(congress_locale, Date.new(2025, 1, 2))).to eq(2023)
      expect(described_class.cycle_start_year(congress_locale, Date.new(2025, 1, 3))).to eq(2025)
      expect(described_class.cycle_start_year(congress_locale, Date.new(2026, 12, 31))).to eq(2025)

      expect(described_class.cycle_start_year(maryland_regional_locale, Date.new(2023, 1, 10))).to eq(2019)
      expect(described_class.cycle_start_year(maryland_regional_locale, Date.new(2023, 1, 11))).to eq(2023)
      expect(described_class.cycle_start_year(maryland_regional_locale, Date.new(2027, 1, 12))).to eq(2023)
      expect(described_class.cycle_start_year(maryland_regional_locale, Date.new(2027, 1, 13))).to eq(2027)

      expect(described_class.cycle_start_year(baltimore_local_locale, Date.new(2024, 12, 4))).to eq(2020)
      expect(described_class.cycle_start_year(baltimore_local_locale, Date.new(2024, 12, 5))).to eq(2024)
      expect(described_class.cycle_start_year(baltimore_local_locale, Date.new(2028, 12, 6))).to eq(2024)
      expect(described_class.cycle_start_year(baltimore_local_locale, Date.new(2028, 12, 7))).to eq(2028)
    end
  end
end
