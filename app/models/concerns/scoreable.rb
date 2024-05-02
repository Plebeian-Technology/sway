# typed: strict

module Scoreable
  extend T::Sig
  extend T::Helpers
  interface! # https://sorbet.org/docs/abstract#creating-an-abstract-method

  sig { abstract.params(user_vote: UserVote).returns(Scoreable) }
  def update_score(user_vote); end
end
