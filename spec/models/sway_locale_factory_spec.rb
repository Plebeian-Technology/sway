# frozen_string_literal: true

require "rails_helper"

# @lat: [[sway-locale-factory-design#Why the address factory hardcodes a real city]]
# Checked directly here (not left to the suite) because the defect only ever appeared in a FULL run.
RSpec.describe "the sway_locale factory" do
  it "refuses a jurisdiction named only in part" do
    expect { create(:sway_locale, state: "MD") }
      .to raise_error(ArgumentError, /names part of a jurisdiction/)

    expect { create(:sway_locale, city: "baltimore") }
      .to raise_error(ArgumentError, /names part of a jurisdiction/)

    expect { create(:sway_locale, city: "annapolis", state: "maryland") }
      .to raise_error(ArgumentError, /names part of a jurisdiction/)
  end

  it "names the traits in the refusal, so the fix is in the message" do
    expect { create(:sway_locale, state: "MD") }
      .to raise_error(ArgumentError, /:baltimore, :maryland, :congress/)
  end

  it "builds a jurisdiction named in full, declared or not" do
    declared = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
    expect(declared.name).to eq("baltimore-maryland-united_states")

    # A city nobody has declared is still a real request, and registration makes
    # these in production — a row for each reader's city and state.
    undeclared = create(:sway_locale, city: "chicago", state: "illinois", country: "united_states")
    expect(undeclared.name).to eq("chicago-illinois-united_states")
  end

  describe "the traits" do
    it "each names one of the three jurisdictions Sway seeds" do
      expect(create(:sway_locale, :baltimore).name).to eq("baltimore-maryland-united_states")
      expect(create(:sway_locale, :maryland).name).to eq("maryland-maryland-united_states")
      expect(create(:sway_locale, :congress).name).to eq("congress-congress-united_states")
    end

    it "gives a spec two jurisdictions it can tell apart" do
      first = create(:sway_locale, :baltimore)
      second = create(:sway_locale, :maryland)

      expect(first.id).not_to eq(second.id)
    end
  end

  describe "naming nothing at all" do
    it "still hands back a jurisdiction Sway declares" do
      sway_locale = create(:sway_locale)

      expect(SwayLocale::TermRulesRegistry.declared?(sway_locale.name)).to be(true)
      expect(SwayLocale::JurisdictionRulesRegistry.declared?(sway_locale.name)).to be(true)
    end

    it "moves on to a different one next time" do
      expect(create(:sway_locale).name).not_to eq(create(:sway_locale).name)
    end
  end
end
