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
FactoryBot.define do
  factory :user_legislator_term_score do
    user_legislator
    legislator_term
    count_agreed { 0 }
    count_disagreed { 0 }
    count_legislator_abstained { 0 }
    count_no_legislator_vote { 0 }
  end
end
