# frozen_string_literal: true

# == Schema Information
#
# Table name: news_article_discovery_requests
# Database name: primary
#
#  id                   :integer          not null, primary key
#  completed_at         :datetime
#  diagnostics          :json             not null
#  match_counts         :json             not null
#  model                :string           not null
#  provider             :string           not null
#  query                :text
#  source_config_digest :string           not null
#  status               :string           default("queued"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  bill_id              :integer          not null
#  requested_by_id      :integer          not null
#
# Indexes
#
#  idx_on_bill_id_created_at_5965be0083                         (bill_id,created_at)
#  index_news_article_discovery_requests_on_bill_id             (bill_id)
#  index_news_article_discovery_requests_on_bill_id_and_status  (bill_id,status)
#  index_news_article_discovery_requests_on_requested_by_id     (requested_by_id)
#  index_news_article_discovery_requests_on_status              (status)
#
# Foreign Keys
#
#  bill_id          (bill_id => bills.id) ON DELETE => cascade
#  requested_by_id  (requested_by_id => users.id) ON DELETE => restrict
#
FactoryBot.define do
  factory :news_article_discovery_request do
    bill
    requested_by factory: %i[user sway_admin]
    status { "queued" }
    source_config_digest { Digest::SHA256.hexdigest("factory-config") }
    provider { "claude" }
    model { "claude-haiku-5-5" }
    match_counts { {"direct" => 0, "context" => 0, "ambiguous" => 0, "unmatched" => 0} }
    diagnostics { [] }

    trait :running do
      status { "running" }
    end

    trait :succeeded do
      status { "succeeded" }
      match_counts { {"direct" => 1, "context" => 0, "ambiguous" => 0, "unmatched" => 0} }
      completed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      completed_at { Time.current }
      diagnostics { [{"error" => "Simulated failure"}] }
    end
  end
end
