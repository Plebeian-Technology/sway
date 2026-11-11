# frozen_string_literal: true

# @lat: [[news-article-evidence#Discovery request receipt]]
class NewsArticleDiscoveryRequestService
  def self.request!(bill:, requested_by:)
    validate_actor_and_bill!(bill: bill, requested_by: requested_by)

    doc = SwayLocale::DocumentReader.current_for(bill.sway_locale)

    NewsArticleDiscoveryRequest.create!(
      bill: bill,
      requested_by: requested_by,
      status: "queued",
      source_config_digest: doc.source_config_digest,
      provider: BraveSearch::Client::PROVIDER_NAME,
      model: BraveSearch::Client::MODEL_NAME,
      match_counts: {"direct" => 0, "context" => 0, "ambiguous" => 0, "unmatched" => 0},
      diagnostics: []
    )
  end

  def self.retry!(discovery_request)
    raise ArgumentError, "discovery_request must be present and persisted" unless discovery_request&.persisted?

    bill = discovery_request.bill
    doc = SwayLocale::DocumentReader.current_for(bill.sway_locale)

    discovery_request.update!(
      status: "queued",
      source_config_digest: doc.source_config_digest,
      provider: BraveSearch::Client::PROVIDER_NAME,
      model: BraveSearch::Client::MODEL_NAME,
      match_counts: {"direct" => 0, "context" => 0, "ambiguous" => 0, "unmatched" => 0},
      diagnostics: [],
      completed_at: nil
    )
    discovery_request
  end

  def self.validate_actor_and_bill!(bill:, requested_by:)
    raise ArgumentError, "bill must be a persisted Bill" unless bill.is_a?(Bill) && bill.persisted?

    is_admin = requested_by.is_a?(User) && requested_by.respond_to?(:is_sway_admin?) && requested_by.is_sway_admin?
    raise ArgumentError, "requested_by must be a Sway admin" unless is_admin
  end
end
