# frozen_string_literal: true

require "rails_helper"

# @lat: [[jurisdiction-rules#Declared executives]]
RSpec.describe SwayLocale::OpenStatesExecutivesRegistry do
  it "hands back the executives declared for a locale" do
    titles = described_class
      .for("maryland-maryland-united_states")
      .map { |executive| executive.dig("current_role", "title") }

    expect(titles).to include("Governor", "Lt. Governor", "Attorney General")
  end

  # A missing Governor is a gap a reader can see. Another state's Governor is a
  # lie they cannot, so an undeclared locale gets nothing rather than a guess.
  it "hands back nothing for a locale with no entry" do
    expect(described_class.for("delaware-delaware-united_states")).to eq([])
    expect(described_class.declared?("delaware-delaware-united_states")).to be(false)
  end

  it "declares executives only for locales that read OpenStates" do
    described_class.declared_locale_names.each do |locale_name|
      rules = SwayLocale::JurisdictionRulesRegistry.fetch(locale_name)

      expect((rules.roster_rules&.[](:retrieval) || rules.roster_rules&.[](:engine))&.to_sym).to eq(:open_states),
        "#{locale_name} declares executives for the OpenStates fetch but does not read OpenStates"
    end
  end

  # A made-up id matches no stored row, so the next reseed inserts a second
  # copy and cuts the original loose from the users paired with it.
  it "uses each executive's real OpenStates id, never a made-up slug" do
    uuid = %r{\Aocd-person/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z}

    described_class::DECLARATIONS.each do |locale_name, executives|
      executives.each do |executive|
        expect(executive["id"]).to match(uuid),
          "#{locale_name}: #{executive["family_name"]} carries an id that matches no stored row"
      end
    end
  end

  # The Governor's site hands a browser an address that stops working after ten
  # minutes. Everything before the "?" works on its own — measured.
  it "stores photo addresses that do not expire" do
    described_class::DECLARATIONS.each_value do |executives|
      executives.each do |executive|
        image = executive["image"].to_s

        expect(image).not_to include("X-Amz-Signature"),
          "#{executive["family_name"]}: this address carries a signature and will stop working"
        expect(image).not_to include("?"),
          "#{executive["family_name"]}: strip the query string — the address works without it"
      end
    end
  end

  # Every field SeedPreparers::Legislators::OpenStates reads, so an entry that
  # would take the whole seed down is caught here instead.
  it "carries every field the OpenStates seed preparer reads" do
    described_class::DECLARATIONS.each_value do |executives|
      executives.each do |executive|
        expect(executive.fetch("id")).to be_present
        expect(executive.fetch("given_name")).to be_present
        expect(executive.fetch("family_name")).to be_present
        expect(executive.dig("current_role", "title")).to be_present
        expect(executive.dig("current_role", "org_classification")).to be_present
        expect(executive.dig("jurisdiction", "name")).to be_present
      end
    end
  end
end
