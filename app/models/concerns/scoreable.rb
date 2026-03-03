# frozen_string_literal: true

module Scoreable
  def update_supportable_score(user_vote)
    self.for = self.for.to_i + 1 if user_vote.for?
    self.against = against.to_i + 1 if user_vote.against?
  end

  def update_agreeable_score(user_vote, legislator_vote)
    if legislator_vote.nil?
      self.count_no_legislator_vote = count_no_legislator_vote.to_i + 1
    elsif (user_vote.for? && legislator_vote.for?) ||
          (user_vote.against? && legislator_vote.against?)
      self.count_agreed = count_agreed.to_i + 1
    else
      self.count_disagreed = count_disagreed.to_i + 1

      # Abstained, Sway users cannot abstain
      self.count_legislator_abstained =
        count_legislator_abstained.to_i + 1 if legislator_vote.abstain?
    end
  end
end
