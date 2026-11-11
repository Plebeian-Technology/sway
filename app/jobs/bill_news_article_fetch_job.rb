# frozen_string_literal: true

# @lat: [[news-article-evidence#Discovery request receipt]]
# @lat: [[llm-summaries#Batch summarisation]]
class BillNewsArticleFetchJob < ApplicationJob
  queue_as :background

  limits_concurrency to: 1,
    key: ->(bill_id, **_kwargs) { "news_fetch_#{bill_id}" },
    on_conflict: :discard

  discard_on ActiveRecord::RecordNotFound, ArgumentError

  retry_on Net::OpenTimeout,
    Net::ReadTimeout,
    Faraday::TimeoutError,
    Faraday::ConnectionFailed,
    wait: :polynomially_longer,
    attempts: 3

  def perform(bill_id, requested_by_id = nil, discovery_request_id = nil)
    bill = Bill.find_by(id: bill_id)
    return unless bill

    admin = User.find_by(id: requested_by_id)
    return unless admin&.is_sway_admin?

    discovery_request = nil
    if discovery_request_id
      discovery_request = NewsArticleDiscoveryRequest.find_by(id: discovery_request_id)
      return unless discovery_request && discovery_request.bill_id == bill.id && discovery_request.requested_by_id == admin.id
    end

    receipt = BillNewsArticleFetchService.call(
      bill: bill,
      requested_by: admin,
      discovery_request: discovery_request
    )

    if receipt&.status == "succeeded"
      bill.bill_news_articles.where(current_text_version_id: nil).find_each do |bna|
        NewsArticleTextFetchJob.perform_later(bna.id)
      end
    end

    receipt
  end
end
