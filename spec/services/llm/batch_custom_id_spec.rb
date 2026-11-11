# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::BatchCustomId do
  describe ".build" do
    it "joins legal parts with a double underscore and leaves them otherwise unchanged" do
      expect(described_class.build("25-0064", "positions")).to eq("25-0064__positions")
    end

    it "replaces an illegal character (a slash) with a single dash" do
      expect(described_class.build("25-0064/positions")).to eq("25-0064-positions")
    end

    it "collapses a run of several illegal characters in a row into ONE dash" do
      expect(described_class.build("a///b")).to eq("a-b")
      expect(described_class.build("a ?! b")).to eq("a-b")
    end

    it "always produces a string matching PATTERN" do
      ids = [
        described_class.build("25-0064", "positions"),
        described_class.build("weird/id with spaces!!"),
        described_class.build("x" * 200),
        described_class.build("a", "b", "c")
      ]
      expect(ids).to all(match(described_class::PATTERN))
    end

    it "truncates output longer than 64 characters down to 64 or fewer" do
      long_id = described_class.build("x" * 200)
      expect(long_id.length).to be <= 64
    end

    it "keeps two long inputs that share their first 55 characters unique after truncation" do
      shared_prefix = "y" * 55
      id_one = described_class.build("#{shared_prefix}-AAAA")
      id_two = described_class.build("#{shared_prefix}-BBBB")
      expect(id_one).not_to eq(id_two)
    end
  end

  describe ".valid?" do
    it "accepts a legal id" do
      expect(described_class.valid?("25-0064__positions")).to be(true)
    end

    it "rejects an id containing a slash" do
      expect(described_class.valid?("25-0064/positions")).to be(false)
    end

    it "rejects an empty id" do
      expect(described_class.valid?("")).to be(false)
    end

    it "rejects an id 65 characters long" do
      expect(described_class.valid?("a" * 65)).to be(false)
    end
  end
end
