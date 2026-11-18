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
    row = score.legislator_term.legislator_district_scores.first
    if row
      suppressed = VoteComparisonPrivacy.suppressed?(row.count_agreed, row.count_disagreed)
      percentages = VoteComparisonPercentageCalculator.calculate(
        UserLegislatorTermScoreResource.counters([row]),
        row.distinct_voter_count
      )
      {
        legislator_id: row.legislator_term.legislator_id,
        comparison_suppressed: suppressed,
        agreed_percent: suppressed ? nil : percentages[:agreed],
        disagreed_percent: suppressed ? nil : percentages[:disagreed],
        abstained_percent: suppressed ? nil : percentages[:abstained],
        no_vote_percent: suppressed ? nil : percentages[:no_vote]
      }.merge(
        suppressed ? {count_agreed: nil, count_disagreed: nil, count_no_legislator_vote: nil, count_legislator_abstained: nil} : UserLegislatorTermScoreResource.counters([row])
      )
    end
  end

  attribute :legislator_locale_score do |score|
    row = score.legislator_term.legislator_locale_scores.first
    if row
      suppressed = VoteComparisonPrivacy.suppressed?(row.count_agreed, row.count_disagreed)
      percentages = VoteComparisonPercentageCalculator.calculate(
        UserLegislatorTermScoreResource.counters([row]),
        row.distinct_voter_count
      )
      {
        legislator_id: row.legislator_term.legislator_id,
        comparison_suppressed: suppressed,
        agreed_percent: suppressed ? nil : percentages[:agreed],
        disagreed_percent: suppressed ? nil : percentages[:disagreed],
        abstained_percent: suppressed ? nil : percentages[:abstained],
        no_vote_percent: suppressed ? nil : percentages[:no_vote]
      }.merge(
        suppressed ? {count_agreed: nil, count_disagreed: nil, count_no_legislator_vote: nil, count_legislator_abstained: nil} : UserLegislatorTermScoreResource.counters([row])
      )
    end
  end

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

      {legislator_id: legislator_id}.merge(counters(rows))
    end
  end
end
