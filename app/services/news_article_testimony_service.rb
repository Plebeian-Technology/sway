# frozen_string_literal: true

# @lat: [[news-testimony#Grounding published opinion testimony in article evidence]]
class NewsArticleTestimonyService
  def self.eligible_articles(bill)
    return [] unless bill

    bill.bill_news_articles
      .eligible_for_testimony
      .includes(:news_article, :current_text_version)
      .order(:id)
      .to_a
      .select(&:eligible_for_testimony?)
  end

  def self.commentary_eligible?(bill)
    eligible_articles(bill).any?
  end

  def self.persist_drafts!(bill:, payload:, snapshot:, run_receipt: nil)
    new(bill: bill, payload: payload, snapshot: snapshot, run_receipt: run_receipt).persist_drafts!
  end

  def self.publish_commentary!(bill:, snapshot:)
    new(bill: bill, payload: nil, snapshot: snapshot).publish_commentary!
  end

  class << self
    alias_method :record_drafts!, :persist_drafts!
    alias_method :publish_generated_commentary!, :publish_commentary!
    alias_method :publish_drafts!, :publish_commentary!
  end

  def initialize(bill:, payload: nil, snapshot: nil, run_receipt: nil)
    @bill = bill
    @payload = payload || {}
    @snapshot = snapshot
    @run_receipt = run_receipt
  end

  def persist_drafts!
    raw_items = @payload["draft_news_testimonies"] || @payload[:draft_news_testimonies] || @payload["published_opinion_commentary"]
    return [] if raw_items.blank? || !raw_items.is_a?(Array)

    ActiveRecord::Base.transaction do
      raw_items.filter_map do |item|
        record_single_draft(item)
      end
    end
  end

  def publish_commentary!
    return [] unless bill && snapshot
    return [] if snapshot.bill_id != bill.id
    return [] unless snapshot.current_eligibility_comparison.eligible?

    drafts = bill.news_article_testimonies.drafts.where(news_article_source_snapshot_id: snapshot.id).to_a
    return [] if drafts.empty?

    published_testimonies = []

    drafts.each do |testimony|
      bna = testimony.bill_news_article
      next unless bna

      source_use = snapshot.source_uses.find_by(
        bill_news_article_id: bna.id,
        text_version_id: testimony.news_article_text_version_id,
        evidence_excerpt: testimony.evidence_excerpt
      )

      content = if testimony.citation_url.present?
        "#{testimony.argument_markdown} [#{testimony.outlet_name.presence || "Source"}](#{testimony.citation_url})"
      else
        testimony.argument_markdown
      end

      grounding_result = NewsClaimGroundingService.call(
        bill: bill,
        content: content,
        source_uses: (source_use ? [source_use] : nil),
        snapshot: snapshot,
        news_usage: "cited",
        persist: true
      )

      is_supported = grounding_result.supported?

      bill.with_lock do
        testimony.reload
        bna.reload

        if is_supported && testimony.currently_eligible? && snapshot.current_eligibility_comparison.eligible?
          bna.news_article_testimonies.published.where.not(id: testimony.id).update_all(
            publication_state: "withdrawn",
            updated_at: Time.current
          )

          testimony.update!(
            publication_state: "published",
            published_at: Time.current
          )
          published_testimonies << testimony
        end
      end
    end

    published_testimonies
  end

  private

  attr_reader :bill, :snapshot, :run_receipt

  def record_single_draft(item)
    return nil unless item.is_a?(Hash)

    item = item.with_indifferent_access
    bna_id = item["bill_news_article_id"]&.to_i
    tv_id = item["text_version_id"]&.to_i
    stance = item["stance"].to_s
    argument = (item["argument"] || item["argument_markdown"]).to_s
    excerpt = item["evidence_excerpt"].to_s
    canonical_url = (item["canonical_url"] || item["citation_url"]).to_s

    return nil if bna_id.nil? || bna_id <= 0 || tv_id.nil? || tv_id <= 0
    return nil if stance.blank? || argument.blank? || excerpt.blank?

    bna = bill.bill_news_articles.find_by(id: bna_id)
    return nil unless bna&.eligible_for_testimony?
    return nil unless bna.stance == stance

    tv = bna.current_text_version
    return nil unless tv && tv.id == tv_id && tv.usable_text?
    return nil unless tv.text.to_s.include?(excerpt)

    article = bna.news_article
    return nil unless article
    return nil unless attribution_valid?(article, item, canonical_url)

    outlet = article.outlet_name
    author = article.author_name
    citation_url = article.canonical_url

    testimony = bna.news_article_testimonies.create!(
      news_article_source_snapshot: snapshot,
      news_article_text_version: tv,
      argument_markdown: argument,
      evidence_excerpt: excerpt,
      citation_url: citation_url,
      author_name: author,
      outlet_name: outlet,
      stance: bna.stance,
      stance_version: bna.stance_version,
      review_version: bna.review_version,
      text_digest: tv.digest,
      publication_state: "draft"
    )

    record_source_use!(bna, tv, argument, excerpt, citation_url) if snapshot

    testimony
  end

  def record_source_use!(bna, tv, claim_text, excerpt, citation_url)
    return unless snapshot

    snapshot.source_uses.create!(
      bill_news_article_id: bna.id,
      text_version_id: tv.id,
      claim_text: claim_text,
      evidence_excerpt: excerpt,
      citation_url: citation_url,
      grounding_status: "pending"
    )
  rescue ActiveRecord::RecordInvalid => e
    SwayLogging.warn(
      "news_article_testimony_service.invalid_source_use",
      bill_id: bill.id,
      bna_id: bna.id,
      tv_id: tv.id,
      message: e.message
    )
  end

  def attribution_valid?(article, item, canonical_url)
    gen_outlet = item["outlet_name"]&.to_s&.strip
    return false if gen_outlet.present? && gen_outlet != article.outlet_name.to_s.strip

    gen_url = canonical_url.to_s.strip
    return false if gen_url.present? && gen_url != article.canonical_url.to_s.strip

    gen_author = item["author_name"]&.to_s&.strip
    art_author = article.author_name&.strip

    if article.article_kind == "editorial"
      if gen_author.present?
        board_match = gen_author.casecmp?("editorial board") ||
          gen_author.casecmp?("#{article.outlet_name} editorial board") ||
          (art_author.present? && gen_author.casecmp?(art_author))
        return false unless board_match
      end
    elsif art_author.present?
      return false if gen_author.present? && gen_author != art_author
    elsif gen_author.present?
      return false
    end

    true
  end
end
