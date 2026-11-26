# frozen_string_literal: true

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
#  distinct_voter_count       :integer          default(0), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  legislator_term_id         :integer          not null
#
# Indexes
#
#  index_legislator_locale_scores_on_legislator_term_id  (legislator_term_id) UNIQUE
#

# @lat: [[legislator-person-not-seat#Why LegislatorLocaleScore exists separately from LegislatorDistrictScore]]
class LegislatorLocaleScore < ApplicationRecord
  belongs_to :legislator_term
  has_one :legislator, through: :legislator_term
end
