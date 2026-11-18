# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_scores
# Database name: primary
#
#  id         :integer          not null, primary key
#  against    :integer          default(0), not null
#  for        :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  bill_id    :integer          not null
#
# Indexes
#
#  index_bill_scores_on_bill_id  (bill_id) UNIQUE
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#

class BillScore < ApplicationRecord
  belongs_to :bill
  delegate :sway_locale, to: :bill

  has_many :bill_score_districts, dependent: :destroy

  # @lat: [[bill-score-builder-variants#Why BillsController.index preloads bill_score_districts]]
  def to_builder
    Jbuilder.new do |bs|
      bs.id id
      bs.bill_id bill_id
      bs.for self.for
      bs.against against
      bs.comparison_suppressed VoteComparisonPrivacy.suppressed?(self.for, against)
      bs.voters_needed VoteComparisonPrivacy.voters_needed(self.for, against)

      bs.districts bill_score_districts.map(&:to_sway_json)
    end
  end

  def to_builder_with_user(user, user_districts: nil)
    # @lat: [[bill-score-builder-variants#Why BillsController.index preloads bill_score_districts]]
    user_districts ||=
      user&.districts(sway_locale) || [sway_locale.at_large_district].compact
    user_districts_by_id = user_districts.select(&:id).index_by(&:id)

    bill_districts =
      bill_score_districts.filter do |bsd|
        if bsd.district_id && user_districts_by_id.any?
          matched_district = user_districts_by_id[bsd.district_id]
          if matched_district
            bsd.district = matched_district unless bsd.association(:district).loaded?
            true
          else
            false
          end
        else
          user_districts.include?(bsd.district)
        end
      end

    Jbuilder.new do |bs|
      bs.id id
      bs.bill_id bill_id
      bs.for self.for
      bs.against against
      bs.comparison_suppressed VoteComparisonPrivacy.suppressed?(self.for, against)
      bs.voters_needed VoteComparisonPrivacy.voters_needed(self.for, against)
      bs.districts bill_districts.map(&:to_sway_json)
    end
  end
end
