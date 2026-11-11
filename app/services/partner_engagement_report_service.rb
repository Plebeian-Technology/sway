# frozen_string_literal: true

class PartnerEngagementReportService
  # @lat: [[partner-article-engagement#Newsroom reporting and Alba serialization]]

  class Report < Struct.new(
    :organization,
    :partner_slug,
    :partner_name,
    :total_articles,
    :total_bills_covered,
    :total_clicks,
    :total_registrations,
    :total_votes,
    :pro_votes,
    :con_votes,
    :pro_percentage,
    :con_percentage,
    :articles
  )
    def articles_count
      total_articles
    end

    def bills_count
      total_bills_covered
    end
  end

  def initialize(organization:, start_date: nil, end_date: nil)
    @organization = organization.is_a?(Organization) ? organization : Organization.find(organization)
    @start_date = start_date
    @end_date = end_date
  end

  def call
    scope = @organization.article_bills.joins(:bill)
    if @start_date.present? && @end_date.present?
      scope = scope.where(published_at: @start_date..@end_date)
    end

    articles = scope.order(created_at: :desc).to_a

    total_articles = articles.size
    total_bills_covered = articles.map(&:bill_id).uniq.size
    total_clicks = articles.sum(&:clicks_count)
    total_registrations = articles.sum(&:registrations_count)
    total_votes = articles.sum(&:votes_count)
    pro_votes = articles.sum(&:pro_votes_count)
    con_votes = articles.sum(&:con_votes_count)

    # @lat: [[partner-article-engagement#Privacy guarantees and k-anonymity]]
    pro_percentage = nil
    con_percentage = nil
    if total_votes >= 5
      pro_percentage = ((pro_votes.to_f / total_votes) * 100).round(1)
      con_percentage = ((con_votes.to_f / total_votes) * 100).round(1)
    end

    partner_slug = articles.first&.partner_slug || @organization.name.parameterize

    Report.new(
      organization: @organization,
      partner_slug: partner_slug,
      partner_name: @organization.name,
      total_articles: total_articles,
      total_bills_covered: total_bills_covered,
      total_clicks: total_clicks,
      total_registrations: total_registrations,
      total_votes: total_votes,
      pro_votes: pro_votes,
      con_votes: con_votes,
      pro_percentage: pro_percentage,
      con_percentage: con_percentage,
      articles: articles
    )
  end
end
