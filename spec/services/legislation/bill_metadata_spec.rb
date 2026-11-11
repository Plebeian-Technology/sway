# frozen_string_literal: true

require "rails_helper"

# Legislation::BillMetadata is one of two places that READ metadata.json;
# earlier work rescued filesystem/IO errors on every WRITE but neither read.
module LegislationBillMetadataSpecHelpers
  ROOT = LegislationTestArtifacts.root_for("legislation_bill_metadata").freeze

  # Every example here uses one jurisdiction. "25-0064" is a Baltimore bill
  # number, and the whole reason the segment exists is that the number alone
  # does not say which city, so the fixture has to.
  SWAY_LOCALE = "baltimore-maryland-united_states"

  def self.dir_for(external_id)
    Pathname.new(ROOT).join(SWAY_LOCALE, external_id)
  end

  def self.write(external_id, contents)
    dir = dir_for(external_id)
    dir.mkpath
    dir.join("metadata.json").write(contents)
  end
end

RSpec.describe Legislation::BillMetadata do
  around do |example|
    FileUtils.rm_rf(LegislationBillMetadataSpecHelpers::ROOT)
    with_app_config(:legislation, legislation_bills_raw_root: LegislationBillMetadataSpecHelpers::ROOT) {
      example.run
    }
  ensure
    FileUtils.rm_rf(LegislationBillMetadataSpecHelpers::ROOT)
  end

  describe ".matter_id" do
    it "reads matter_id out of the bill's metadata.json" do
      LegislationBillMetadataSpecHelpers.write("25-0064", {matter_id: 10122}.to_json)

      expect(described_class.matter_id("25-0064", sway_locale: LegislationBillMetadataSpecHelpers::SWAY_LOCALE)).to eq(10122)
    end

    it "returns nil when the file is absent" do
      expect(described_class.matter_id("25-0064", sway_locale: LegislationBillMetadataSpecHelpers::SWAY_LOCALE)).to be_nil
    end

    it "returns nil when the file is not JSON" do
      LegislationBillMetadataSpecHelpers.write("25-0064", "not json {")

      expect(described_class.matter_id("25-0064", sway_locale: LegislationBillMetadataSpecHelpers::SWAY_LOCALE)).to be_nil
    end

    it "returns nil when the JSON is not an object" do
      LegislationBillMetadataSpecHelpers.write("25-0064", "[1, 2, 3]")

      expect(described_class.matter_id("25-0064", sway_locale: LegislationBillMetadataSpecHelpers::SWAY_LOCALE)).to be_nil
    end

    it "returns nil when the external_id cannot name a path segment (A1-CR-02)" do
      expect(described_class.matter_id("../../etc/passwd", sway_locale: LegislationBillMetadataSpecHelpers::SWAY_LOCALE)).to be_nil
    end

    # The locale is the OTHER half of the path, checked the same way as
    # external_id: a value that cant be one segment must answer no metadata,
    # not read a file somewhere else.
    it "returns nil when the sway_locale cannot name a path segment" do
      expect(described_class.matter_id("25-0064", sway_locale: "../../etc")).to be_nil
    end

    it "returns nil when the sway_locale is missing altogether" do
      expect(described_class.matter_id("25-0064", sway_locale: nil)).to be_nil
    end

    # This used to return parsed["matter_id"] with no type check, though the
    # signature promised Integer|String — Steep believed the else branch
    # could never run. Narrowing happens HERE now.
    describe "type narrowing at the untrusted-JSON boundary (A1-WR-06)" do
      it "passes an Integer matter_id through" do
        LegislationBillMetadataSpecHelpers.write("25-0064", {matter_id: 10122}.to_json)

        expect(described_class.matter_id("25-0064", sway_locale: LegislationBillMetadataSpecHelpers::SWAY_LOCALE)).to eq(10122)
      end

      it "passes a String matter_id through (HI-04 accepts digit strings)" do
        LegislationBillMetadataSpecHelpers.write("25-0064", {matter_id: "10122"}.to_json)

        expect(described_class.matter_id("25-0064", sway_locale: LegislationBillMetadataSpecHelpers::SWAY_LOCALE)).to eq("10122")
      end

      # A String that doesnt look like an id is worse than a Float, since
      # nothing downstream re-checks it — Legistar::Clients own uncaught error
      # used to end the whole run.
      {
        "letters" => "not-a-number",
        "a negative number" => "-5",
        "a decimal" => "10.5",
        "eleven digits" => "12345678901",
        "an empty string" => "",
        "digits with a space" => "101 22"
      }.each do |label, value|
        it "returns nil for a matter_id of #{label}" do
          LegislationBillMetadataSpecHelpers.write("25-0064", {matter_id: value}.to_json)

          expect(described_class.matter_id("25-0064", sway_locale: LegislationBillMetadataSpecHelpers::SWAY_LOCALE)).to be_nil
        end
      end

      it "returns nil for a numeric matter_id of zero" do
        LegislationBillMetadataSpecHelpers.write("25-0064", {matter_id: 0}.to_json)

        expect(described_class.matter_id("25-0064", sway_locale: LegislationBillMetadataSpecHelpers::SWAY_LOCALE)).to be_nil
      end

      it "returns nil for a numeric matter_id past what Legistar accepts" do
        LegislationBillMetadataSpecHelpers.write(
          "25-0064", {matter_id: Legistar::Client::ID_MAX + 1}.to_json
        )

        expect(described_class.matter_id("25-0064", sway_locale: LegislationBillMetadataSpecHelpers::SWAY_LOCALE)).to be_nil
      end

      # THE CASES THAT HAD TO FAIL FIRST. Each is a JSON value the type
      # signature claims can never arrive.
      {
        "a Float" => 3.5,
        "an Array" => [1, 2],
        "an Object" => {"nested" => 1},
        "a boolean" => true
      }.each do |label, value|
        it "returns nil for #{label} matter_id" do
          LegislationBillMetadataSpecHelpers.write("25-0064", {matter_id: value}.to_json)

          expect(described_class.matter_id("25-0064", sway_locale: LegislationBillMetadataSpecHelpers::SWAY_LOCALE)).to be_nil
        end
      end

      it "returns nil when the key is absent" do
        LegislationBillMetadataSpecHelpers.write("25-0064", {title: "no matter_id here"}.to_json)

        expect(described_class.matter_id("25-0064", sway_locale: LegislationBillMetadataSpecHelpers::SWAY_LOCALE)).to be_nil
      end
    end

    # THE CASE THAT HAD TO FAIL FIRST: a full disk or read-only mount raises
    # an error thats neither JSON::ParserError nor BillProcessingError,
    # failing the WHOLE run over one bill.
    it "returns nil when the file exists but cannot be read" do
      LegislationBillMetadataSpecHelpers.dir_for("25-0064").join("metadata.json").mkpath

      expect { described_class.matter_id("25-0064", sway_locale: LegislationBillMetadataSpecHelpers::SWAY_LOCALE) }.not_to raise_error
      expect(described_class.matter_id("25-0064", sway_locale: LegislationBillMetadataSpecHelpers::SWAY_LOCALE)).to be_nil
    end
  end
end
