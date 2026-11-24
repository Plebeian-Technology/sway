# frozen_string_literal: true

# @lat: [[user-legislator-term-score-resource-shapes#The frontend type mirror (app/frontend/index.d.ts)]]
class UserLegislatorTermScoreResource < ApplicationResource
  attributes :count_agreed, :count_disagreed, :count_no_legislator_vote,
    :count_legislator_abstained

  attribute :user_legislator_id do |score|
    score.user_legislator_id
  end

  attribute :legislator_id do |score|
    score.user_legislator.legislator_id
  end

  attribute :sway_locale_id do |score|
    score.user_legislator.legislator.sway_locale_id
  end

  attribute :legislator_district_score do |score|
    term = score.legislator_term
    UserLegislatorTermScoreResource.aggregate(term.legislator_district_scores.first(1), term.legislator_id)
  end

  attribute :legislator_locale_score do |score|
    term = score.legislator_term
    UserLegislatorTermScoreResource.aggregate(term.legislator_locale_scores.first(1), term.legislator_id)
  end

  PERCENT_KEY_BY_COUNTER = {
    count_agreed: :agreed_percent,
    count_disagreed: :disagreed_percent,
    count_no_legislator_vote: :no_legislator_vote_percent,
    count_legislator_abstained: :legislator_abstained_percent
  }.freeze

  class << self
    # @lat: [[user-legislator-term-score-resource-shapes#Why the current-term and lifetime shapes share key names]]
    def lifetime_hash_for(user_legislator)
      legislator = user_legislator.legislator
      term_scores = user_legislator.user_legislator_term_scores.to_a
      district_rows = legislator.legislator_terms.flat_map(&:legislator_district_scores)
      locale_rows = legislator.legislator_terms.flat_map(&:legislator_locale_scores)

      {
        user_legislator_id: user_legislator.id,
        legislator_id: legislator.id,
        sway_locale_id: legislator.sway_locale_id
      }.merge(counters(term_scores)).merge(
        legislator_district_score: aggregate(district_rows, legislator.id),
        legislator_locale_score: aggregate(locale_rows, legislator.id)
      )
    end

    def counters(rows)
      {
        count_agreed: rows.sum { |row| row.count_agreed },
        count_disagreed: rows.sum { |row| row.count_disagreed },
        count_no_legislator_vote: rows.sum { |row| row.count_no_legislator_vote },
        count_legislator_abstained: rows.sum { |row| row.count_legislator_abstained }
      }
    end

    def aggregate(rows, legislator_id)
      return nil if rows.empty?

      {legislator_id: legislator_id}.merge(group_score(rows))
    end

    # @lat: [[voter-privacy-threshold#Legislator scores are sent as percentages]]
    def group_score(rows)
      totals = counters(rows)
      suppressed = comparison_suppressed?(rows, totals)
      {comparison_suppressed: suppressed}
        .merge(suppressed ? PERCENT_KEY_BY_COUNTER.values.index_with { nil } : percentages(totals))
    end

    # @lat: [[voter-privacy-threshold#A lifetime figure needs every summed term at the minimum]]
    def comparison_suppressed?(rows, totals)
      counted_rows = rows.select { |row| row.distinct_voter_count.positive? }
      totals.values.sum.zero? || counted_rows.empty? ||
        counted_rows.any? { |row| row.distinct_voter_count < VoteComparisonPrivacy::MINIMUM_VOTERS }
    end

    # Whole numbers that sum to 100; the largest remainders take the leftover points.
    def percentages(totals)
      total = totals.values.sum
      exact = totals.transform_values { |count| count * 100.0 / total }
      floors = exact.transform_values(&:floor)
      rounded_up = exact.keys.max_by(100 - floors.values.sum) { |counter| exact[counter] - floors[counter] }
      PERCENT_KEY_BY_COUNTER.to_h do |counter, percent_key|
        [percent_key, floors[counter] + (rounded_up.include?(counter) ? 1 : 0)]
      end
    end
  end
end
