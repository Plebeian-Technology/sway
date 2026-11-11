# frozen_string_literal: true

require "rails_helper"

# @lat: [[term-rules-design#The problem TermRules replaced]]
RSpec.describe SwayLocale::TermRulesRegistry do
  describe ".fetch" do
    it "refuses a locale it does not name, instead of falling through to another one" do
      expect { described_class.fetch("philadelphia-pennsylvania-united_states") }
        .to raise_error(SwayLocale::TermRules::Undeclared, /philadelphia-pennsylvania-united_states/)
    end

    it "says what to do about it, and why guessing is not an option" do
      message = begin
        described_class.fetch("austin-texas-united_states")
      rescue SwayLocale::TermRules::Undeclared => e
        e.message
      end

      expect(message).to include("DECLARATIONS")
      expect(message).to include("wrong term")
    end
  end

  # The gate that fires on the change that caused this issue: somebody adds a
  # locale to the seed file and does not declare how its terms run.
  describe "every seeded locale" do
    it "has a declaration" do
      seeded = SeedSwayLocale.read_locales

      undeclared = seeded.reject { |entry|
        item = entry.with_indifferent_access
        name = SwayLocale.new(
          city: item.fetch(:city),
          state: item[:region] || item[:state],
          country: item.fetch(:country)
        ).name

        described_class.declared?(name)
      }

      expect(undeclared.map { |e| (e[:name] || e["name"]).presence || e.to_s }).to eq([])
    end
  end

  # The declarations themselves, pinned so a later edit has to be deliberate.
  # The dates each one produces are checked through TermWindow, which is what
  # the rest of the app calls.
  describe "the declared locales" do
    it "records how long a cycle runs and a year one really began" do
      congress = described_class.fetch("congress-congress-united_states")
      maryland = described_class.fetch("maryland-maryland-united_states")
      baltimore = described_class.fetch("baltimore-maryland-united_states")

      expect([congress.cycle_anchor_year, congress.cycle_years]).to eq([1991, 2])
      expect([maryland.cycle_anchor_year, maryland.cycle_years]).to eq([2023, 4])
      expect([baltimore.cycle_anchor_year, baltimore.cycle_years]).to eq([2024, 4])
    end

    # @lat: [[current-legislator-term#Roster evidence for observed departures]]
    it "records what each roster source can prove" do
      congress = described_class.fetch("congress-congress-united_states")
      maryland = described_class.fetch("maryland-maryland-united_states")
      baltimore = described_class.fetch("baltimore-maryland-united_states")

      # Congress keeps people who have left and marks them, and publishes every
      # past term with the day it ended.
      expect(congress.roster_lists_only_current_legislators).to be(false)
      expect(congress.publishes_term_history).to be(true)
      expect(congress.publishes_exact_term_dates).to be(true)
      expect(congress.identified_by).to eq(:person)

      # OpenStates answers with sitting members only, so somebody dropping out
      # of the file is the only sign Sway gets that they left.
      expect(maryland.roster_lists_only_current_legislators).to be(true)
      expect(maryland.publishes_term_history).to be(false)
      expect(maryland.identified_by).to eq(:person)

      # @lat: [[term-rules-design#Why Baltimore's roster_lists_only_current_members went from false to true]]
      expect(baltimore.roster_lists_only_current_legislators).to be(true)
      expect(baltimore.publishes_term_history).to be(false)
      expect(baltimore.identified_by).to eq(:seat)
    end

    # @lat: [[current-legislator-term#Why the candidates are bounded in SQL first]]
    it "convenes inside the year it is asked about, for every declared locale" do
      out_of_year = described_class::DECLARATIONS.flat_map { |locale_name, rules|
        (2000..2100).filter_map { |year|
          convened_on = rules.convening.date_in(year)
          "#{locale_name} #{year} -> #{convened_on}" unless convened_on.year == year
        }
      }

      expect(out_of_year).to eq([])
    end

    it "declares a fourth supported calendar solely in that SwayLocale YAML file" do
      synthetic_slug = "synthetic-maryland-united_states"
      synthetic_doc = SwayLocale::DocumentReader::Document.new(
        {
          "schema_version" => 1,
          "city" => "synthetic",
          "region" => "maryland",
          "country" => "united_states",
          "name" => synthetic_slug,
          "time_zone" => "America/New_York",
          "source_rules" => {
            "roster_source" => "curated",
            "roster_refresher" => "unavailable",
            "vote_source" => "manual",
            "publishes_legislator_votes" => false,
            "chamber_label" => "City Council",
            "session_numbering" => "term_years",
            "default_bill_chamber" => "council",
            "bill_chambers" => ["council"]
          },
          "term_rules" => {
            "convening" => {"kind" => "fixed_day", "month" => 12, "day" => 1},
            "cycle_anchor_year" => 2025,
            "cycle_years" => 4,
            "roster_lists_only_current_legislators" => true,
            "publishes_term_history" => false,
            "publishes_exact_term_dates" => false,
            "identified_by" => "seat"
          }
        },
        filename: "#{synthetic_slug}.yml"
      )

      allow(SwayLocale::DocumentReader).to receive(:find)
        .with(synthetic_slug)
        .and_return(synthetic_doc)
      allow(SwayLocale::DocumentReader).to receive(:declared_locale_names)
        .and_return(SwayLocale::DocumentReader.declared_locale_names + [synthetic_slug])

      expect(described_class.declared?(synthetic_slug)).to be(true)
      rules = described_class.fetch(synthetic_slug)
      expect(rules.cycle_anchor_year).to eq(2025)
      expect(rules.cycle_years).to eq(4)
      expect(rules.convening).to be_a(SwayLocale::FixedDayConvening)
      expect(rules.convening.date_in(2025)).to eq(Date.new(2025, 12, 1))
    end
  end
end
