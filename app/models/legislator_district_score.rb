# frozen_string_literal: true

# == Schema Information
#
# Table name: legislator_district_scores
#
#  id                         :integer          not null, primary key
#  count_agreed               :integer          default(0), not null
#  count_disagreed            :integer          default(0), not null
#  count_legislator_abstained :integer          default(0), not null
#  count_no_legislator_vote   :integer          default(0), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  legislator_id              :integer          not null
#
# Indexes
#
#  index_legislator_district_scores_on_legislator_id  (legislator_id)
#
# Foreign Keys
#
#  legislator_id  (legislator_id => legislators.id)
#
# typed: true

# Scores calculated for a Legislator in a Distict
# This may seem repetetive since Legislators have 1-1 relationships with Districts
# However, if/when a Legislator changes districts, either through re-districting or election to a new position
# the district attribute will prove to be useful in order to distinguish between
# the Legislator's new district and old district
class LegislatorDistrictScore < ApplicationRecord
  extend T::Sig
  include Agreeable
  include Scoreable

  belongs_to :legislator

  sig { returns(Legislator) }
  def legislator
    T.cast(super, Legislator)
  end

  sig { params(user_vote: UserVote).returns(LegislatorDistrictScore) }
  def update_score(user_vote)
    update_agreeable_score(user_vote, legislator_vote(user_vote))
    save!
    self
  end

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |lds|
      # How user compares to Legislator
      lds.legislator_id legislator_id

      lds.count_agreed count_agreed
      lds.count_disagreed count_disagreed
      lds.count_no_legislator_vote count_no_legislator_vote
      lds.count_legislator_abstained count_legislator_abstained
    end
  end

  private

  sig { override.params(user_vote: UserVote).returns(T.nilable(LegislatorVote)) }
  def legislator_vote(user_vote)
    legislator.vote(user_vote.bill)
  end
end
