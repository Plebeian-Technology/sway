# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scraper::Congress::RollCallIdentity do
  def built(document_name: nil, question: nil, voted_on: nil, title: nil)
    described_class.new(document_name: document_name, question: question, voted_on: voted_on, title: title)
  end

  # @lat: [[congress-roll-calls#Why a fetched record has to name the bill's own vote]]
  describe "the text the record gives" do
    it "keeps no surrounding whitespace" do
      identity = built(document_name: " S. 870 ", question: "On the Motion\n", title: "Motion to Concur\n")

      expect(identity.document_name).to eq("S. 870")
      expect(identity.question).to eq("On the Motion")
      expect(identity.title).to eq("Motion to Concur")
    end

    it "reports the title alongside the rest" do
      expect(built(title: "Motion to Concur").to_h).to include(title: "Motion to Concur")
    end

    it "leaves the title empty when the record has none" do
      expect(built(question: "On Passage").title).to be_nil
    end
  end

  describe "#names?" do
    # Every pair below was read from the live record and from the bill Sway
    # stores for it on 2026-08-12. The two sources never spell it the same way.
    {
      "H R 192" => "hr192",
      "H R 1968" => "hr1968",
      "H R 28" => "hr28",
      "S 5" => "S5",
      "S. 5" => "S5",
      "PN11-7" => "PN11-7",
      "PN11-8" => "PN11-8",
      "H J RES 98" => "hjres98",
      "H RES 1371" => "hres1371"
    }.each do |printed, stored|
      it "reads #{printed.inspect} as the bill stored as #{stored.inspect}" do
        expect(built(document_name: printed).names?(stored)).to be(true)
      end
    end

    it "does not match a different bill" do
      expect(built(document_name: "S. 870").names?("s1111")).to be(false)
    end

    it "refuses when the record names nothing" do
      expect(built(document_name: nil).names?("hr192")).to be(false)
    end

    it "refuses when the bill has no id" do
      expect(built(document_name: "H R 192").names?(nil)).to be(false)
    end

    # The one that needs saying out loud: strip both of punctuation and they
    # are the same empty string, so without the guard two silences agree.
    it "refuses when neither side names anything" do
      expect(built(document_name: nil).names?(nil)).to be(false)
    end
  end

  describe "#taken_on?" do
    # @lat: [[congress-roll-calls#Why a fetched record has to name the bill's own vote]]
    it "accepts a day stored as midnight in Washington" do
      stored = Time.utc(2024, 5, 23, 4, 0, 0).in_time_zone

      expect(built(voted_on: Date.new(2024, 5, 23)).taken_on?(stored)).to be(true)
    end

    it "accepts a day stored as midnight in UTC" do
      stored = Time.utc(2025, 1, 24, 0, 0, 0).in_time_zone

      expect(built(voted_on: Date.new(2025, 1, 24)).taken_on?(stored)).to be(true)
    end

    # The whole point. A roll number paired with the wrong year returns a real
    # record for somebody else's vote, and only the day gives it away.
    it "refuses the same number from a different year" do
      stored = Time.utc(2024, 5, 23, 4, 0, 0).in_time_zone

      expect(built(voted_on: Date.new(2026, 5, 23)).taken_on?(stored)).to be(false)
    end

    # An 8:57 PM vote in Washington is already tomorrow in UTC. Reading the
    # stored time in Washington's zone is what keeps that pairing correct.
    it "accepts an evening vote whose UTC day has already turned over" do
      stored = Time.utc(2025, 1, 25, 1, 57, 0).in_time_zone

      expect(built(voted_on: Date.new(2025, 1, 24)).taken_on?(stored)).to be(true)
    end

    it "refuses when the record states no day" do
      expect(built(voted_on: nil).taken_on?(Time.utc(2024, 5, 23).in_time_zone)).to be(false)
    end

    it "refuses when the bill records no day" do
      expect(built(voted_on: Date.new(2024, 5, 23)).taken_on?(nil)).to be(false)
    end
  end
end
