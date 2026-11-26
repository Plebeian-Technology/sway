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
      counted_rows = rows.select { |row| row.distinct_voter_count.positive? }
      totals = counters(counted_rows)
      suppressed = comparison_suppressed?(counted_rows, totals)
      voters = counted_rows.map(&:distinct_voter_count).min || 0
      {comparison_suppressed: suppressed}
        .merge(suppressed ? PERCENT_KEY_BY_COUNTER.values.index_with { nil } : percentages(totals, voters))
        .merge(voter_agreement_percent: suppressed ? nil : voter_agreement_percent(totals, voters))
    end

    # Rounded agreed share of agreed plus disagreed; nil when neither was counted.
    def voter_agreement_percent(totals, voters)
      VoteComparisonPrivacy
        .rounded_percentages({agreed: totals[:count_agreed], disagreed: totals[:count_disagreed]}, voters:)
        &.fetch(:agreed)
    end

    # @lat: [[voter-privacy-threshold#A lifetime figure needs every summed term at the minimum]]
    def comparison_suppressed?(counted_rows, totals)
      totals.values.sum.zero? ||
        counted_rows.any? { |row| row.distinct_voter_count < VoteComparisonPrivacy::MINIMUM_VOTERS } ||
        VoteComparisonPrivacy.unanimous?(totals[:count_agreed], totals[:count_disagreed])
    end

    # Percentages in steps of five or ten that sum to 100.
    def percentages(totals, voters)
      rounded = VoteComparisonPrivacy.rounded_percentages(totals, voters:) || {}
      PERCENT_KEY_BY_COUNTER.to_h { |counter, percent_key| [percent_key, rounded.fetch(counter)] }
    end
  end
end
