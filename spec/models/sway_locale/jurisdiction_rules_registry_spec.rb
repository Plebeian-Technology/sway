# frozen_string_literal: true

require "rails_helper"

# @lat: [[jurisdiction-rules-design#Why the Bill Creator still draws for an undeclared jurisdiction]]
RSpec.describe SwayLocale::JurisdictionRulesRegistry do
  describe ".fetch" do
    it "refuses a locale it does not name, instead of falling through to another one" do
      expect { described_class.fetch("philadelphia-pennsylvania-united_states") }
        .to raise_error(SwayLocale::JurisdictionRules::Undeclared, /philadelphia-pennsylvania-united_states/)
    end

    it "says what to do about it, and why guessing is not an option" do
      message = begin
        described_class.fetch("austin-texas-united_states")
      rescue SwayLocale::JurisdictionRules::Undeclared => e
        e.message
      end

      expect(message).to include("DECLARATIONS")
      expect(message).to include("another city's dates")
    end

    it "declares sources when a new YAML file is added without modifying Ruby registries" do
      synthetic_doc = SwayLocale::DocumentReader::Document.new(
        {
          "schema_version" => 1,
          "city" => "annapolis",
          "region" => "maryland",
          "country" => "united_states",
          "name" => "annapolis-maryland-united_states",
          "time_zone" => "America/New_York",
          "source_rules" => {
            "publishes_legislator_votes" => false,
            "chamber_label" => "City Council",
            "session_numbering" => "term_years",
            "default_bill_chamber" => "council",
            "bill_chambers" => ["council"],
            "roster_rules" => {"retrieval" => "curated", "parsing" => "curated"},
            "vote_rules" => {"retrieval" => "manual", "parsing" => "manual"},
            "legislation_rules" => {"retrieval" => "legistar", "parsing" => "legistar", "base_url" => "https://webapi.legistar.com/v1"},
            "law_rules" => {"retrieval" => "unavailable", "parsing" => "unavailable"},
            "hearings_rules" => {"retrieval" => "legistar", "parsing" => "legistar", "base_url" => "https://webapi.legistar.com/v1"}
          },
          "term_rules" => {
            "convening" => {"kind" => "fixed_day", "month" => 1, "day" => 1},
            "cycle_anchor_year" => 2025,
            "cycle_years" => 4,
            "roster_lists_only_current_legislators" => true,
            "publishes_term_history" => false,
            "publishes_exact_term_dates" => false,
            "identified_by" => "seat"
          }
        },
        filename: "annapolis-maryland-united_states.yml"
      )

      allow(SwayLocale::DocumentReader).to receive(:find_by_name)
        .with("annapolis-maryland-united_states")
        .and_return(synthetic_doc)
      allow(SwayLocale::DocumentReader).to receive(:declared_locale_names)
        .and_return(SwayLocale::DocumentReader.declared_locale_names + ["annapolis-maryland-united_states"])

      expect(described_class.declared?("annapolis-maryland-united_states")).to be(true)
      rules = described_class.fetch("annapolis-maryland-united_states")
      expect(rules.roster_rules[:retrieval]).to eq("curated")
      expect(rules.roster_rules[:parsing]).to eq("curated")
      expect(rules.vote_rules[:retrieval]).to eq("manual")
      expect(rules.vote_rules[:parsing]).to eq("manual")
      expect(rules.chamber_label).to eq("City Council")
      expect(rules.respond_to?(:roster_source)).to be(false)
      expect(rules.respond_to?(:roster_refresher)).to be(false)
    end
  end

  # The gate that fires on the change that caused this issue: somebody adds a
  # locale to the seed file and does not say where its data comes from.
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

  # Two registries now have to be kept in step. A locale with a calendar and no
  # data sources still refuses at the first vote fetch — which is right, but it
  # would refuse a long way from the file somebody forgot to edit.
  describe "against the term rules" do
    it "declares the same locales" do
      expect(described_class.declared_locale_names.sort)
        .to eq(SwayLocale::TermRulesRegistry.declared_locale_names.sort)
    end
  end

  # The declarations themselves, pinned so a later edit has to be deliberate.
  describe "the declared locales" do
    let(:congress) { described_class.fetch("congress-congress-united_states") }
    let(:maryland) { described_class.fetch("maryland-maryland-united_states") }
    let(:baltimore) { described_class.fetch("baltimore-maryland-united_states") }

    it "names where each roster and each set of votes comes from via rules" do
      expect([congress.roster_rules[:retrieval], congress.vote_rules[:retrieval]]).to eq(["congress_dot_gov", "congress_dot_gov"])
      expect([congress.roster_rules[:parsing], congress.vote_rules[:parsing]]).to eq(["congress_dot_gov", "congress_dot_gov"])
      expect([maryland.roster_rules[:retrieval], maryland.vote_rules[:retrieval]]).to eq(["open_states", "maryland_general_assembly"])
      expect([maryland.roster_rules[:parsing], maryland.vote_rules[:parsing]]).to eq(["open_states", "generic_html"])
      expect([baltimore.roster_rules[:retrieval], baltimore.vote_rules[:retrieval]]).to eq(["curated", "legistar"])
      expect([baltimore.roster_rules[:parsing], baltimore.vote_rules[:parsing]]).to eq(["curated", "legistar"])
    end

    it "names where each locale's legislation and law corpus come from via rules" do
      expect([congress.legislation_rules[:retrieval], congress.law_rules[:retrieval]]).to eq(["congress_dot_gov", "uslm_xml"])
      expect([congress.legislation_rules[:parsing], congress.law_rules[:parsing]]).to eq(["congress_dot_gov", "uslm_xml"])
      expect([maryland.legislation_rules[:retrieval], maryland.law_rules[:retrieval]]).to eq(["generic_html", "configured_pdf_catalog"])
      expect([maryland.legislation_rules[:parsing], maryland.law_rules[:parsing]]).to eq(["generic_html", "pdf_statute_sections"])
      expect([baltimore.legislation_rules[:retrieval], baltimore.law_rules[:retrieval]]).to eq(["legistar", "akoma_ntoso"])
      expect([baltimore.legislation_rules[:parsing], baltimore.law_rules[:parsing]]).to eq(["legistar", "akoma_ntoso"])
    end

    # Integration rules no longer declare client; multi-tenant Legistar clients are derived
    # from the jurisdiction's city identity.
    it "verifies client absence from integration rules with city fallback" do
      expect(baltimore.legislation_rules[:client]).to be_nil
      expect(baltimore.hearings_rules[:client]).to be_nil
      expect(baltimore.vote_rules[:client]).to be_nil
      expect(congress.legislation_rules[:client]).to be_nil
      expect(maryland.legislation_rules[:client]).to be_nil
    end

    # @lat: [[jurisdiction-rules#Source pairing]]
    it "names the OpenStates jurisdiction in rules only for the locale that reads OpenStates" do
      expect(maryland.roster_rules[:jurisdiction]).to eq("Maryland")
      expect(maryland.vote_rules[:jurisdiction]).to be_nil
      expect(congress.roster_rules[:jurisdiction]).to be_nil
      expect(baltimore.roster_rules[:jurisdiction]).to be_nil
    end

    it "does not expose deleted legacy source properties on rules" do
      [congress, maryland, baltimore].each do |rules|
        expect(rules.respond_to?(:roster_source)).to be(false)
        expect(rules.respond_to?(:roster_refresher)).to be(false)
        expect(rules.respond_to?(:vote_source)).to be(false)
        expect(rules.respond_to?(:legistar_client)).to be(false)
        expect(rules.respond_to?(:open_states_jurisdiction)).to be(false)
        expect(rules.respond_to?(:legislation_source)).to be(false)
        expect(rules.respond_to?(:law_source)).to be(false)
        expect(rules.respond_to?(:hearings_source)).to be(false)
      end
    end

    # Baltimore records only whether a matter passed, never how each member
    # voted, so its bills are scored without the two vote signals. This is a
    # fact about the publisher, not about being a city.
    it "records whether the jurisdiction says how each member voted" do
      expect(congress.publishes_legislator_votes).to be(true)
      expect(maryland.publishes_legislator_votes).to be(true)
      expect(baltimore.publishes_legislator_votes).to be(false)
    end

    it "names the body and how it numbers a session" do
      expect([congress.chamber_label, congress.session_numbering]).to eq(["Congress", :congress_ordinal])
      expect([maryland.chamber_label, maryland.session_numbering]).to eq(["General Assembly", :term_years])
      expect([baltimore.chamber_label, baltimore.session_numbering]).to eq(["City Council", :term_years])
    end

    # The Bill Creator used to start every non-Congress bill at "council",
    # including in Maryland, whose General Assembly has no council.
    it "says which chamber a new bill starts in" do
      expect(congress.default_bill_chamber).to eq("house")
      expect(maryland.default_bill_chamber).to eq("house")
      expect(baltimore.default_bill_chamber).to eq("council")
    end

    # @lat: [[jurisdiction-rules-design#bill_chambers: replacing a guess with a declaration]]
    it "says every chamber a bill there can be in" do
      expect(congress.bill_chambers).to eq(%w[house senate both])
      expect(maryland.bill_chambers).to eq(%w[house senate both])
      expect(baltimore.bill_chambers).to eq(%w[council])
    end

    it "offers a chamber to pick, and a senate vote date, only where there is one" do
    end
  end
end
