# frozen_string_literal: true

# @lat: [[legislation-pipeline#Upstream jurisdiction adapters]]
class LegislatorVoteSweepJob < ApplicationJob
  queue_as :background

  WAIT_CEILING_SECONDS = 1800
  ROLL_CALL_RETRIEVALS = %w[congress_dot_gov generic_csv open_states maryland_general_assembly generic_html congress].freeze
  EXTERNAL_ID_RETRIEVALS = %w[legistar generic_rest generic_json].freeze

  def perform
    SwayLocale.find_each do |sway_locale|
      unless SwayLocale::JurisdictionRulesRegistry.declared?(sway_locale.name)
        SwayLogging.warn("legislator_vote_sweep.undeclared_locale", sway_locale: sway_locale.name)
        next
      end

      rules = sway_locale.jurisdiction_rules
      vote_rules = rules.vote_rules || {}
      retrieval = (rules.respond_to?(:retrieval_for) ? rules.retrieval_for(:vote) : nil) ||
        vote_rules[:retrieval]&.to_s ||
        vote_rules["retrieval"]&.to_s ||
        vote_rules[:engine]&.to_s ||
        vote_rules["engine"]&.to_s
      next if %w[manual unavailable].include?(retrieval) || retrieval.blank?

      scope = filter_scope_for_engine(Bill.where(sway_locale: sway_locale), retrieval, sway_locale: sway_locale)

      scope.find_each.with_index do |bill, i|
        next if settled?(bill)

        wait_seconds = [i * 0.5, WAIT_CEILING_SECONDS].min
        LegislatorVoteFetchJob
          .set(wait: wait_seconds.seconds)
          .perform_later(bill.id)
      end
    end
  end

  private

  def filter_scope_for_engine(scope, engine_or_retrieval, sway_locale:)
    strategy = engine_or_retrieval.to_s
    if ROLL_CALL_RETRIEVALS.include?(strategy)
      scope.joins(:roll_calls).where(
        "roll_calls.house_roll_call_vote_number IS NOT NULL OR " \
        "roll_calls.senate_roll_call_vote_number IS NOT NULL"
      ).distinct
    elsif EXTERNAL_ID_RETRIEVALS.include?(strategy)
      scope.where.not(external_id: [nil, ""])
    else
      raise ArgumentError,
        "LegislatorVoteSweepJob has no bill filter for vote engine " \
        "#{strategy.inspect} (#{sway_locale.name})"
    end
  end

  # @lat: [[congress-roll-calls#Roll-call numbering restarts every year]]
  def settled?(bill)
    newest_vote = [bill.house_vote_date_time_utc, bill.senate_vote_date_time_utc].compact.max
    return false if newest_vote.nil? || newest_vote.year >= Time.current.year

    bill.legislator_votes.where(inferred: false).exists?
  end
end
