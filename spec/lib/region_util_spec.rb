# frozen_string_literal: true

require "rails_helper"

# @lat: [[region-util-dead-code-removal#Why from_country_name_to_code and COUNTRY_NAMES_CODES were deleted]]
RSpec.describe RegionUtil do
  describe ".from_region_name_to_region_code" do
    it "maps a full state name to its two-letter code" do
      expect(described_class.from_region_name_to_region_code("Maryland")).to eq("MD")
    end

    it "returns nil for a blank name and passes a 2-char code straight through (upcased)" do
      expect(described_class.from_region_name_to_region_code(nil)).to be_nil
      expect(described_class.from_region_name_to_region_code("md")).to eq("MD")
    end
  end

  describe ".from_region_code_to_region_name" do
    it "maps a two-letter code to its full state name" do
      expect(described_class.from_region_code_to_region_name("MD")).to eq("Maryland")
    end

    it "returns nil for a blank code" do
      expect(described_class.from_region_code_to_region_name(nil)).to be_nil
      expect(described_class.from_region_code_to_region_name("")).to be_nil
    end
  end

  describe ".from_country_code_to_name" do
    it "returns nil for a blank code" do
      expect(described_class.from_country_code_to_name(nil)).to be_nil
      expect(described_class.from_country_code_to_name("")).to be_nil
    end

    it "maps US to United States" do
      expect(described_class.from_country_code_to_name("US")).to eq("United States")
    end

    it "maps every spelling of the United States to United States" do
      ["USA", "usa", "U.S.", "U.S.A.", "United States", "United States of America", "  USA  "].each do |spelling|
        expect(described_class.from_country_code_to_name(spelling)).to eq("United States"), spelling
      end
    end

    it "returns the code when a two-letter country code is not in the lookup table" do
      expect(described_class.from_country_code_to_name("CA")).to eq("CA")
    end

    it "title-cases a country name that is not the United States" do
      expect(described_class.from_country_code_to_name("canada")).to eq("Canada")
    end
  end

  describe "constant hashes" do
    it "are frozen" do
      expect(described_class::COUNTRY_CODES_NAMES).to be_frozen
      expect(described_class::UNITED_STATES_SPELLINGS).to be_frozen
      expect(described_class::STATE_NAMES_CODES).to be_frozen
      expect(described_class::STATE_CODES_NAMES).to be_frozen
    end
  end
end
