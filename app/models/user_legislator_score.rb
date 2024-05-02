# typed: strict

# == Schema Information
#
# Table name: user_legislator_scores
#
#  id                         :integer          not null, primary key
#  user_legislator_id         :integer          not null
#  count_agreed               :integer          default(0), not null
#  count_disagreed            :integer          default(0), not null
#  count_no_legislator_vote   :integer          default(0), not null
#  count_legislator_abstained :integer          default(0), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#
class UserLegislatorScore < ApplicationRecord
  extend T::Sig
  include ::Scoreable

  belongs_to :user_legislator

  sig { returns(UserLegislator) }
  def user_legislator
    T.cast(super, UserLegislator)
  end

  sig { override.params(user_vote: UserVote).returns(UserLegislatorScore) }
  def update_score(user_vote)
    _update_scores(user_vote, legislator_vote(user_vote))

    save!

    self
  end

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |uls|
      uls.user_legislator_id user_legislator_id
      uls.legislator_id user_legislator.legislator_id
      uls.sway_locale_id user_legislator.legislator.sway_locale&.id
      uls.count_agreed count_agreed
      uls.count_disagreed count_disagreed
      uls.count_no_legislator_vote count_no_legislator_vote
      uls.count_legislator_abstained count_legislator_abstained
    end
  end

  private

  sig { params(user_vote: UserVote, legislator_vote: T.nilable(LegislatorVote)).void }
  def _update_scores(user_vote, legislator_vote)
    if legislator_vote.nil?
      self.count_no_legislator_vote = count_no_legislator_vote + 1

    elsif (user_vote.for? && legislator_vote.for?) || (user_vote.against? && legislator_vote.against?)
      self.count_agreed = count_agreed + 1

    else
      self.count_disagreed = count_disagreed + 1

      # Abstained, Sway users cannot abstain
      self.count_legislator_abstained = count_legislator_abstained + 1 if legislator_vote.abstain?

    end
  end

  sig { params(user_vote: UserVote).returns(T.nilable(LegislatorVote)) }
  def legislator_vote(user_vote)
    user_vote.legislator_votes(legislator)
  end

  sig { returns(Legislator) }
  def legislator
    user_legislator.legislator
  end
end
