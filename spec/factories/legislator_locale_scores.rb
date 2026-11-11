# == Schema Information
#
# Table name: legislator_locale_scores
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
#
# Indexes
#
#  index_legislator_locale_scores_on_legislator_term_id  (legislator_term_id) UNIQUE
#
FactoryBot.define do
  factory :legislator_locale_score do
    legislator_term
    count_agreed { 0 }
    count_disagreed { 0 }
    count_legislator_abstained { 0 }
    count_no_legislator_vote { 0 }
  end
end
