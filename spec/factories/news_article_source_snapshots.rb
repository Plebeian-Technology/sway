# frozen_string_literal: true

# == Schema Information
#
# Table name: news_article_source_snapshots
# Database name: primary
#
#  id             :integer          not null, primary key
#  digest         :string           not null
#  purpose        :string           not null
#  run_receipt    :string
#  source_entries :json             not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  actor_id       :integer
#  bill_id        :integer          not null
#
# Indexes
#
#  index_news_article_source_snapshots_on_actor_id                (actor_id)
#  index_news_article_source_snapshots_on_bill_id                 (bill_id)
#  index_news_article_source_snapshots_on_bill_id_and_created_at  (bill_id,created_at)
#  index_news_article_source_snapshots_on_bill_id_and_purpose     (bill_id,purpose)
#  index_news_article_source_snapshots_on_digest                  (digest)
#  index_news_article_source_snapshots_on_run_receipt             (run_receipt)
#
# Foreign Keys
#
#  actor_id  (actor_id => users.id) ON DELETE => nullify
#  bill_id   (bill_id => bills.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :news_article_source_snapshot do
    bill
    purpose { "summary" }
    source_entries { [] }
    run_receipt { nil }
    actor { nil }

    trait :summary do
      purpose { "summary" }
    end

    trait :testimony do
      purpose { "testimony" }
    end

    trait :manual do
      actor { association :user, :sway_admin }
    end

    trait :automated do
      actor { nil }
      run_receipt { "pipeline-run-#{SecureRandom.hex(6)}" }
    end

    trait :with_entries do
      transient do
        bill_news_article { nil }
      end

      after(:build) do |snapshot, evaluator|
        bna = evaluator.bill_news_article || create(:bill_news_article, :approved, :with_text_version, bill: snapshot.bill)
        snapshot.source_entries = [
          {
            "bill_news_article_id" => bna.id,
            "news_article_id" => bna.news_article_id,
            "text_version_id" => bna.current_text_version_id,
            "news_article_text_version_id" => bna.current_text_version_id,
            "text_digest" => bna.current_text_version&.digest,
            "digest" => bna.current_text_version&.digest,
            "review_version" => bna.review_version,
            "approved" => bna.approved,
            "stance" => bna.stance,
            "stance_version" => bna.stance_version,
            "outlet_name" => bna.news_article.outlet_name,
            "canonical_url" => bna.news_article.canonical_url
          }
        ]
      end
    end
  end
end
