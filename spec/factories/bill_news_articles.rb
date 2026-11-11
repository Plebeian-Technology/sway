# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_news_articles
# Database name: primary
#
#  id                      :integer          not null, primary key
#  approved                :boolean          default(FALSE), not null
#  approved_at             :datetime
#  match_evidence          :text
#  match_kind              :string           default("direct"), not null
#  review_version          :integer          default(0), not null
#  stance                  :string
#  stance_version          :integer          default(0), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  approved_by_id          :integer
#  bill_id                 :integer          not null
#  current_text_version_id :integer
#  news_article_id         :integer          not null
#  stance_by_id            :integer
#
# Indexes
#
#  index_bill_news_articles_on_approved_by_id               (approved_by_id)
#  index_bill_news_articles_on_bill_id                      (bill_id)
#  index_bill_news_articles_on_bill_id_and_approved         (bill_id,approved)
#  index_bill_news_articles_on_bill_id_and_news_article_id  (bill_id,news_article_id) UNIQUE
#  index_bill_news_articles_on_current_text_version_id      (current_text_version_id)
#  index_bill_news_articles_on_news_article_id              (news_article_id)
#  index_bill_news_articles_on_stance_by_id                 (stance_by_id)
#
# Foreign Keys
#
#  approved_by_id           (approved_by_id => users.id)
#  bill_id                  (bill_id => bills.id) ON DELETE => cascade
#  current_text_version_id  (current_text_version_id => news_article_text_versions.id) ON DELETE => restrict
#  news_article_id          (news_article_id => news_articles.id) ON DELETE => restrict
#  stance_by_id             (stance_by_id => users.id)
#
FactoryBot.define do
  factory :bill_news_article do
    bill
    news_article
    add_attribute(:match_kind) { "direct" }
    add_attribute(:match_evidence) { "Article directly references council bill number and title." }
    add_attribute(:approved) { false }
    add_attribute(:review_version) { 0 }
    add_attribute(:stance) { nil }
    add_attribute(:stance_version) { 0 }

    trait :approved do
      add_attribute(:approved) { true }
      add_attribute(:approved_at) { Time.current }
      add_attribute(:approved_by) { association :user }
      add_attribute(:review_version) { 1 }
    end

    trait :support do
      add_attribute(:stance) { "support" }
      add_attribute(:stance_by) { association :user }
      add_attribute(:stance_version) { 1 }
    end

    trait :oppose do
      add_attribute(:stance) { "oppose" }
      add_attribute(:stance_by) { association :user }
      add_attribute(:stance_version) { 1 }
    end

    trait :context_match do
      add_attribute(:match_kind) { "context" }
      add_attribute(:match_evidence) { "Broader context covering the subject matter of the bill." }
    end

    trait :with_text_version do
      after(:build) do |bna|
        bna.current_text_version ||= create(
          :news_article_text_version,
          :extracted,
          news_article: bna.news_article
        )
      end
    end

    trait :with_manual_text do
      after(:build) do |bna|
        bna.current_text_version ||= create(
          :news_article_text_version,
          :manual,
          news_article: bna.news_article
        )
      end
    end
  end
end
