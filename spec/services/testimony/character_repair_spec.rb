# frozen_string_literal: true

require "rails_helper"

RSpec.describe Testimony::CharacterRepair do
  describe ".call" do
    it "leaves text with no break character unchanged" do
      result = described_class.call("Do you support this bill?")

      expect(result.text).to eq("Do you support this bill?")
      expect(result.broken_words).to eq(0)
    end

    it "repairs a single break using the pair whose spelling already appears unbroken elsewhere in the text" do
      text = "The Bu\u{FFFD}on on the form was hard to find. Please press the Button again."

      result = described_class.call(text)

      expect(result.text).to eq("The Button on the form was hard to find. Please press the Button again.")
      expect(result.broken_words).to eq(1)
      expect(result.resolved_from_bundle).to eq(1)
    end

    it "repairs a word broken at two different positions by two different letter pairs, not one pair written into both" do
      text = "The plan is e\u{FFFD}ec\u{FFFD}ve and effective work is fine."

      result = described_class.call(text)

      expect(result.text).to eq("The plan is effective and effective work is fine.")
      expect(result.broken_words).to eq(1)
      expect(result.resolved_from_bundle).to eq(1)
      expect(result.resolved_by_fallback).to eq(0)
      expect(result.left_unresolved).to eq(0)
    end

    it "leaves a word unchanged when more than one per-position tuple lands on a spelling that appears elsewhere in the text" do
      text = "The words ctit and cfft appear here. The broken form is c$t among other words."

      result = described_class.call(text)

      expect(result.text).to eq(text)
      expect(result.broken_words).to eq(1)
      expect(result.resolved_from_bundle).to eq(0)
      expect(result.resolved_by_fallback).to eq(0)
      expect(result.left_unresolved).to eq(1)
    end

    it "falls back to FALLBACK_PAIR when every break in the run is U+FFFD and no candidate spelling matches the vocabulary" do
      text = "This word is entirely ma\u{FFFD}e up and matches nothing else in the text."

      result = described_class.call(text)

      expect(result.resolved_by_fallback).to eq(1)
      expect(result.text).to include("matie")
    end

    it "leaves a run unresolved, not guessed, when an unmatched break is the ambiguous \"$\" character" do
      text = "This word is entirely ma$e up and matches nothing else in the text."

      result = described_class.call(text)

      expect(result.text).to eq(text)
      expect(result.left_unresolved).to eq(1)
      expect(result.resolved_by_fallback).to eq(0)
    end

    it "repairs a break extracted as U+019F using the pair whose spelling already appears unbroken elsewhere in the text" do
      text = "I am wri\u{019F}ng in support. Please keep writing to your council."

      result = described_class.call(text)

      expect(result.text).to eq("I am writing in support. Please keep writing to your council.")
      expect(result.broken_words).to eq(1)
      expect(result.resolved_from_bundle).to eq(1)
    end

    it "leaves a run unresolved, not guessed, when an unmatched break is the ambiguous U+019F character" do
      text = "This word is entirely ma\u{019F}e up and matches nothing else in the text."

      result = described_class.call(text)

      expect(result.text).to eq(text)
      expect(result.left_unresolved).to eq(1)
      expect(result.resolved_by_fallback).to eq(0)
    end

    it "repairs a break extracted as \"?\" using the pair whose spelling already appears unbroken elsewhere in the text" do
      text = "I am wri?ng in support. Please keep writing to your council."

      result = described_class.call(text)

      expect(result.text).to eq("I am writing in support. Please keep writing to your council.")
      expect(result.broken_words).to eq(1)
      expect(result.resolved_from_bundle).to eq(1)
    end

    it "repairs a break extracted as a backslash using the pair already unbroken elsewhere in the text" do
      text = "The commi\\ee met today. The committee will meet again."

      result = described_class.call(text)

      expect(result.text).to eq("The committee met today. The committee will meet again.")
      expect(result.broken_words).to eq(1)
      expect(result.resolved_from_bundle).to eq(1)
    end

    # A sentence running straight into the next with no space is the shape a
    # real "?" takes between two letters, and it must survive untouched.
    it "leaves a sentence-joining \"?\" exactly as it arrived rather than guessing a pair into it" do
      text = "Do you support this?The council wants to know."

      result = described_class.call(text)

      expect(result.text).to eq(text)
      expect(result.left_unresolved).to eq(1)
      expect(result.resolved_by_fallback).to eq(0)
    end

    it "falls back to substituting the same pair at every position when a run has more reparable breaks than the per-position cap" do
      text = "a\u{FFFD}b\u{FFFD}c\u{FFFD}d\u{FFFD}e is a made-up word."

      result = described_class.call(text)

      expect(result.broken_words).to eq(1)
      expect(result.resolved_by_fallback).to eq(1)
      expect(result.text).to eq("atibtictidtie is a made-up word.")
    end

    it "does not touch a break character sitting at the edge of a run or beside another break character" do
      text = "Do you support this\u{FFFD}? And what about $ this?"

      result = described_class.call(text)

      expect(result.text).to eq(text)
      expect(result.broken_words).to eq(0)
    end
  end
end
