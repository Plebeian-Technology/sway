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
      bs.for_percent for_percent
      bs.against_percent against_percent
      bs.comparison_suppressed comparison_suppressed?

      bs.districts publishable_districts.map(&:to_sway_json)
    end
  end

  # Returns the district rows any reader may see for this bill.
  # @lat: [[voter-privacy-threshold#Districts are sent as percentages only]]
  def publishable_districts
    rows = bill_score_districts.select(&:publishable?)
    voters_outside_publishable?(rows) ? rows : []
  end

  # Returns the ids of the districts whose district agreement scores may count this bill.
  # @lat: [[voter-privacy-threshold#Legislator scores count only bills that reached the minimum]]
  def countable_district_ids
    at_large_rows =
      bill_score_districts.select do |row|
        row.at_large? && !row.comparison_suppressed? && voters_outside_publishable?([row])
      end
    (publishable_districts + at_large_rows).map(&:district_id)
  end

  # @lat: [[voter-privacy-threshold#Bill totals are sent as rounded percentages]]
  def comparison_suppressed?
    VoteComparisonPrivacy.withheld?(self.for, against)
  end

  def for_percent
    rounded_percentages&.fetch(:for)
  end

  def against_percent
    rounded_percentages&.fetch(:against)
  end

  def to_builder_with_user(user, user_districts: nil)
    # @lat: [[bill-score-builder-variants#Why BillsController.index preloads bill_score_districts]]
    user_districts ||=
      user&.districts(sway_locale) || [sway_locale.at_large_district].compact
    user_districts_by_id = user_districts.select(&:id).index_by(&:id)

    bill_districts =
      publishable_districts.filter do |bsd|
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
      bs.for_percent for_percent
      bs.against_percent against_percent
      bs.comparison_suppressed comparison_suppressed?
      bs.districts bill_districts.map(&:to_sway_json)
    end
  end

  private

  def rounded_percentages
    return nil if comparison_suppressed?

    VoteComparisonPrivacy.rounded_percentages({for: self.for, against: against}, voters: self.for + against)
  end

  def voters_outside_publishable?(rows)
    outside = (self.for + against) - rows.sum { |row| row.for + row.against }
    outside.zero? || outside >= VoteComparisonPrivacy::MINIMUM_VOTERS
  end
end
