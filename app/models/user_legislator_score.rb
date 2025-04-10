# frozen_string_literal: true
# typed: strict

# == Schema Information
#
# Table name: user_legislator_scores
#
#  id                         :integer          not null, primary key
#  count_agreed               :integer          default(0), not null
#  count_disagreed            :integer          default(0), not null
#  count_legislator_abstained :integer          default(0), not null
#  count_no_legislator_vote   :integer          default(0), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  user_legislator_id         :integer          not null
#
# Indexes
#
#  index_user_legislator_scores_on_user_legislator_id  (user_legislator_id)
#
# Foreign Keys
#
#  user_legislator_id  (user_legislator_id => user_legislators.id)
#
class UserLegislatorScore < ApplicationRecord
  extend T::Sig
  include Agreeable
  include Scoreable

  belongs_to :user_legislator

  sig { returns(UserLegislator) }
  def user_legislator
    T.cast(super, UserLegislator)
  end

  sig { params(user_vote: UserVote).returns(UserLegislatorScore) }
  def update_score(user_vote)
    update_agreeable_score(user_vote, legislator_vote(user_vote))
    save!
    self
  end

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |uls|
      # How user compares to Legislator
      uls.user_legislator_id user_legislator_id
      uls.legislator_id user_legislator.legislator_id
      uls.sway_locale_id user_legislator.legislator.sway_locale.id
      uls.count_agreed count_agreed
      uls.count_disagreed count_disagreed
      uls.count_no_legislator_vote count_no_legislator_vote
      uls.count_legislator_abstained count_legislator_abstained

      # How User's district compares to Legislator
      uls.legislator_district_score legislator.legislator_district_score.to_sway_json
    end
  end

  sig { returns(T::Boolean) }
  def empty?
    count_agreed == 0 && count_disagreed == 0 && count_legislator_abstained == 0 && count_no_legislator_vote == 0
  end

  private

  sig { override.params(user_vote: UserVote).returns(T.nilable(LegislatorVote)) }
  def legislator_vote(user_vote)
    legislator.vote(user_vote.bill)
  end

  sig { returns(Legislator) }
  def legislator
    user_legislator.legislator
  end
end
