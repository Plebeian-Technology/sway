# frozen_string_literal: true

# == Schema Information
#
# Table name: user_legislator_scores
# Database name: primary
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
  include Agreeable
  include Scoreable

  belongs_to :user_legislator

  def user_legislator
    super
  end

  def update_score(user_vote)
    update_agreeable_score(user_vote, legislator_vote(user_vote))
    save!
    self
  end

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
      district_score = legislator.legislator_district_score
      uls.legislator_district_score district_score&.to_sway_json
    end
  end

  def empty?
    count_agreed.zero? && count_disagreed.zero? &&
      count_legislator_abstained.zero? && count_no_legislator_vote.zero?
  end

  def legislator_vote(user_vote)
    legislator.vote(user_vote.bill)
  end

  private

  def legislator
    user_legislator.legislator
  end
end
