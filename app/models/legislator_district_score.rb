# frozen_string_literal: true

# == Schema Information
#
# Table name: legislator_district_scores
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
#  index_legislator_district_scores_on_legislator_term_id  (legislator_term_id) UNIQUE
#

# @lat: [[legislator-person-not-seat#Why LegislatorDistrictScore is keyed by district at all]]
class LegislatorDistrictScore < ApplicationRecord
  belongs_to :legislator_term
  has_one :legislator, through: :legislator_term

  def to_builder
    Jbuilder.new do |lds|
      lds.legislator_id legislator&.id

      lds.count_agreed count_agreed
      lds.count_disagreed count_disagreed
      lds.count_no_legislator_vote count_no_legislator_vote
      lds.count_legislator_abstained count_legislator_abstained
    end
  end
end
