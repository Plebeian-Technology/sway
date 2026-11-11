# frozen_string_literal: true

require "rails_helper"

# The prompt for the model pass over the letters
# Testimony::SourceKindRules left in its tail.
RSpec.describe Testimony::SourceKindPromptBuilder do
  let(:candidates) do
    [
      {position: 0, text: "Jane Doe\nExecutive Director of the Baltimore Housing Coalition\n"},
      {position: 3, text: "On behalf of the Fells Point Merchants Association, we support this bill.\n"}
    ]
  end

  describe "#system_prompt" do
    # WR-03. Testimony::SourceKindClassifier sends a letter to the model only
    # when the rules DID match a pattern for one of the two kinds; letters the
    # rules could not place fall to person_speaking_for_self and are never
    # sent. The header told the model the opposite, and because an omitted
    # letter falls back to person_speaking_for_self, a model acting on that
    # false premise throws away the rules' correct verdict.
    it "does not tell the model the letters failed to match a pattern" do
      prompt = described_class.new(candidates).system_prompt

      expect(prompt).not_to include("already failed to match")
      expect(prompt).not_to include("tiebreaker")
    end

    it "tells the model these letters matched a pattern for one of the two kinds" do
      prompt = described_class.new(candidates).system_prompt

      expect(prompt).to include("matched a pattern")
    end

    it "names exactly the kinds the classifier will accept back" do
      prompt = described_class.new(candidates).system_prompt

      Testimony::SourceKindClassifier::MODEL_PASS_KINDS.each do |kind|
        expect(prompt).to include(kind.to_s)
      end
      expect(prompt).not_to include("person_speaking_for_self")
    end
  end

  describe "#user_message" do
    it "numbers each letter by its own position, never by its place in the batch" do
      message = described_class.new(candidates).user_message

      expect(message).to include("0. TEXT:")
      expect(message).to include("3. TEXT:")
    end

    it "cuts a pathologically long letter and says so" do
      long = [{position: 0, text: "z" * (described_class::MAX_LETTER_CHARS + 500)}]

      message = described_class.new(long).user_message

      expect(message).to include(described_class::TEXT_TRUNCATION_NOTICE)
    end
  end
end
