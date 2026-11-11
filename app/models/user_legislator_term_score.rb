# frozen_string_literal: true

# == Schema Information
#
# Table name: user_legislator_term_scores
# Database name: primary
#
#  id                         :integer          not null, primary key
#  count_agreed               :integer          default(0), not null
#  count_disagreed            :integer          default(0), not null
#  count_legislator_abstained :integer          default(0), not null
#  count_no_legislator_vote   :integer          default(0), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  legislator_term_id         :integer          not null
#  user_legislator_id         :integer          not null
#
# Indexes
#
#  index_user_legislator_term_scores_on_ul_and_term  (user_legislator_id,legislator_term_id) UNIQUE
#
# Foreign Keys
#
#  legislator_term_id  (legislator_term_id => legislator_terms.id)
#  user_legislator_id  (user_legislator_id => user_legislators.id)
#
# @lat: [[score-recompute-service-overview#Why recompute_bill_score_districts! counts DISTINCT user_votes.id]]
# @lat: [[scores-and-agreement#Every score is bound to a term]]
class UserLegislatorTermScore < ApplicationRecord
  belongs_to :user_legislator
  belongs_to :legislator_term

  has_one :legislator, through: :user_legislator
  has_one :user, through: :user_legislator

  validates :legislator_term_id, uniqueness: {scope: :user_legislator_id}
end
