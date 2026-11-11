# frozen_string_literal: true

class PartnerEngagementReportResource < ApplicationResource
  # @lat: [[partner-article-engagement#Newsroom reporting and Alba serialization]]
  attributes :partner_slug,
    :partner_name,
    :articles_count,
    :bills_count,
    :total_clicks,
    :total_registrations,
    :total_votes,
    :pro_percentage,
    :con_percentage

  attribute :articles do |report|
    report.articles.map do |article|
      suppress = article.votes_count < 5
      {
        id: article.id,
        bill_id: article.bill_id,
        bill_title: article.bill&.title,
        article_title: article.article_title,
        article_url: article.article_url,
        published_at: article.published_at,
        clicks_count: article.clicks_count,
        registrations_count: article.registrations_count,
        votes_count: article.votes_count,
        sentiment_suppressed: suppress,
        pro_votes_count: suppress ? nil : article.pro_votes_count,
        con_votes_count: suppress ? nil : article.con_votes_count
      }
    end
  end
end
