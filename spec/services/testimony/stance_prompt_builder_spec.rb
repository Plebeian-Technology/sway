# frozen_string_literal: true

require "rails_helper"

RSpec.describe Testimony::StancePromptBuilder do
  let(:candidates) do
    [
      {position: 0, text: "I urge a favorable report on this bill to protect our neighborhood parks.\n"},
      {position: 3, text: "We strongly oppose this legislation as it imposes an unfair tax burden.\n"}
    ]
  end

  let(:bill) do
    instance_double(
      Bill,
      external_id: "SB-100",
      title: "Clean Water and Parks Protection Act",
      summary: "An act to establish funding for municipal park infrastructure."
    )
  end

  describe "#system_prompt" do
    it "includes boundary instruction for untrusted testimony letters" do
      prompt = described_class.new(letters: candidates).system_prompt

      expect(prompt).to include("The letter text")
      expect(prompt).to include("submitted material from members of the public")
    end

    it "defines support, oppose, and neutral stances" do
      prompt = described_class.new(letters: candidates).system_prompt

      expect(prompt).to include('"support"')
      expect(prompt).to include("urges passage, favorable report, or vote for the bill")
      expect(prompt).to include('"oppose"')
      expect(prompt).to include("urges rejection, unfavorable report, or vote against the bill")
      expect(prompt).to include('"neutral"')
      expect(prompt).to include("informational testimony")
    end

    it "specifies the required output schema structure with position and stance" do
      prompt = described_class.new(letters: candidates).system_prompt

      expect(prompt).to include('"classifications"')
      expect(prompt).to include('"position"')
      expect(prompt).to include('"stance"')
    end
  end

  describe "#user_message" do
    it "numbers each letter by its own position" do
      message = described_class.new(letters: candidates).user_message

      expect(message).to include("0. TEXT:")
      expect(message).to include("3. TEXT:")
    end

    it "truncates letters longer than MAX_LETTER_CHARS and appends notice" do
      long = [{position: 0, text: "a" * (described_class::MAX_LETTER_CHARS + 500)}]

      message = described_class.new(letters: long).user_message

      expect(message).to include(described_class::TEXT_TRUNCATION_NOTICE)
    end

    it "omits the bill header when bill is nil" do
      message = described_class.new(letters: candidates, bill: nil).user_message

      expect(message).not_to include("## Bill")
      expect(message).to include("## Letters")
    end

    it "includes sanitized Bill external_id, title, and summary when bill is provided" do
      message = described_class.new(letters: candidates, bill: bill).user_message

      expect(message).to include("## Bill")
      expect(message).to include("SB-100")
      expect(message).to include("Clean Water and Parks Protection Act")
      expect(message).to include("An act to establish funding for municipal park infrastructure.")
      expect(message).to include("## Letters")
    end

    it "wraps letters in the testimony untrusted text block delimiter" do
      message = described_class.new(letters: candidates).user_message

      expect(message).to include(described_class::DELIMITER_PREFIX)
    end

    it "omits the Summary line when bill.summary is the pending placeholder" do
      pending_bill = instance_double(
        Bill,
        external_id: "SB-101",
        title: "Pending Bill",
        summary: Bill::SUMMARY_PLACEHOLDER
      )
      message = described_class.new(letters: candidates, bill: pending_bill).user_message

      expect(message).to include("## Bill")
      expect(message).to include("SB-101")
      expect(message).not_to include(Bill::SUMMARY_PLACEHOLDER)
    end
  end
end
