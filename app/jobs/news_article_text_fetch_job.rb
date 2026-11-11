# frozen_string_literal: true

# @lat: [[news-article-evidence#Discovery request receipt]]
# @lat: [[news-article-evidence#Immutable article text]]
# @lat: [[news-text#News text acquisition]]
class NewsArticleTextFetchJob < ApplicationJob
  queue_as :background

  limits_concurrency to: 1,
    key: ->(bill_news_article_id, **_kwargs) { "news_text_fetch_#{bill_news_article_id}" },
    on_conflict: :discard

  discard_on ActiveRecord::RecordNotFound, ArgumentError

  retry_on Net::OpenTimeout,
    Net::ReadTimeout,
    Faraday::TimeoutError,
    Faraday::ConnectionFailed,
    wait: :polynomially_longer,
    attempts: 3

  def perform(bill_news_article_id, force: false)
    bill_news_article = BillNewsArticle.find_by(id: bill_news_article_id)
    return unless bill_news_article

    if force
      NewsArticleTextFetchService.call(bill_news_article: bill_news_article, force: true)
    else
      NewsArticleTextFetchService.call(bill_news_article: bill_news_article)
    end
  end
end
