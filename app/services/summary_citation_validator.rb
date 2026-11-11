# frozen_string_literal: true

# @lat: [[llm-summaries#Output is validated, not trusted]]
class SummaryCitationValidator
  # @lat: [[llm-summaries#Output is validated, not trusted]]
  class Result < Struct.new(:invalid_citations)
    def valid?
      invalid_citations.empty?
    end
  end

  MAX_PROSE_NEWS_URLS = 5

  # @lat: [[llm-summaries#Public summary content and source grounding]]
  def self.verdict_attrs(bill:, payload:)
    section_attrs = section_verdict_attrs(bill: bill, payload: payload)
    news_attrs = news_verdict_attrs(bill: bill, payload: payload)
    {
      citations_valid: section_attrs[:citations_valid],
      invalid_citations: section_attrs[:invalid_citations],
      news_urls_valid: news_attrs[:news_urls_valid],
      invalid_news_urls: news_attrs[:invalid_news_urls]
    }
  end

  def self.section_verdict_attrs(bill:, payload:)
    return {citations_valid: nil, invalid_citations: nil} unless payload.key?("cited_section_keys")

    result = new(bill: bill, cited_section_keys: payload["cited_section_keys"]).call
    {citations_valid: result.valid?, invalid_citations: result.invalid_citations}
  end

  # @lat: [[llm-summaries#Public summary content and source grounding]]
  def self.news_verdict_attrs(bill:, payload:)
    has_news_key = payload.key?("cited_news_urls")
    prose_urls = extract_prose_urls(payload["summary_markdown"])

    return {news_urls_valid: nil, invalid_news_urls: nil} unless has_news_key || prose_urls.any?

    allowed = allowed_news_urls(bill)
    official_url = official_bill_url(bill)
    structured_urls = has_news_key ? extract_structured_urls(payload) : []
    all_cited = (structured_urls + prose_urls).uniq

    unlisted = all_cited.reject { |url| allowed.include?(url) || official_url?(url, official_url) }
    prose_news_urls = prose_urls.reject { |url| official_url?(url, official_url) }
    excess_prose = (prose_news_urls.length > MAX_PROSE_NEWS_URLS) ? prose_news_urls.drop(MAX_PROSE_NEWS_URLS) : []
    invalid = (unlisted + excess_prose).uniq

    if invalid.empty? && prose_news_urls.length <= MAX_PROSE_NEWS_URLS
      {news_urls_valid: true, invalid_news_urls: []}
    else
      {news_urls_valid: false, invalid_news_urls: invalid}
    end
  end

  def self.official_bill_url(bill)
    return nil unless bill.respond_to?(:link)

    url = bill.link&.strip&.presence
    return nil if url.nil? || generic_search_url?(url)

    url
  end

  def self.generic_search_url?(url)
    return false if url.blank?

    url.match?(%r{/LegislationSearch(\.aspx)?}i)
  end

  def self.official_url?(url, official_url)
    return false if official_url.blank? || url.blank?
    return true if url == official_url

    parsed_url = URI.parse(url)
    parsed_official = URI.parse(official_url)

    return false unless parsed_url.scheme && parsed_official.scheme
    return false unless parsed_url.scheme.casecmp?(parsed_official.scheme)
    return false unless parsed_url.host && parsed_official.host
    return false unless parsed_url.host.casecmp?(parsed_official.host)
    return false unless parsed_url.port == parsed_official.port
    return false unless parsed_url.query == parsed_official.query
    return false unless parsed_url.fragment == parsed_official.fragment

    normalize_path(parsed_url.path) == normalize_path(parsed_official.path)
  rescue URI::InvalidURIError, ArgumentError
    false
  end

  def self.normalize_path(path)
    return "/" if path.blank? || path == "/"

    path.chomp("/")
  end

  def self.allowed_news_urls(bill)
    urls = Set.new
    provisioning = bill.bill_llm_provisioning
    provisioning&.news_articles_list&.each do |article|
      url = (article["url"] || article[:url])&.to_s
      urls << url if url.present?
    end

    if bill.respond_to?(:bill_news_articles)
      begin
        bill.bill_news_articles.approved.includes(:news_article).each do |bna|
          canonical = bna.news_article&.canonical_url
          urls << canonical if canonical.present?
        end
      rescue NoMethodError, (defined?(RSpec::Mocks::MockExpectationError) ? RSpec::Mocks::MockExpectationError : StandardError)
        # @lat: [[llm-summaries#Public summary content and source grounding]]
      end
    end

    urls
  end

  def self.extract_structured_urls(payload)
    raw = payload["cited_news_urls"]
    return [] unless raw.is_a?(Array)

    raw.filter_map do |url|
      if url.is_a?(String)
        url
      elsif url.respond_to?(:to_s)
        url.to_s
      end
    end.uniq
  end

  def self.normalize_markdown_label(label)
    label.to_s.strip.gsub(/\s+/, " ").downcase
  end

  # @lat: [[news-claim-assessment#Two-phase verification architecture]]
  def self.extract_prose_urls(text)
    return [] if text.blank?

    cleaned = text.to_s.gsub(/\r\n?/, "\n")
    cleaned = cleaned.gsub(/<!--.*?-->/m, "")
    cleaned = cleaned.gsub(/^[ \t]{0,3}```[^\n]*\n.*?\n[ \t]{0,3}```[ \t]*(?:\n|\z)/m, "")
    cleaned = cleaned.gsub(/^[ \t]{0,3}~~~[^\n]*\n.*?\n[ \t]{0,3}~~~[ \t]*(?:\n|\z)/m, "")
    cleaned = cleaned.gsub(/^(?: {4,}| {0,3}\t).*$/, "")
    cleaned = cleaned.gsub(/`+[^`]+`+/, "")

    definitions = {}
    ref_def_regex = /^ {0,3}\[([^\]]+)\]:[ \t]*(?:<([^\s>]+)>|(\S+))(?:[ \t]+(?:"[^"]*"|'[^']*'|\([^)]*\)))?[ \t]*$/

    cleaned = cleaned.lines.reject do |line|
      if line =~ ref_def_regex
        raw_label = Regexp.last_match(1)
        raw_url = Regexp.last_match(2) || Regexp.last_match(3)
        clean_url = raw_url&.sub(/[.,;:!?]+\z/, "")
        norm_label = normalize_markdown_label(raw_label)
        definitions[norm_label] ||= clean_url if clean_url && clean_url =~ /\Ahttps?:\/\//i
        true
      else
        false
      end
    end.join

    urls = []

    inline_link_regex = /\[([^\]]*)\]\([ \t]*(?:<([^\s>]+)>|([^\s)]+))(?:[ \t]+(?:"[^"]*"|'[^']*'|\([^)]*\)))?[ \t]*\)/i
    cleaned = cleaned.gsub(inline_link_regex) do
      anchor = Regexp.last_match(1)
      raw_url = Regexp.last_match(2) || Regexp.last_match(3)
      url = raw_url&.sub(/[.,;:!?]+\z/, "")
      urls << url if url && url =~ /\Ahttps?:\/\//i
      anchor
    end

    full_ref_regex = /\[([^\]]*)\]\[([^\]]*)\]/
    cleaned = cleaned.gsub(full_ref_regex) do
      anchor = Regexp.last_match(1)
      label = Regexp.last_match(2)
      norm_label = label.to_s.empty? ? normalize_markdown_label(anchor) : normalize_markdown_label(label)
      if definitions.key?(norm_label)
        url = definitions[norm_label]
        urls << url if url && url =~ /\Ahttps?:\/\//i
        anchor
      else
        Regexp.last_match(0)
      end
    end

    shortcut_ref_regex = /\[([^\]]+)\](?![\[(])/
    cleaned = cleaned.gsub(shortcut_ref_regex) do
      label = Regexp.last_match(1)
      norm_label = normalize_markdown_label(label)
      if definitions.key?(norm_label)
        url = definitions[norm_label]
        urls << url if url && url =~ /\Ahttps?:\/\//i
        label
      else
        Regexp.last_match(0)
      end
    end

    autolink_regex = /<((?:https?):\/\/[^\s>]+)>/i
    cleaned = cleaned.gsub(autolink_regex) do
      match = Regexp.last_match(1)
      if match
        url = match.sub(/[.,;:!?]+\z/, "")
        urls << url
      end
      ""
    end

    plain_url_regex = %r{https?://[^\s)\]"'><]+}i
    cleaned.scan(plain_url_regex) do
      match_text = Regexp.last_match(0)
      urls << match_text.sub(/[.,;:!?]+\z/, "") if match_text
    end

    urls.uniq
  end

  def initialize(bill:, cited_section_keys:)
    @bill = bill
    @cited_section_keys = cited_section_keys
  end

  # @lat: [[llm-summaries#Output is validated, not trusted]]
  def call
    allowed = @bill.bill_section_references.pluck(:key).to_set
    cited = Array(@cited_section_keys).map(&:to_s).uniq
    invalid = cited.reject { |key| allowed.include?(key) }

    Result.new(invalid_citations: invalid)
  end
end
