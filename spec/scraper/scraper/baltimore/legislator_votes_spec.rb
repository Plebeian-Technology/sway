# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scraper::Baltimore::LegislatorVotes do
  describe "#process" do
    it "maps Yea → FOR" do
      result = described_class.new(raw_votes: [
        {"VotePersonId" => 1, "VotePersonName" => "Nick Mosby", "VoteValueName" => "Yea"}
      ]).process
      expect(result.size).to eq(1)
      expect(result.first.support).to eq("FOR")
      expect(result.first.external_id).to eq("1")
      expect(result.first.last_name).to eq("Nick Mosby")
      expect(result.first.first_name).to eq("")
      expect(result.first.party).to eq("")
      expect(result.first.state_code).to eq("MD")
    end

    it "maps Yes → FOR" do
      result = described_class.new(raw_votes: [
        {"VotePersonId" => 1, "VotePersonName" => "X", "VoteValueName" => "Yes"}
      ]).process
      expect(result.first.support).to eq("FOR")
    end

    it "maps Aye → FOR" do
      result = described_class.new(raw_votes: [
        {"VotePersonId" => 1, "VotePersonName" => "X", "VoteValueName" => "Aye"}
      ]).process
      expect(result.first.support).to eq("FOR")
    end

    it "maps Nay → AGAINST" do
      result = described_class.new(raw_votes: [
        {"VotePersonId" => 2, "VotePersonName" => "X", "VoteValueName" => "Nay"}
      ]).process
      expect(result.first.support).to eq("AGAINST")
    end

    it "maps No → AGAINST" do
      result = described_class.new(raw_votes: [
        {"VotePersonId" => 2, "VotePersonName" => "X", "VoteValueName" => "No"}
      ]).process
      expect(result.first.support).to eq("AGAINST")
    end

    %w[Abstain Absent Excused Present Recused Other].each do |dropped|
      it "drops #{dropped} votes" do
        result = described_class.new(raw_votes: [
          {"VotePersonId" => 3, "VotePersonName" => "X", "VoteValueName" => dropped}
        ]).process
        expect(result).to be_empty
      end
    end

    it "is case-insensitive on VoteValueName" do
      %w[YEA yea Yea YeA].each do |variant|
        result = described_class.new(raw_votes: [
          {"VotePersonId" => 1, "VotePersonName" => "X", "VoteValueName" => variant}
        ]).process
        expect(result.first&.support).to eq("FOR"), "expected #{variant.inspect} → FOR"
      end
    end

    it "handles nil/empty input gracefully" do
      expect(described_class.new(raw_votes: nil).process).to eq([])
      expect(described_class.new(raw_votes: []).process).to eq([])
    end

    it "drops a mixed batch's abstain rows but keeps Yea + Nay" do
      result = described_class.new(raw_votes: [
        {"VotePersonId" => 1, "VotePersonName" => "A", "VoteValueName" => "Yea"},
        {"VotePersonId" => 2, "VotePersonName" => "B", "VoteValueName" => "Nay"},
        {"VotePersonId" => 3, "VotePersonName" => "C", "VoteValueName" => "Abstain"}
      ]).process
      expect(result.size).to eq(2)
      expect(result.map(&:support)).to contain_exactly("FOR", "AGAINST")
    end

    it "returns Array<Scraper::LegislatorVote> (contract)" do
      result = described_class.new(raw_votes: [
        {"VotePersonId" => 1, "VotePersonName" => "Nick Mosby", "VoteValueName" => "Yea"},
        {"VotePersonId" => 2, "VotePersonName" => "Odette Ramos", "VoteValueName" => "Nay"}
      ]).process
      expect(result).to all(be_a(Scraper::LegislatorVote))
    end
  end
end
