# frozen_string_literal: true

require "rails_helper"

# Unit tests for the text cleaner itself. Tests for how the three callers behave
# live next to those callers (testimony_text_extractor, fetch_hearings_service,
# bill_positions_prompt_builder).
RSpec.describe Sway::Utf8 do
  describe ".scrub" do
    it "replaces an invalid byte sequence and keeps everything legible around it" do
      invalid = (+"ACME Coalition supports \xC3\x28 the bill.").force_encoding(Encoding::UTF_8)
      expect(invalid.valid_encoding?).to be(false)

      result = described_class.scrub(invalid)

      expect(result.valid_encoding?).to be(true)
      expect(result).to include("ACME Coalition supports")
      expect(result).to include("the bill.")
      expect(result).to include(described_class::REPLACEMENT)
    end

    it "leaves valid multibyte text byte-identical" do
      valid = "Señora Núñez — testimonio “completo”."

      expect(described_class.scrub(valid)).to eq(valid)
    end

    it "retags a binary-encoded string as UTF-8" do
      binary = (+"Plain testimony body.").force_encoding(Encoding::ASCII_8BIT)

      result = described_class.scrub(binary)

      expect(result.encoding).to eq(Encoding::UTF_8)
      expect(result).to eq("Plain testimony body.")
    end

    it "returns an empty string for nil" do
      expect(described_class.scrub(nil)).to eq("")
    end

    it "does not mutate its argument" do
      invalid = (+"before \xC3\x28 after").force_encoding(Encoding::UTF_8)

      described_class.scrub(invalid)

      expect(invalid.valid_encoding?).to be(false)
    end

    it "leaves a frozen valid string usable without raising" do
      expect { described_class.scrub("frozen literal") }.not_to raise_error
    end

    it "makes the scrubbed result safe for the regexp operations that were raising" do
      invalid = (+"fence ``` here \xC3\x28 and \xE2\x28\xA1 there").force_encoding(Encoding::UTF_8)

      result = described_class.scrub(invalid)

      expect { result.gsub(/`{3,}/, "'''") }.not_to raise_error
      expect { result.strip }.not_to raise_error
      expect(result.blank?).to be(false)
    end
  end
end
