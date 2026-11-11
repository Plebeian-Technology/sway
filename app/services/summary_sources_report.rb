# frozen_string_literal: true

# @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]]
# @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
class SummarySourcesReport
  CLAUDE_PROVIDER = "claude"

  Record = Data.define(
    :source_kind, :source_chars, :source_cap, :source_reached_chars, :source_truncated, :extracted_text_chars,
    :diff_target, :diff_sections_modified, :diff_sections_referenced, :diff_sections_not_found, :diff_generated_at,
    :citation_keys_offered, :citation_keys_total, :citation_sample_titles,
    :news_search_available, :news_fetched_at, :newsroom_domains,
    :news_articles_offered, :news_articles_total, :news_articles
  )

  # @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
  Read = Data.define(:built_at, :llm_model, :llm_provider, :record)

  Result = Data.define(:read, :now, :summary_generated_at, :summary_model, :summary_provider)

  class << self
    def call(bill:)
      new(bill: bill).call
    end

    # @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
    def record(bill:, sources: nil)
      new(bill: bill).record(sources: sources)
    end
  end

  def initialize(bill:)
    @bill = bill
  end

  def call
    provisioning = bill.bill_llm_provisioning

    Result.new(
      read: read_of(bill.bill_summary_prompt_snapshot),
      now: record,
      summary_generated_at: provisioning&.llm_generated_at,
      summary_model: provisioning&.llm_model,
      summary_provider: provisioning&.llm_provider
    )
  end

  def record(sources: nil)
    counts = sources || BillSummaryPromptBuilder.new(bill).sources
    provisioning = bill.bill_llm_provisioning

    Record.new(
      source_kind: counts.source_kind,
      source_chars: counts.source_chars,
      source_cap: counts.source_cap,
      source_reached_chars: reached_chars(counts.source_chars, counts.source_cap),
      source_truncated: counts.source_truncated,
      extracted_text_chars: counts.extracted_text_chars,
      diff_target: counts.diff_target,
      diff_sections_modified: counts.diff_sections_modified,
      diff_sections_referenced: counts.diff_sections_referenced,
      diff_sections_not_found: counts.diff_sections_not_found,
      diff_generated_at: provisioning&.diff_generated_at,
      citation_keys_offered: counts.citation_keys_offered,
      citation_keys_total: counts.citation_keys_total,
      citation_sample_titles: counts.citation_sample_titles,
      news_search_available: Sway::Settings.llm.llm_provider.to_s.strip == CLAUDE_PROVIDER,
      news_fetched_at: provisioning&.news_articles_fetched_at,
      newsroom_domains: newsroom_domains,
      news_articles_offered: counts.news_articles_offered,
      news_articles_total: counts.news_articles_total,
      news_articles: news_articles(provisioning)
    )
  end

  private

  attr_reader :bill

  def read_of(snapshot)
    return nil if snapshot.nil?

    facts = snapshot.facts
    Read.new(
      built_at: snapshot.built_at,
      llm_model: snapshot.llm_model,
      llm_provider: snapshot.llm_provider,
      record: record_from_facts(facts.is_a?(Hash) ? facts.transform_keys(&:to_s) : {})
    )
  end

  # @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
  def record_from_facts(facts)
    chars = count_of(facts["source_chars"])
    cap = count_of(facts["source_cap"])

    Record.new(
      source_kind: facts["source_kind"].presence&.to_sym || :none,
      source_chars: chars,
      source_cap: cap,
      source_reached_chars: facts.key?("source_reached_chars") ? count_of(facts["source_reached_chars"]) : reached_chars(chars, cap),
      source_truncated: facts["source_truncated"] == true,
      extracted_text_chars: count_of(facts["extracted_text_chars"]),
      diff_target: facts["diff_target"]&.to_s,
      diff_sections_modified: integer_or_nil(facts["diff_sections_modified"]),
      diff_sections_referenced: integer_or_nil(facts["diff_sections_referenced"]),
      diff_sections_not_found: integer_or_nil(facts["diff_sections_not_found"]),
      diff_generated_at: time_or_nil(facts["diff_generated_at"]),
      citation_keys_offered: count_of(facts["citation_keys_offered"]),
      citation_keys_total: count_of(facts["citation_keys_total"]),
      citation_sample_titles: Array(facts["citation_sample_titles"]).map(&:to_s),
      news_search_available: facts["news_search_available"] == true,
      news_fetched_at: time_or_nil(facts["news_fetched_at"]),
      newsroom_domains: Array(facts["newsroom_domains"]).map(&:to_s),
      news_articles_offered: count_of(facts["news_articles_offered"]),
      news_articles_total: count_of(facts["news_articles_total"]),
      news_articles: stored_news_articles(facts["news_articles"])
    )
  end

  def reached_chars(chars, cap)
    [chars, cap].min
  end

  def count_of(value)
    integer_or_nil(value) || 0
  end

  def integer_or_nil(value)
    Integer(value, exception: false)
  end

  def time_or_nil(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def stored_news_articles(value)
    Array(value).filter_map do |article|
      next unless article.is_a?(Hash)

      row = article.transform_keys(&:to_s)
      {title: row["title"].to_s, host: row["host"].to_s}
    end
  end

  def newsroom_domains
    bill.sway_locale&.llm_bill_summarization_instruction&.allowed_domains || []
  end

  # @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]]
  def news_articles(provisioning)
    (provisioning&.news_articles_list || []).first(BillSummaryPromptBuilder::MAX_NEWS_ARTICLES).map do |article|
      url = (article["url"] || article[:url]).to_s
      {
        title: Llm::PromptLabel.collapse((article["title"] || article[:title]).to_s),
        host: host_of(url)
      }
    end
  end

  def host_of(url)
    URI.parse(url).host.to_s.sub(/\Awww\./, "").presence || url
  rescue URI::InvalidURIError
    url
  end
end
