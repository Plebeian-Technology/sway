# frozen_string_literal: true
# typed: strict

module Scoreable
    extend T::Sig

    sig { params(user_vote: UserVote).void }
    def update_supportable_score(user_vote)
        T.cast(self, Supportable).for = (T.cast(self, Supportable).for + 1) if user_vote.for?
        T.cast(self, Supportable).against = (T.cast(self, Supportable).against + 1) if user_vote.against?
    end

    sig { params(user_vote: UserVote, legislator_vote: T.nilable(LegislatorVote)).void }
    def update_agreeable_score(user_vote, legislator_vote)
        if legislator_vote.nil?
            T.cast(self, Agreeable).count_no_legislator_vote = T.cast(self, Agreeable).count_no_legislator_vote + 1
        elsif (user_vote.for? && legislator_vote.for?) || (user_vote.against? && legislator_vote.against?)
            T.cast(self, Agreeable).count_agreed = T.cast(self, Agreeable).count_agreed + 1
        else
            T.cast(self, Agreeable).count_disagreed = T.cast(self, Agreeable).count_disagreed + 1

            # Abstained, Sway users cannot abstain
            if legislator_vote.abstain?
                T.cast(self, Agreeable).count_legislator_abstained = T.cast(self, Agreeable).count_legislator_abstained + 1
            end
        end
    end
end
