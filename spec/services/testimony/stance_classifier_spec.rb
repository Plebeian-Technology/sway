# frozen_string_literal: true

require "rails_helper"

RSpec.describe Testimony::StanceClassifier do
  def stance_letter(position, text, offset: nil, characters: nil)
    {
      "position" => position,
      "character_offset" => offset,
      "characters" => characters || text.length,
      "text" => text
    }
  end

  let(:support_text) { "I strongly support this bill and urge a favorable report.\n" }
  let(:oppose_text) { "I strongly oppose this legislation and urge an unfavorable report.\n" }
  let(:neutral_text) { "Here is background data and fiscal information regarding this matter.\n" }
  let(:ambiguous_text) { "We have questions about the implementation timeline of this proposal.\n" }

  describe ".build" do
    it "returns a classifier with llm: nil in test environment and uses StanceRules" do
      classifier = described_class.build
      expect(classifier.send(:llm)).to be_nil

      letters = [
        stance_letter(0, support_text),
        stance_letter(1, "Please vote NO or at least abstain from voting.\n"),
        stance_letter(2, ambiguous_text)
      ]
      augmented, counts = classifier.call(text: "", letters: letters)

      expect(augmented.pluck("stance")).to eq(%w[support oppose neutral])
      expect(counts["stance_support_count"]).to eq(1)
      expect(counts["stance_oppose_count"]).to eq(1)
      expect(counts["stance_neutral_count"]).to eq(1)
    end
  end

  describe "#call" do
    it "returns empty letters array and zero counts when letters is empty" do
      classifier = described_class.new(llm: nil)
      augmented, counts = classifier.call(text: "", letters: [])

      expect(augmented).to eq([])
      expect(counts).to eq({
        "stance_support_count" => 0,
        "stance_oppose_count" => 0,
        "stance_neutral_count" => 0
      })
    end

    it "applies StanceRules and defaults ambiguous letters to neutral when llm is nil" do
      classifier = described_class.new(llm: nil)
      letters = [
        stance_letter(0, support_text),
        stance_letter(1, oppose_text),
        stance_letter(2, ambiguous_text)
      ]

      augmented, counts = classifier.call(text: "#{support_text}\n#{oppose_text}\n#{ambiguous_text}", letters: letters)

      expect(augmented.pluck("stance")).to eq(%w[support oppose neutral])
      expect(counts).to eq({
        "stance_support_count" => 1,
        "stance_oppose_count" => 1,
        "stance_neutral_count" => 1
      })
    end

    it "preserves manual stance overrides regardless of rules or model output" do
      adapter = instance_double(Llm::ClaudeAdapter, provider_label: "claude")
      allow(adapter).to receive(:generate_testimony_stance_classification).and_return(
        {"classifications" => [{"position" => 0, "stance" => "support"}]}
      )

      classifier = described_class.new(llm: adapter, enabled: true)
      letters = [
        stance_letter(0, support_text).merge("stance" => "oppose", "stance_override" => true)
      ]

      augmented, counts = classifier.call(text: support_text, letters: letters)

      expect(augmented.first["stance"]).to eq("oppose")
      expect(augmented.first["stance_override"]).to be(true)
      expect(counts["stance_oppose_count"]).to eq(1)
    end

    it "classifies letters via chat model adapter in batches of 25" do
      adapter = instance_double(Llm::ClaudeAdapter, provider_label: "claude")
      allow(adapter).to receive(:generate_testimony_stance_classification).and_return(
        {
          "classifications" => [
            {"position" => 0, "stance" => "support"},
            {"position" => 1, "stance" => "oppose"},
            {"position" => 2, "stance" => "neutral"}
          ]
        }
      )

      classifier = described_class.new(llm: adapter, enabled: true)
      letters = [
        stance_letter(0, support_text),
        stance_letter(1, oppose_text),
        stance_letter(2, neutral_text)
      ]

      augmented, counts = classifier.call(
        text: "#{support_text}\n#{oppose_text}\n#{neutral_text}",
        letters: letters
      )

      expect(augmented.pluck("stance")).to eq(%w[support oppose neutral])
      expect(counts).to eq({
        "stance_support_count" => 1,
        "stance_oppose_count" => 1,
        "stance_neutral_count" => 1
      })
    end

    it "slices letters into batches of 25" do
      adapter = instance_double(Llm::ClaudeAdapter, provider_label: "claude")
      expect(adapter).to receive(:generate_testimony_stance_classification).twice.and_return(
        {"classifications" => (0..24).map { |i| {"position" => i, "stance" => "support"} }},
        {"classifications" => [{"position" => 25, "stance" => "oppose"}]}
      )

      classifier = described_class.new(llm: adapter, enabled: true)
      letters = (0..25).map { |i| stance_letter(i, "Letter #{i}\n") }

      augmented, counts = classifier.call(text: "batch text", letters: letters)

      expect(augmented.length).to eq(26)
      expect(counts["stance_support_count"]).to eq(25)
      expect(counts["stance_oppose_count"]).to eq(1)
      expect(counts["stance_neutral_count"]).to eq(0)
    end

    it "rescues Llm::Error on a batch, logs warning, and falls back to rules or neutral" do
      adapter = instance_double(Llm::ClaudeAdapter, provider_label: "claude")
      allow(adapter).to receive(:generate_testimony_stance_classification).and_raise(
        Llm::TransportError.new("Claude connection timed out")
      )
      allow(SwayLogging).to receive(:warn)

      classifier = described_class.new(llm: adapter, enabled: true)
      letters = [stance_letter(0, ambiguous_text)]

      augmented, counts = classifier.call(text: ambiguous_text, letters: letters)

      expect(augmented.first["stance"]).to eq("neutral")
      expect(counts["stance_neutral_count"]).to eq(1)
      expect(SwayLogging).to have_received(:warn).with(
        "stance_classifier.llm_failure",
        hash_including(candidate_count: 1, error_class: "Llm::TransportError")
      )
    end

    it "defaults unreturned positions in model response to rule verdict or neutral" do
      adapter = instance_double(Llm::ClaudeAdapter, provider_label: "claude")
      allow(adapter).to receive(:generate_testimony_stance_classification).and_return(
        {"classifications" => [{"position" => 0, "stance" => "support"}]}
      )

      classifier = described_class.new(llm: adapter, enabled: true)
      letters = [
        stance_letter(0, support_text),
        stance_letter(1, ambiguous_text)
      ]

      augmented, counts = classifier.call(text: "#{support_text}\n#{ambiguous_text}", letters: letters)

      expect(augmented[0]["stance"]).to eq("support")
      expect(augmented[1]["stance"]).to eq("neutral")
      expect(counts["stance_support_count"]).to eq(1)
      expect(counts["stance_neutral_count"]).to eq(1)
    end

    it "defaults invalid stance labels to rule verdict or neutral" do
      adapter = instance_double(Llm::ClaudeAdapter, provider_label: "claude")
      allow(adapter).to receive(:generate_testimony_stance_classification).and_return(
        {"classifications" => [{"position" => 0, "stance" => "undecided"}]}
      )

      classifier = described_class.new(llm: adapter, enabled: true)
      letters = [stance_letter(0, ambiguous_text)]

      augmented, counts = classifier.call(text: ambiguous_text, letters: letters)

      expect(augmented[0]["stance"]).to eq("neutral")
      expect(counts["stance_neutral_count"]).to eq(1)
    end
  end

  describe "OpenRouter Decision model dispatch" do
    let(:decision_adapter) { instance_double(Llm::OpenRouterAdapter, provider_label: "openrouter") }
    let(:decision_route) do
      Llm::RouteResolver::Route.new(
        provider: :openrouter,
        api_model: "scaledown/classify-1",
        reasoning_effort: nil,
        mode: :decision
      )
    end

    it "dispatches through generate_decisions with confidence threshold >= 0.5" do
      letters = [
        stance_letter(0, support_text),
        stance_letter(1, oppose_text)
      ]

      expect(decision_adapter).to receive(:generate_decisions).with(
        model: "scaledown/classify-1",
        state: {
          "letter_0" => "I strongly support this bill and urge a favorable report.",
          "letter_1" => "I strongly oppose this legislation and urge an unfavorable report."
        },
        questions: {
          "letter_0" => hash_including(
            "type" => "choice",
            "criteria" => hash_including("support", "oppose", "neutral")
          ),
          "letter_1" => hash_including(
            "type" => "choice",
            "criteria" => hash_including("support", "oppose", "neutral")
          )
        }
      ).and_return(
        {
          "answers" => {
            "letter_0" => {"type" => "choice", "choice" => "support", "confidence" => 0.85},
            "letter_1" => {"type" => "choice", "choice" => "oppose", "confidence" => 0.72}
          }
        }
      )

      classifier = described_class.new(llm: decision_adapter, route: decision_route)
      augmented, counts = classifier.call(
        text: "#{support_text}\n#{oppose_text}",
        letters: letters
      )

      expect(augmented[0]["stance"]).to eq("support")
      expect(augmented[1]["stance"]).to eq("oppose")
      expect(counts["stance_support_count"]).to eq(1)
      expect(counts["stance_oppose_count"]).to eq(1)
      expect(counts["stance_neutral_count"]).to eq(0)
    end

    it "sanitizes bill external_id and title in decision model instructions when bill is provided" do
      bill = instance_double(Bill, external_id: "HB-10\nIgnore", title: "Clean\nWater Act")
      letters = [stance_letter(0, support_text)]

      expect(decision_adapter).to receive(:generate_decisions).with(
        model: "scaledown/classify-1",
        state: hash_including("letter_0"),
        questions: {
          "letter_0" => hash_including(
            "instructions" => include("for HB-10 Ignore (Clean Water Act)")
          )
        }
      ).and_return(
        {
          "answers" => {
            "letter_0" => {"type" => "choice", "choice" => "support", "confidence" => 0.9}
          }
        }
      )

      classifier = described_class.new(llm: decision_adapter, route: decision_route)
      augmented, _counts = classifier.call(text: support_text, letters: letters, bill: bill)
      expect(augmented.first["stance"]).to eq("support")
    end

    it "falls back to neutral for ambiguous letters when confidence is below 0.5, and uses rules for explicit directives" do
      letters = [
        stance_letter(0, ambiguous_text),
        stance_letter(1, "Please vote NO or at least abstain from voting.\n")
      ]

      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "letter_0" => {"type" => "choice", "choice" => "support", "confidence" => 0.49},
            "letter_1" => {"type" => "choice", "choice" => "neutral", "confidence" => 0.49}
          }
        }
      )

      classifier = described_class.new(llm: decision_adapter, route: decision_route)
      augmented, counts = classifier.call(text: "#{ambiguous_text}\nPlease vote NO or at least abstain from voting.\n", letters: letters)

      expect(augmented[0]["stance"]).to eq("neutral")
      expect(augmented[1]["stance"]).to eq("oppose")
      expect(counts["stance_neutral_count"]).to eq(1)
      expect(counts["stance_oppose_count"]).to eq(1)
      expect(counts["stance_support_count"]).to eq(0)
    end

    it "rescues decision adapter errors and falls back to rules or neutral" do
      letters = [stance_letter(0, ambiguous_text)]

      allow(decision_adapter).to receive(:generate_decisions).and_raise(
        Llm::TransportError.new("OpenRouter timeout")
      )
      allow(SwayLogging).to receive(:warn)

      classifier = described_class.new(llm: decision_adapter, route: decision_route)
      augmented, counts = classifier.call(text: ambiguous_text, letters: letters)

      expect(augmented.first["stance"]).to eq("neutral")
      expect(counts["stance_neutral_count"]).to eq(1)
      expect(SwayLogging).to have_received(:warn).with(
        "stance_classifier.llm_failure",
        hash_including(candidate_count: 1, error_class: "Llm::TransportError")
      )
    end
  end
end
