# frozen_string_literal: true

# @lat: [[scores-and-agreement#Privacy thresholds for aggregates]]
module VoteComparisonPercentageCalculator
  def self.calculate(counters, total_voter_count)
    if total_voter_count < VoteComparisonPrivacy::MINIMUM_VOTERS
      return {agreed: nil, disagreed: nil, abstained: nil, no_vote: nil}
    end

    total = counters.values.sum.to_f
    return {agreed: nil, disagreed: nil, abstained: nil, no_vote: nil} if total == 0

    {
      agreed: (counters[:count_agreed] / total * 100).round,
      disagreed: (counters[:count_disagreed] / total * 100).round,
      abstained: (counters[:count_legislator_abstained] / total * 100).round,
      no_vote: (counters[:count_no_legislator_vote] / total * 100).round
    }
  end
end
