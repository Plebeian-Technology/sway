# frozen_string_literal: true
# typed: strict

module Supportable
    extend T::Sig
    extend T::Helpers
    interface! # https://sorbet.org/docs/abstract#creating-an-abstract-method

    sig { abstract.params(user_vote: UserVote).returns(Supportable) }
    def update_score(user_vote)
    end

    sig { abstract.returns(Integer) }
    def for
    end

    sig { abstract.returns(Integer) }
    def against
    end

    sig { abstract.params(value: Integer).void }
    def for=(value)
    end

    sig { abstract.params(value: Integer).void }
    def against=(value)
    end
end
