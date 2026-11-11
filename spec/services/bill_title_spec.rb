# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillTitle do
  # Every title here is also a case in billTitle.test.ts, and the parity
  # examples below fail when one of them stops appearing there.
  let(:shared_cases) do
    {
      "Clean Energy Act - modernizing the grid" => "Clean Energy Act",
      "Clean Energy Act – modernizing the grid" => "Clean Energy Act",
      "Clean Energy Act — modernizing the grid" => "Clean Energy Act",
      "Property Tax Credit FOR the purpose of altering the credit" => "Property Tax Credit",
      "Property Tax Credit for the purpose of altering the credit" => "Property Tax Credit",
      "Budget Bill - fiscal year 2026 FOR the purpose of appropriating funds" => "Budget Bill",
      "A Resolution Honoring Volunteers" => "A Resolution Honoring Volunteers",
      "Transit Act - phase one - downtown corridor" => "Transit Act",
      "  Spacious Title  " => "Spacious Title",
      "" => ""
    }
  end

  describe ".headline" do
    it "drops a hyphen-separated qualifier" do
      expect(described_class.headline("Clean Energy Act - modernizing the grid")).to eq("Clean Energy Act")
    end

    it "drops an en-dash-separated qualifier" do
      expect(described_class.headline("Clean Energy Act – modernizing the grid")).to eq("Clean Energy Act")
    end

    it "drops an em-dash-separated qualifier" do
      expect(described_class.headline("Clean Energy Act — modernizing the grid")).to eq("Clean Energy Act")
    end

    it "drops the 'FOR the purpose of' clause" do
      expect(
        described_class.headline("Property Tax Credit FOR the purpose of altering the credit")
      ).to eq("Property Tax Credit")
    end

    it "matches the clause whatever its capitalisation" do
      expect(
        described_class.headline("Property Tax Credit for the purpose of altering the credit")
      ).to eq("Property Tax Credit")
    end

    it "reads the qualifier out of the text in front of the clause" do
      expect(
        described_class.headline("Budget Bill - fiscal year 2026 FOR the purpose of appropriating funds")
      ).to eq("Budget Bill")
    end

    it "returns the whole title when it carries neither a clause nor a dash" do
      expect(described_class.headline("A Resolution Honoring Volunteers")).to eq("A Resolution Honoring Volunteers")
    end

    it "cuts at the first dash and leaves later ones in the part it drops" do
      expect(described_class.headline("Transit Act - phase one - downtown corridor")).to eq("Transit Act")
    end

    it "trims surrounding whitespace" do
      expect(described_class.headline("  Spacious Title  ")).to eq("Spacious Title")
    end

    it "returns an empty string for an empty title" do
      expect(described_class.headline("")).to eq("")
    end

    it "returns an empty string for nil" do
      expect(described_class.headline(nil)).to eq("")
    end

    it "returns an empty string for a title that is only whitespace" do
      expect(described_class.headline("   \n  ")).to eq("")
    end

    # A dash the browser cannot split on either: `.` does not cross a newline
    # on either side, so the title arrives whole rather than half-cut.
    it "leaves a title whose dash sits on another line alone" do
      expect(described_class.headline("Title\nline – deck")).to eq("Title\nline – deck")
    end

    it "keeps a dash that carries no spaces around it" do
      expect(described_class.headline("E-Bike Rebate Program")).to eq("E-Bike Rebate Program")
    end
  end

  # @lat: [[bill-title-display#Which outbound messages carry the shortened title]]
  describe "parity with the browser helper" do
    let(:helper_source) do
      Rails.root.join("app", "frontend", "components", "bill", "sway_utils", "billTitle.ts").read
    end
    let(:helper_test_source) do
      Rails.root.join(
        "app", "frontend", "components", "bill", "sway_utils", "__tests__", "billTitle.test.ts"
      ).read
    end

    it "cuts at the clause the browser cuts at" do
      expect(helper_source).to include('split(/\s+FOR\s+the\s+purpose\s+of\s+/i)')
    end

    it "splits on the three dash characters the browser splits on" do
      expect(helper_source).to include('match(/^(.+?)\s+[–—-]\s+(.+)$/)')
    end

    it "answers every title the browser helper's own tests use" do
      absent = shared_cases.keys.reject { |title| title.empty? || helper_test_source.include?(title) }

      expect(absent).to be_empty,
        "these no longer appear in billTitle.test.ts, so the two sides can drift: #{absent.inspect}"
    end

    it "produces the headline the browser produces for each of them" do
      shared_cases.each do |title, headline|
        expect(described_class.headline(title)).to eq(headline)
      end
    end
  end
end
