# frozen_string_literal: true

# @lat: [[news-article-evidence#Source snapshots and claim uses]]
class NewsArticleSourceSnapshotService
  def self.capture!(
    bill:,
    purpose:,
    run_receipt: nil,
    actor: nil,
    bill_news_articles: nil,
    sources: nil,
    source_associations: nil,
    source_uses_attributes: nil,
    source_uses: nil
  )
    new(
      bill:,
      purpose:,
      run_receipt:,
      actor:,
      bill_news_articles:,
      sources:,
      source_associations:,
      source_uses_attributes:,
      source_uses:
    ).capture!
  end

  class << self
    alias_method :call, :capture!
    alias_method :record_snapshot!, :capture!
    alias_method :create_snapshot!, :capture!
  end

  def initialize(
    bill:,
    purpose:,
    run_receipt: nil,
    actor: nil,
    bill_news_articles: nil,
    sources: nil,
    source_associations: nil,
    source_uses_attributes: nil,
    source_uses: nil
  )
    @bill = bill
    @purpose = purpose.to_s
    @run_receipt = run_receipt
    @actor = actor
    @sources = sources || bill_news_articles || source_associations
    @source_uses_attributes = source_uses_attributes || source_uses || []
  end

  def capture!
    raise ArgumentError, "bill is required" if @bill.nil?
    unless NewsArticleSourceSnapshot::PURPOSES.include?(@purpose)
      raise ArgumentError, "Invalid purpose: #{@purpose}"
    end

    resolved_sources = resolve_sources
    validate_sources!(resolved_sources)

    entries = build_source_entries(resolved_sources)

    ActiveRecord::Base.transaction do
      snapshot = NewsArticleSourceSnapshot.new(
        bill: @bill,
        purpose: @purpose,
        run_receipt: @run_receipt,
        actor: @actor,
        source_entries: entries
      )
      snapshot.save!

      @source_uses_attributes.each do |use_attrs|
        use = snapshot.source_uses.build(use_attrs)
        use.save!
      end

      snapshot
    end
  end

  private

  def resolve_sources
    return @sources if @sources.present?

    if @purpose == "testimony"
      @bill.bill_news_articles.approved.with_stance
    else
      @bill.bill_news_articles.approved
    end
  end

  def validate_sources!(sources)
    sources.each do |bna|
      if bna.bill_id != @bill.id
        raise ArgumentError, "All sources must belong to bill #{@bill.id}"
      end
    end
  end

  def build_source_entries(sources)
    sources.map do |bna|
      tv = bna.current_text_version
      {
        "bill_news_article_id" => bna.id,
        "news_article_id" => bna.news_article_id,
        "text_version_id" => bna.current_text_version_id,
        "news_article_text_version_id" => bna.current_text_version_id,
        "text_digest" => tv&.digest,
        "digest" => tv&.digest,
        "review_version" => bna.review_version,
        "stance_version" => bna.stance_version,
        "stance" => bna.stance,
        "approved" => bna.approved,
        "canonical_url" => bna.news_article&.canonical_url,
        "outlet_name" => bna.news_article&.outlet_name
      }
    end
  end
end
