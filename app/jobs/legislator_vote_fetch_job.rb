# frozen_string_literal: true

# @lat: [[legislation-pipeline#Upstream jurisdiction adapters]]
class LegislatorVoteFetchJob < ApplicationJob
  queue_as :background

  limits_concurrency to: 1,
    key: ->(bill_id, **_kwargs) { "legislator_votes_#{bill_id}" },
    on_conflict: :discard

  discard_on ActiveRecord::RecordNotFound, ArgumentError
  retry_on Net::OpenTimeout,
    Net::ReadTimeout,
    Faraday::TimeoutError,
    Faraday::ConnectionFailed,
    Legistar::Client::Error,
    wait: :polynomially_longer,
    attempts: 3
  retry_on Scraper::Congress::RollCallUnavailable,
    wait: 1.hour,
    attempts: 3

  def self.run_service_for(bill_id)
    bill = Bill.find_by(id: bill_id)
    return unless bill

    rules = bill.sway_locale.jurisdiction_rules
    if rules.vote_retrieval&.to_s == "congress_dot_gov" ||
        rules.vote_rules&.dig("retrieval") == "congress_dot_gov" ||
        rules.vote_rules&.dig(:retrieval) == "congress_dot_gov"
      CongressLegislatorVoteUpdateService.call(bill)
    else
      adapter = Legislation::Adapters::GenericVoteAdapter.new(rules.vote_rules || {})
      votes = adapter.fetch_votes(bill)
      GenericLegislatorVoteUpdateService.new.call(bill: bill, votes: votes)
    end
  end

  def perform(bill_id, force_refresh: false)
    self.class.run_service_for(bill_id)
  end
end
