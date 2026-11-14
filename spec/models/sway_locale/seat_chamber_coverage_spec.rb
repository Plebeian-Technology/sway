# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "sway_locale")
require Rails.root.join("db", "seeds", "models", "legislator")

RSpec.describe "Seat chamber coverage of the seeded rosters", type: :model do
  # @lat: [[seat-chamber-coverage-tests#Seat chamber coverage tests#Every roster title maps to a seat or a skipped office]]
  it "maps every roster title of every declared locale to a seat chamber or a skipped office" do
    SeedSwayLocale.run
    unmapped = []

    SwayLocale::TermRulesRegistry.declared_locale_names.each do |locale_name|
      sway_locale = SwayLocale.resolve_by_computed_name(locale_name) || raise("#{locale_name} not seeded")
      rules = sway_locale.term_rules
      expect(rules.seat_chambers).not_to be_empty, "#{locale_name} declares no seat chambers"

      SeedLegislator.read_legislators(sway_locale).each do |json|
        seed_legislator = SeedLegislator.new(json, sway_locale)
        next if seed_legislator.prepared.blank?
        next if seed_legislator.unconfigured_executive_office? || seed_legislator.prepared.executive?

        title = seed_legislator.prepared.title
        unmapped << "#{locale_name}: #{title.inspect}" if rules.seat_chamber_for(title).nil?
      end
    end

    expect(unmapped.uniq).to be_empty
  end

  # @lat: [[seat-chamber-coverage-tests#Seat chamber coverage tests#Every seeded current term has a seat or an unconfigured office]]
  it "gives every seeded current term a seat unless its office has no configured chamber" do
    sway_locales = SeedSwayLocale.run
    SeedLegislator.run(sway_locales)

    unseated = LegislatorTerm.current.where(seat_id: nil).includes(district: :sway_locale).filter_map do |term|
      rules = term.district.sway_locale.term_rules
      next if rules.seat_chambers.any? && rules.seat_chamber_for(term.title).nil?

      "#{term.district.sway_locale.name}: #{term.title.inspect} (term #{term.id})"
    end

    expect(LegislatorTerm.current).to exist
    expect(unseated).to be_empty
  end

  describe SwayLocale::TermRules, "#seat_chamber_for" do
    let(:maryland_rules) { SwayLocale::TermRulesRegistry.fetch("maryland-maryland-united_states") }

    # @lat: [[seat-chamber-coverage-tests#Seat chamber coverage tests#Title aliases reach the configured chamber]]
    it "returns the configured chamber for the State Delegate and State Senator aliases" do
      expect(maryland_rules.seat_chamber_for("State Delegate")).to eq(maryland_rules.seat_chamber_for("Delegate"))
      expect(maryland_rules.seat_chamber_for("State Delegate")).to eq("House of Delegates")
      expect(maryland_rules.seat_chamber_for("State Senator")).to eq("Senate")
    end

    # @lat: [[seat-chamber-coverage-tests#Seat chamber coverage tests#Blank and unknown titles have no chamber]]
    it "returns nil for a blank, nil or unconfigured title" do
      expect(maryland_rules.seat_chamber_for("")).to be_nil
      expect(maryland_rules.seat_chamber_for(nil)).to be_nil
      expect(maryland_rules.seat_chamber_for("Attorney General")).to be_nil
    end
  end
end
