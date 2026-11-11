# frozen_string_literal: true

require "rails_helper"

RSpec.describe Legislation::ArtifactFloor do
  describe ".bills_text_floor" do
    let(:sway_locale) { create(:sway_locale) }

    it "counts a bill whose extracted text is stored" do
      create(:bill, sway_locale: sway_locale, extracted_text: "The text of the bill.")

      expect(described_class.bills_text_floor).to eq(1)
    end

    it "does not count a bill with no extracted text" do
      create(:bill, sway_locale: sway_locale, extracted_text: nil)

      expect(described_class.bills_text_floor).to eq(0)
    end

    it "does not count a bill whose extracted text is empty" do
      create(:bill, sway_locale: sway_locale, extracted_text: "")

      expect(described_class.bills_text_floor).to eq(0)
    end

    it "is zero on a database holding no bills at all" do
      expect(described_class.bills_text_floor).to eq(0)
    end
  end
end
