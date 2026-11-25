# frozen_string_literal: true

require "rails_helper"

RSpec.describe VoteComparisonPrivacy do
  describe ".unanimous?" do
    it "is true when one side has every vote" do
      expect(described_class.unanimous?(10, 0)).to be true
      expect(described_class.unanimous?(0, 10)).to be true
    end

    it "is false when nobody voted" do
      expect(described_class.unanimous?(0, 0)).to be false
    end

    it "is false when both sides have a vote" do
      expect(described_class.unanimous?(9, 1)).to be false
    end
  end

  describe ".withheld?" do
    it "is true under ten voters, even when the split is mixed" do
      expect(described_class.withheld?(9, 0)).to be true
      expect(described_class.withheld?(5, 4)).to be true
    end

    it "is true for a unanimous split of ten or more voters" do
      expect(described_class.withheld?(10, 0)).to be true
      expect(described_class.withheld?(0, 10)).to be true
    end

    it "is false for a mixed split of ten or more voters" do
      expect(described_class.withheld?(9, 1)).to be false
      expect(described_class.withheld?(9, 2)).to be false
    end
  end

  describe ".rounded_percentages" do
    def rounded(counts, voters)
      described_class.rounded_percentages(counts, voters: voters)
    end

    it "rounds to tens under 20 voters" do
      expect(rounded({for: 7, against: 3}, 10)).to eq({for: 70, against: 30})
      expect(rounded({for: 13, against: 6}, 19)).to eq({for: 70, against: 30})
      expect(rounded({for: 9, against: 1}, 10)).to eq({for: 90, against: 10})
    end

    it "rounds to fives from 20 voters up" do
      expect(rounded({for: 19, against: 1}, 20)).to eq({for: 95, against: 5})
      expect(rounded({for: 11, against: 9}, 20)).to eq({for: 55, against: 45})
    end

    it "never shows 100 and 0 for a split that is not unanimous" do
      expect(rounded({for: 39, against: 1}, 40)).to eq({for: 95, against: 5})
    end

    it "gives a tied leftover step to the first key" do
      expect(rounded({for: 21, against: 19}, 40)).to eq({for: 55, against: 45})
    end

    it "handles four keys, one of them empty" do
      counts = {agreed: 6, disagreed: 3, no_legislator_vote: 1, abstained: 0}
      expect(rounded(counts, 10)).to eq({agreed: 60, disagreed: 30, no_legislator_vote: 10, abstained: 0})
    end

    it "takes a step from the largest key for each non-zero key that rounded to zero" do
      counts = {a: 97, b: 1, c: 1, d: 1}
      expect(rounded(counts, 100)).to eq({a: 85, b: 5, c: 5, d: 5})
    end

    it "keeps the key order of the input" do
      expect(rounded({against: 3, for: 7}, 10).keys).to eq(%i[against for])
    end

    it "always sums to 100" do
      expect(rounded({a: 1, b: 1, c: 1}, 12).values.sum).to eq(100)
    end

    it "returns nil when every count is zero" do
      expect(rounded({for: 0, against: 0}, 0)).to be_nil
    end
  end
end
