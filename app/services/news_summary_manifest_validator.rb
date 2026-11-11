# frozen_string_literal: true

# @lat: [[news-article-evidence#Source snapshots and claim uses]]
# @lat: [[news-gate#Why ungrounded generations are quarantined as draft revisions]]
class NewsSummaryManifestValidator
  class Result
    attr_reader :valid, :news_usage, :errors, :reasons, :structured_refusal

    def initialize(valid:, news_usage: nil, errors: [], reasons: [], structured_refusal: nil)
      @valid = valid
      @news_usage = news_usage
      @errors = errors || []
      @reasons = reasons || []
      @structured_refusal = structured_refusal
    end

    def valid?
      @valid
    end
  end

  def self.call(bill:, summary_markdown:, news_usage:, source_uses:, snapshot: nil)
    new(
      bill: bill,
      summary_markdown: summary_markdown,
      news_usage: news_usage,
      source_uses: source_uses,
      snapshot: snapshot
    ).call
  end

  def initialize(bill:, summary_markdown:, news_usage:, source_uses:, snapshot: nil)
    @bill = bill
    @summary_markdown = summary_markdown.to_s
    @news_usage = news_usage
    @source_uses = source_uses
    @snapshot = snapshot
    @errors = []
    @reasons = []
  end

  def call
    usage_str = news_usage&.to_s&.strip

    if usage_str.blank? || !%w[none cited].include?(usage_str)
      @errors << "Missing or invalid news_usage declaration: #{news_usage.inspect}"
      @reasons << :invalid_news_usage
      return build_result(valid: false, news_usage: usage_str)
    end

    prose_news_urls = extract_prose_news_urls

    if usage_str == "none"
      if prose_news_urls.any?
        @errors << "Declared no-news usage but content contains visible news citations: #{prose_news_urls.join(", ")}"
        @reasons << :undeclared_news_links
      end

      if source_uses.present?
        @errors << "Declared no-news usage but source-use manifest is not empty"
        @reasons << :non_empty_manifest
      end

      return build_result(valid: @errors.empty?, news_usage: "none")
    end

    if snapshot.nil?
      @errors << "Missing or invalid news source snapshot for cited news usage"
      @reasons << :missing_snapshot
      return build_result(valid: false, news_usage: "cited")
    end

    if snapshot.bill_id != bill.id
      @errors << "News source snapshot belongs to a different bill"
      @reasons << :cross_bill_snapshot
      return build_result(valid: false, news_usage: "cited")
    end

    uses_list = source_uses.is_a?(Array) ? source_uses : []

    if uses_list.empty? && prose_news_urls.empty?
      @errors << "Declared cited news usage but source-use manifest is empty"
      @reasons << :empty_manifest
      return build_result(valid: false, news_usage: "cited")
    end

    manifest_urls = uses_list.filter_map do |u|
      next unless u.is_a?(Hash)
      (u["citation_url"] || u[:citation_url])&.to_s
    end.compact_blank.uniq

    unmanifested_urls = prose_news_urls.reject { |u| manifest_urls.include?(u) }
    unmanifested_urls.each do |url|
      validate_prose_url_against_snapshot(url)
    end

    missing_in_prose = manifest_urls.reject { |u| prose_news_urls.include?(u) }
    if missing_in_prose.any?
      @errors << "Manifest citation URL #{missing_in_prose.join(", ")} does not appear in visible prose"
      @reasons << :manifest_url_not_in_prose
    end

    uses_list.each do |use_payload|
      validate_use_entry(use_payload, prose_news_urls)
    end

    build_result(valid: @errors.empty?, news_usage: "cited")
  end

  private

  attr_reader :bill, :summary_markdown, :news_usage, :source_uses, :snapshot

  def extract_prose_news_urls
    prose_urls = SummaryCitationValidator.extract_prose_urls(summary_markdown)
    official_url = SummaryCitationValidator.official_bill_url(bill)
    prose_urls.reject do |url|
      SummaryCitationValidator.official_url?(url, official_url)
    end
  end

  def validate_prose_url_against_snapshot(url)
    bna = bill.bill_news_articles.includes(:news_article, :current_text_version).find do |candidate|
      candidate.news_article&.canonical_url == url
    end

    if bna.nil?
      @errors << "Citation URL #{url} does not belong to referenced article"
      @reasons << :canonical_url_mismatch
      return
    end

    unless bna.approved?
      @errors << "Bill news article approval is false or has been withdrawn"
      @reasons << :unapproved_article
      return
    end

    captured_entries = snapshot&.captured_source_entries || []
    captured_entry = captured_entries.find do |entry|
      h = entry.respond_to?(:to_h) ? entry.to_h.stringify_keys : entry
      (h["bill_news_article_id"] || h[:bill_news_article_id])&.to_i == bna.id
    end

    if captured_entry.nil?
      @errors << "Bill news article #{bna.id} is not present in referenced snapshot"
      @reasons << :not_in_snapshot
      return
    end

    h_entry = captured_entry.respond_to?(:to_h) ? captured_entry.to_h.stringify_keys : captured_entry
    if h_entry["approved"] == false || h_entry[:approved] == false
      @errors << "Bill news article approval is false or has been withdrawn"
      @reasons << :unapproved_article
      return
    end

    captured_tv_id = (h_entry["text_version_id"] || h_entry[:text_version_id] || h_entry["news_article_text_version_id"])&.to_i
    if captured_tv_id.nil? || captured_tv_id <= 0 || bna.current_text_version_id != captured_tv_id
      @errors << "Text version #{bna.current_text_version_id} does not match captured snapshot text version #{captured_tv_id}"
      @reasons << :snapshot_text_version_mismatch
      return
    end
    tv = NewsArticleTextVersion.find_by(id: captured_tv_id)

    if tv.nil? || tv.news_article_id != bna.news_article_id
      @errors << "Text version does not belong to article"
      @reasons << :text_version_mismatch
      return
    end

    unless tv.usable_text?
      @errors << "Text version is not usable text (extraction_status: #{tv.extraction_status})"
      @reasons << :unusable_text
    end
  end

  def validate_use_entry(use_payload, prose_news_urls)
    unless use_payload.is_a?(Hash)
      @errors << "Source use entry must be a hash: #{use_payload.inspect}"
      @reasons << :malformed_source_use
      return
    end

    bna_id = (use_payload["bill_news_article_id"] || use_payload[:bill_news_article_id])&.to_i
    tv_id = (use_payload["text_version_id"] || use_payload[:text_version_id])&.to_i
    claim_text = (use_payload["claim_text"] || use_payload[:claim_text]).to_s
    excerpt = (use_payload["evidence_excerpt"] || use_payload[:evidence_excerpt] || use_payload["verbatim_excerpt"] || use_payload[:verbatim_excerpt]).to_s
    citation_url = (use_payload["citation_url"] || use_payload[:citation_url]).to_s

    if claim_text.blank? || excerpt.blank? || citation_url.blank? || bna_id.nil? || bna_id <= 0 || tv_id.nil? || tv_id <= 0
      @errors << "Claim text, evidence excerpt, citation URL, bill_news_article_id, and text_version_id must be present"
      @reasons << :malformed_source_use
      return
    end

    unless summary_markdown.include?(claim_text)
      @errors << "Claim text does not appear in prose"
      @reasons << :claim_text_missing_from_prose
    end

    unless prose_news_urls.include?(citation_url)
      @errors << "Manifest citation URL #{citation_url} does not appear in visible prose"
      @reasons << :manifest_url_not_in_prose
    end

    bna = bill.bill_news_articles.find_by(id: bna_id)
    if bna.nil?
      @errors << "Bill news article #{bna_id} does not belong to bill #{bill.id}"
      @reasons << :bna_not_found
      return
    end

    captured_entries = snapshot&.captured_source_entries || []
    captured_entry = captured_entries.find do |entry|
      h = entry.respond_to?(:to_h) ? entry.to_h.stringify_keys : entry
      (h["bill_news_article_id"] || h[:bill_news_article_id])&.to_i == bna.id
    end

    if captured_entry.nil?
      @errors << "Bill news article #{bna.id} is not present in referenced snapshot"
      @reasons << :not_in_snapshot
      return
    end

    h_entry = captured_entry.respond_to?(:to_h) ? captured_entry.to_h.stringify_keys : captured_entry

    captured_tv_id = (h_entry["text_version_id"] || h_entry[:text_version_id] || h_entry["news_article_text_version_id"])&.to_i
    if captured_tv_id.present? && captured_tv_id != tv_id
      @errors << "Text version #{tv_id} does not match captured snapshot text version #{captured_tv_id}"
      @reasons << :snapshot_text_version_mismatch
    end

    article_canonical = bna.news_article&.canonical_url
    unless article_canonical.present? && article_canonical == citation_url
      @errors << "Citation URL #{citation_url} does not belong to referenced article"
      @reasons << :canonical_url_mismatch
    end

    tv = NewsArticleTextVersion.find_by(id: tv_id)
    if tv.nil? || tv.news_article_id != bna.news_article_id
      @errors << "Text version does not belong to article"
      @reasons << :text_version_mismatch
      return
    end

    unless tv.usable_text?
      @errors << "Text version is not usable text (extraction_status: #{tv.extraction_status})"
      @reasons << :unusable_text
    end

    unless tv.text.to_s.include?(excerpt)
      @errors << "Evidence excerpt does not appear verbatim in article text version"
      @reasons << :excerpt_mismatch
    end
  end

  def build_result(valid:, news_usage:)
    @errors.uniq!
    @reasons.uniq!

    refusal = if valid
      nil
    else
      NewsClaimGroundingService::Result.new(
        verdict: "unsupported",
        claim_assessments: [],
        deterministic_errors: @errors
      )
    end

    Result.new(
      valid: valid,
      news_usage: news_usage,
      errors: @errors,
      reasons: @reasons,
      structured_refusal: refusal
    )
  end
end
