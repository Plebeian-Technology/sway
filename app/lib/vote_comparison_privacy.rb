# frozen_string_literal: true

module VoteComparisonPrivacy
  MINIMUM_VOTERS = 10

  def self.suppressed?(for_count, against_count)
    (for_count + against_count) < MINIMUM_VOTERS
  end

  def self.voters_needed(for_count, against_count)
    [0, MINIMUM_VOTERS - (for_count + against_count)].max
  end
end
