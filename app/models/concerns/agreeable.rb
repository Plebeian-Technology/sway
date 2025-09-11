# frozen_string_literal: true
# typed: strict

module Agreeable
  extend T::Sig
  extend T::Helpers
  interface!

  sig { abstract.returns(Integer) }
  def count_no_legislator_vote
  end

  sig { abstract.returns(Integer) }
  def count_agreed
  end

  sig { abstract.returns(Integer) }
  def count_disagreed
  end

  sig { abstract.returns(Integer) }
  def count_legislator_abstained
  end

  sig { abstract.params(value: Integer).void }
  def count_no_legislator_vote=(value)
  end

  sig { abstract.params(value: Integer).void }
  def count_agreed=(value)
  end

  sig { abstract.params(value: Integer).void }
  def count_disagreed=(value)
  end

  sig { abstract.params(value: Integer).void }
  def count_legislator_abstained=(value)
  end

  sig do
    abstract.params(user_vote: UserVote).returns(T.nilable(LegislatorVote))
  end
  def legislator_vote(user_vote)
  end
end
