# frozen_string_literal: true

require "uri"

# @lat: [[news-article-evidence#Discovery request receipt]]
# @lat: [[news-source-configuration#Matching evidence]]
class BillNewsArticleFetchService
  MAX_NEWS_ARTICLES = 5
  MAX_TITLE_CHARS = 300
  MAX_CITED_TEXT_CHARS = 150
  MAX_DIAGNOSTICS_ENTRIES = 20
  MAX_DIAGNOSTIC_STRING_CHARS = 250
  GENERIC_LOCALE_SINGLE_WORDS = %w[city council state states united america country both general].freeze
  GENERIC_ISSUE_WORDS = %w[
    bill ordinance concerning relative section act law code resolution amendment
    report order policy program general public state states city council committee
    credits share shares grant grants loan loans service services fund funds
    property properties tax taxes agreement project projects issue issues
    measure measures debate session
  ].freeze

  def self.call(*args, requested_by: nil, discovery_request: nil, search_client: nil, **kwargs)
    resolved_bill = kwargs[:bill] || args.first
    new(bill: resolved_bill, requested_by: requested_by, discovery_request: discovery_request, search_client: search_client).call
  end

  def initialize(bill:, requested_by: nil, discovery_request: nil, search_client: nil)
    @bill = bill
    @requested_by = requested_by
    @discovery_request = discovery_request
    @search_client = search_client || BraveSearch::Client.new
  end

  def call
    validate_actor_and_bill!

    receipt = nil
    begin
      locale_doc = SwayLocale::DocumentReader.current_for(bill.sway_locale)
      receipt = find_or_initialize_receipt(locale_doc: locale_doc)

      unless BraveSearch::Client.configured?
        receipt.update!(
          status: "unsupported",
          match_counts: {"direct" => 0, "context" => 0, "ambiguous" => 0, "unmatched" => 0},
          diagnostics: [{"error" => "Brave Search API key (BRAVE_SEARCH_API_KEY) is not configured", "timestamp" => Time.current.iso8601}],
          completed_at: Time.current
        )
        return receipt
      end

      sources = locale_doc.news_sources
      if sources.empty?
        receipt.update!(
          status: "no_matches",
          match_counts: {"direct" => 0, "context" => 0, "ambiguous" => 0, "unmatched" => 0},
          diagnostics: [{"message" => "Locale has no configured news sources or news discovery is disabled", "timestamp" => Time.current.iso8601}],
          completed_at: Time.current
        )
        return receipt
      end

      execute_search_and_attach(receipt: receipt, sources: sources)
    rescue KeyError => e
      raise e
    rescue BraveSearch::Client::Error, Llm::TransportError, Faraday::Error, StandardError => e
      handle_failure(receipt || discovery_request, e)
    end
  end

  private

  attr_reader :bill, :requested_by, :discovery_request, :search_client

  def validate_actor_and_bill!
    raise ArgumentError, "bill must be a persisted Bill" unless bill.is_a?(Bill) && bill.persisted?

    admin = requested_by
    raise ArgumentError, "requested_by must be a Sway admin" unless admin
    raise ArgumentError, "requested_by must be a Sway admin" unless admin.is_a?(User) && admin.respond_to?(:is_sway_admin?) && admin.is_sway_admin?

    if discovery_request
      raise ArgumentError, "discovery_request must be a persisted NewsArticleDiscoveryRequest" unless discovery_request.is_a?(NewsArticleDiscoveryRequest) && discovery_request.persisted?
      raise ArgumentError, "discovery_request does not belong to bill" unless discovery_request.bill_id == bill.id
      raise ArgumentError, "discovery_request does not belong to requested_by" unless discovery_request.requested_by_id == admin&.id
    end
  end

  def find_or_initialize_receipt(locale_doc:)
    query_str = build_search_query
    if discovery_request
      discovery_request.update!(
        status: "running",
        source_config_digest: locale_doc.source_config_digest,
        provider: BraveSearch::Client::PROVIDER_NAME,
        model: BraveSearch::Client::MODEL_NAME,
        query: query_str,
        match_counts: {"direct" => 0, "context" => 0, "ambiguous" => 0, "unmatched" => 0},
        diagnostics: [],
        completed_at: nil
      )
      discovery_request
    else
      NewsArticleDiscoveryRequest.create!(
        bill: bill,
        requested_by: requested_by,
        status: "running",
        source_config_digest: locale_doc.source_config_digest,
        provider: BraveSearch::Client::PROVIDER_NAME,
        model: BraveSearch::Client::MODEL_NAME,
        query: query_str,
        match_counts: {"direct" => 0, "context" => 0, "ambiguous" => 0, "unmatched" => 0},
        diagnostics: []
      )
    end
  end

  def execute_search_and_attach(receipt:, sources:)
    allowed_domains = extract_allowed_domains(sources)
    query = receipt.query.presence || build_search_query

    raw_candidates = search_client.search(
      query: query,
      allowed_domains: allowed_domains
    )

    counts = {"direct" => 0, "context" => 0, "ambiguous" => 0, "unmatched" => 0}
    diagnostics = []
    seen_canonical_urls = Set.new

    Array(raw_candidates).each do |candidate|
      process_candidate(
        candidate: candidate,
        sources: sources,
        counts: counts,
        diagnostics: diagnostics,
        seen_canonical_urls: seen_canonical_urls
      )
    end

    final_status = (counts["direct"] + counts["context"]).positive? ? "succeeded" : "no_matches"

    receipt.update!(
      status: final_status,
      match_counts: counts,
      diagnostics: diagnostics,
      completed_at: Time.current
    )
    receipt
  end

  def handle_failure(receipt, error)
    sanitized_msg = BraveSearch::Client.redact_api_key(
      Sway::Utf8.scrub(error.message.to_s).delete("\u0000")
    ).strip[0, MAX_DIAGNOSTIC_STRING_CHARS]
    formatted_error = BraveSearch::Client.redact_api_key(
      Sway::Utf8.scrub("#{error.class}: #{error.message}").delete("\u0000")
    ).strip[0, MAX_DIAGNOSTIC_STRING_CHARS]
    reported_error = scrub_exception_for_reporting(error)

    if receipt&.persisted?
      current_diag = Array(receipt.diagnostics).dup
      err_entry = {
        "error" => formatted_error,
        "timestamp" => Time.current.iso8601
      }
      if current_diag.size >= MAX_DIAGNOSTICS_ENTRIES
        current_diag[MAX_DIAGNOSTICS_ENTRIES - 1] = err_entry
      else
        current_diag << err_entry
      end

      receipt.update!(
        status: "failed",
        diagnostics: current_diag,
        completed_at: Time.current
      )

      SwayLogging.error(
        "bill_news_article_fetch.failed",
        bill_id: bill.id,
        discovery_request_id: receipt.id,
        provider: receipt.provider,
        model: receipt.model,
        error_class: error.class.name,
        error_message: sanitized_msg
      )
      Sentry.capture_exception(
        reported_error,
        extra: {
          bill_id: bill.id,
          discovery_request_id: receipt.id,
          provider: receipt.provider,
          model: receipt.model
        }.compact
      )
      receipt
    else
      Sentry.capture_exception(reported_error, extra: {bill_id: bill&.id}.compact)
      raise error
    end
  end

  def scrub_exception_for_reporting(error)
    raw_msg = error.message.to_s
    clean_msg = BraveSearch::Client.redact_api_key(Sway::Utf8.scrub(raw_msg).delete("\u0000"))
    return error if clean_msg == raw_msg

    scrubbed = begin
      error.class.new(clean_msg)
    rescue ArgumentError, TypeError
      RuntimeError.new("#{error.class}: #{clean_msg}")
    end
    backtrace = error.backtrace
    scrubbed.set_backtrace(backtrace) if backtrace
    scrubbed
  end

  def extract_allowed_domains(sources)
    sources.filter_map do |s|
      uri = URI.parse(s["url"].to_s)
      host = uri.host&.downcase&.sub(/\Awww\./, "")
      host.presence
    rescue URI::InvalidURIError
      nil
    end.uniq
  end

  def add_diagnostic(diagnostics, entry)
    return if diagnostics.size >= MAX_DIAGNOSTICS_ENTRIES

    sanitized_entry = entry.transform_values do |val|
      case val
      when String
        Sway::Utf8.scrub(val).strip[0, MAX_DIAGNOSTIC_STRING_CHARS]
      else
        val
      end
    end
    diagnostics << sanitized_entry
  end

  def process_candidate(candidate:, sources:, counts:, diagnostics:, seen_canonical_urls: Set.new)
    return unless candidate.is_a?(Hash)

    raw_url = (candidate["url"] || candidate[:url]).to_s.strip
    uri = parse_valid_https_uri(raw_url)
    if uri.nil?
      counts["unmatched"] += 1
      add_diagnostic(diagnostics, {"url" => raw_url, "reason" => "invalid_https_url"})
      return
    end

    candidate_host = uri.host&.downcase&.sub(/\Awww\./, "")
    if candidate_host.blank?
      counts["unmatched"] += 1
      add_diagnostic(diagnostics, {"url" => raw_url, "reason" => "invalid_https_url"})
      return
    end

    matching_sources = sources.select do |s|
      source_uri = URI.parse(s["url"].to_s)
      source_host = source_uri.host&.downcase&.sub(/\Awww\./, "")
      source_host == candidate_host
    rescue URI::InvalidURIError
      false
    end

    if matching_sources.empty?
      counts["unmatched"] += 1
      add_diagnostic(diagnostics, {"url" => raw_url, "reason" => "unconfigured_host", "host" => candidate_host})
      return
    end

    unless path_policy_allowed?(uri: uri, matching_sources: matching_sources)
      counts["unmatched"] += 1
      add_diagnostic(diagnostics, {"url" => raw_url, "reason" => "path_policy_violation", "path" => uri.path})
      return
    end

    canonical_url = SwayLocale::DocumentReader.normalize_news_source_url(raw_url)
    return if seen_canonical_urls.include?(canonical_url)

    seen_canonical_urls << canonical_url

    kind, evidence = classify_candidate(candidate)

    case kind
    when "direct", "context"
      attached_count = counts["direct"] + counts["context"]
      if attached_count < MAX_NEWS_ARTICLES
        counts[kind] += 1
        attach_candidate(candidate, match_kind: kind, match_evidence: evidence)
      else
        add_diagnostic(
          diagnostics,
          {
            "url" => raw_url,
            "title" => (candidate["title"] || candidate[:title]).to_s[0, MAX_TITLE_CHARS],
            "reason" => "candidate_capacity_exceeded",
            "kind" => kind,
            "message" => "Matched #{kind} candidate excluded because maximum capacity of #{MAX_NEWS_ARTICLES} articles was reached"
          }
        )
      end
    when "ambiguous"
      counts["ambiguous"] += 1
      add_diagnostic(
        diagnostics,
        {
          "url" => raw_url,
          "title" => (candidate["title"] || candidate[:title]).to_s[0, MAX_TITLE_CHARS],
          "reason" => evidence,
          "kind" => "ambiguous"
        }
      )
    else
      counts["unmatched"] += 1
      add_diagnostic(
        diagnostics,
        {
          "url" => raw_url,
          "title" => (candidate["title"] || candidate[:title]).to_s[0, MAX_TITLE_CHARS],
          "reason" => evidence,
          "kind" => "unmatched"
        }
      )
    end
  end

  def parse_valid_https_uri(url)
    return nil if url.blank?

    uri = URI.parse(url)
    return nil unless uri.is_a?(URI::HTTPS) && uri.host.present?
    return nil if uri.user.present? || uri.password.present?

    uri
  rescue URI::InvalidURIError, ArgumentError
    nil
  end

  def path_policy_allowed?(uri:, matching_sources:)
    return true if matching_sources.any? { |s| s["path_policy"] == "search_hint" }

    cand_path = uri.path.presence || "/"
    matching_sources.any? do |s|
      next false unless s["path_policy"] == "restrict"

      source_path = URI.parse(s["url"]).path.presence || "/"
      cand_path == source_path || cand_path.start_with?(source_path.chomp("/") + "/")
    rescue URI::InvalidURIError
      false
    end
  end

  def classify_candidate(candidate)
    explicit_kind = (candidate["match_kind"] || candidate[:match_kind])&.to_s
    raw_title = (candidate["title"] || candidate[:title]).to_s
    raw_cited = (candidate["cited_text"] || candidate[:cited_text]).to_s
    raw_url = (candidate["url"] || candidate[:url]).to_s
    raw_published_at = (candidate["published_at"] || candidate[:published_at]).to_s
    title = Sway::Utf8.scrub(raw_title).delete("\u0000")
    cited = Sway::Utf8.scrub(raw_cited).delete("\u0000")[0, MAX_CITED_TEXT_CHARS]
    combined = "#{title} #{cited}".downcase
    session_text = "#{combined} #{Sway::Utf8.scrub(raw_url).downcase} #{Sway::Utf8.scrub(raw_published_at).downcase}"

    session_years = valid_session_years
    locale_terms = determine_locale_terms

    has_conflicting_session = conflicting_session?(combined, session_years)

    if explicit_kind == "unmatched"
      default_evidence = (candidate["cited_text"] || candidate[:cited_text]).presence || "Unmatched candidate"
      return ["unmatched", (candidate["match_evidence"] || candidate[:match_evidence]).presence || default_evidence]
    elsif explicit_kind == "ambiguous"
      default_evidence = (candidate["cited_text"] || candidate[:cited_text]).presence || "Ambiguous match"
      return ["ambiguous", (candidate["match_evidence"] || candidate[:match_evidence]).presence || default_evidence]
    end

    has_bill_id = bill_id_matches?(combined)
    has_locale = locale_terms.any? { |term| combined.include?(term) }
    has_session = (session_text.scan(/\b(20\d\d)\b/).flatten.uniq & session_years).any?
    has_issue = issue_matches_bill?(combined)
    has_leg_body = legislative_body_terms.any? { |term| combined.include?(term) }

    direct_valid = has_bill_id && has_locale && has_session && !has_conflicting_session
    if direct_valid
      default_ev = "Direct match on bill #{bill.external_id}, jurisdiction, and session #{session_years.join("/")}"
      return ["direct", (candidate["match_evidence"] || candidate[:match_evidence]).presence || (candidate["cited_text"] || candidate[:cited_text]).presence || default_ev]
    end

    if explicit_kind == "direct"
      if has_conflicting_session
        return ["ambiguous", "Mentions topic or legislation but references a conflicting session"]
      elsif has_bill_id
        return ["ambiguous", "References bill identifier without verifiable current session grounding"]
      elsif has_locale && has_issue
        return ["ambiguous", "References topic without bill identifier required for direct match"]
      elsif has_leg_body
        return ["ambiguous", "Mentions legislative topic without conclusive session and bill grounding"]
      else
        return ["unmatched", "Off-topic or general discussion without legislative grounding"]
      end
    end

    context_valid = has_locale && has_issue && !has_conflicting_session
    if context_valid
      default_ev = "Context match on local issue and jurisdiction grounded in bill"
      return ["context", (candidate["match_evidence"] || candidate[:match_evidence]).presence || (candidate["cited_text"] || candidate[:cited_text]).presence || default_ev]
    end

    if explicit_kind == "context"
      if has_conflicting_session
        return ["ambiguous", "Mentions topic or legislation but references a conflicting session"]
      elsif has_bill_id
        return ["ambiguous", "References bill identifier without verifiable current session grounding"]
      elsif has_leg_body
        return ["ambiguous", "Mentions legislative topic without conclusive session and bill grounding"]
      else
        return ["unmatched", "Off-topic or general discussion without legislative grounding"]
      end
    end

    if has_bill_id
      if has_conflicting_session
        ["ambiguous", "Mentions topic or legislation but references a conflicting session"]
      else
        ["ambiguous", "References bill identifier without verifiable current session grounding"]
      end
    elsif has_locale && has_issue
      if has_conflicting_session
        ["ambiguous", "Mentions topic or legislation but references a conflicting session"]
      else
        ["context", (candidate["match_evidence"] || candidate[:match_evidence]).presence || (candidate["cited_text"] || candidate[:cited_text]).presence || "Context match on local issue and jurisdiction grounded in bill"]
      end
    elsif has_leg_body
      ["ambiguous", "Mentions legislative topic without conclusive session and bill grounding"]
    else
      ["unmatched", "Off-topic or general discussion without legislative grounding"]
    end
  end

  def bill_id_matches?(text)
    bill_id_str = bill.external_id.to_s.strip.downcase
    return false if bill_id_str.blank?
    return true if text.include?(bill_id_str)

    if (m = bill_id_str.match(/\A(sb|hb|sj|hj)[\s-]*0*(\d+)\z/))
      prefix = m[1]
      num = m[2]
      return true if text.match?(/\b#{Regexp.escape(prefix.to_s)}[\s.-]*0*#{Regexp.escape(num.to_s)}\b/)

      expanded = case prefix
      when "sb" then "senate bill"
      when "hb" then "house bill"
      when "sj" then "senate joint resolution"
      when "hj" then "house joint resolution"
      end
      return true if expanded && text.match?(/\b#{Regexp.escape(expanded)}\s+0*#{Regexp.escape(num.to_s)}\b/)
    elsif (m = bill_id_str.match(/\A(?:\d+-)?(hr|s|hjres|sjres)[\s-]*0*(\d+)\z/))
      prefix = m[1]
      num = m[2]
      pattern = case prefix
      when "hr" then /\bh\.?\s*r\.?[\s-]*0*#{Regexp.escape(num.to_s)}\b/
      when "s" then /\bs\.?[\s-]*0*#{Regexp.escape(num.to_s)}\b/
      else /\b#{Regexp.escape(prefix.to_s)}[\s.-]*0*#{Regexp.escape(num.to_s)}\b/
      end
      return true if text.match?(pattern)
    end

    false
  end

  def valid_session_years
    years = []
    session = bill.legislative_session
    if session && session.start_date.present? && session.end_date.present?
      start_y = session.start_date.to_date.year
      end_y = session.end_date.to_date.year
      years.concat((start_y..end_y).map(&:to_s))
    end
    if bill.introduced_date_time_utc
      years << bill.introduced_date_time_utc.to_date.year.to_s
    end
    if bill.external_id =~ /\A(\d{2})-\d+/
      years << "20#{$1}"
    end
    (years.presence || %w[2024 2025 2026 2027 2028]).uniq
  end

  def determine_locale_terms
    locale = bill.sway_locale
    return [] unless locale

    terms = []

    [locale.city, locale.region_name].each do |comp|
      next if comp.blank?

      normalized = comp.to_s.downcase.tr("_", " ").strip
      terms << normalized
      terms.concat(normalized.split(/\s+/)) if normalized.include?(" ")
    end

    rules = locale.declared_jurisdiction_rules
    if rules
      if rules.chamber_label.present?
        label = rules.chamber_label.to_s.downcase.strip
        terms << label
        terms.concat(label.split(/\s+/)) if label.include?(" ")
      end
      if rules.bill_chambers.present?
        terms.concat(rules.bill_chambers.map { |c| c.to_s.downcase.strip })
      end
    end

    if locale.congress?
      terms.concat(["congress", "capitol", "federal", "u.s. congress", "united states congress"])
    end

    terms.map(&:strip).reject { |t| t.length < 3 || GENERIC_LOCALE_SINGLE_WORDS.include?(t) }.uniq
  end

  def legislative_body_terms
    body_terms = %w[legislation ordinance]
    locale = bill.sway_locale
    if locale
      rules = locale.declared_jurisdiction_rules
      if rules
        body_terms << rules.chamber_label.to_s.downcase.strip if rules.chamber_label.present?
        body_terms.concat(rules.bill_chambers.map { |c| c.to_s.downcase.strip }) if rules.bill_chambers.present?
      end
      if locale.congress?
        body_terms.concat(%w[congress house senate])
      end
    end
    body_terms.map(&:presence).compact.reject { |t| t == "both" }.uniq
  end

  def conflicting_session?(text, valid_years)
    return false if valid_years.blank?

    found_years = text.scan(/\b(20\d\d)\b/).flatten.uniq
    found_years.any? && (found_years & valid_years).empty?
  end

  def issue_matches_bill?(text)
    return false if text.blank? || bill.title.blank?

    title_clean = bill.title.to_s.downcase.gsub(/[^a-z0-9\s]/, " ")
    raw_tokens = title_clean.scan(/\b[a-z]{3,}\b/)
    stopwords = %w[for and the of in on to with from by an about concerning relative section bill ordinance]
    substantive_tokens = raw_tokens - stopwords

    return false if substantive_tokens.empty?

    title_phrases = []
    substantive_tokens.each_cons(2) do |w1, w2|
      title_phrases << "#{w1} #{w2}"
    end
    return true if title_phrases.any? { |phrase| text.include?(phrase) }

    non_generic_tokens = substantive_tokens.reject do |token|
      GENERIC_ISSUE_WORDS.include?(token) || token.length < 4
    end
    return true if non_generic_tokens.any? { |token| text.include?(token.to_s) }

    matching_tokens = substantive_tokens.select { |token| text.include?(token.to_s) }.uniq
    matching_tokens.size >= 2
  end

  def attach_candidate(candidate, match_kind:, match_evidence:)
    canonical_url = SwayLocale::DocumentReader.normalize_news_source_url(candidate["url"] || candidate[:url])
    article = NewsArticle.find_or_initialize_by(canonical_url: canonical_url)

    raw_title = (candidate["title"] || candidate[:title]).to_s
    clean_title = Llm::UntrustedTextBlock.neutralize(Sway::Utf8.scrub(raw_title).delete("\u0000"))[0, MAX_TITLE_CHARS].presence || "Untitled Article"

    if article.new_record?
      article.title = clean_title
      article.outlet_name = (candidate["outlet_name"] || candidate[:outlet_name]).presence || infer_outlet_name(canonical_url)
      article.published_at = candidate["published_at"] || candidate[:published_at]
      article.author_name = candidate["author_name"] || candidate[:author_name]
      article.article_kind = (candidate["article_kind"] || candidate[:article_kind]).presence || "reporting"
      article.save!
    end

    bna = BillNewsArticle.find_or_initialize_by(bill: bill, news_article: article)
    clean_evidence = Llm::UntrustedTextBlock.neutralize(Sway::Utf8.scrub(match_evidence.to_s).delete("\u0000"))[0, MAX_CITED_TEXT_CHARS]
    if bna.new_record?
      bna.approved = false
      bna.review_version = 0
      bna.stance = nil
      bna.stance_version = 0
      bna.match_kind = match_kind
      bna.match_evidence = clean_evidence
      bna.save!
    elsif bna.match_evidence.blank?
      bna.update!(match_evidence: clean_evidence)
    end
    bna
  end

  def infer_outlet_name(canonical_url)
    host = URI.parse(canonical_url).host.to_s.downcase.sub(/\Awww\./, "")
    case host
    when /thebaltimorebanner|thebanner/
      "The Baltimore Banner"
    when /baltimoresun/
      "The Baltimore Sun"
    when /wypr/
      "WYPR"
    else
      host.split(".").first.to_s.titleize
    end
  rescue URI::InvalidURIError
    "News Outlet"
  end

  def build_search_query
    clean_title = Llm::UntrustedTextBlock.neutralize(Sway::Utf8.scrub(bill.title.to_s).delete("\u0000"))
    parts = [bill.external_id, clean_title, bill.sway_locale&.name].compact_blank
    parts.join(" ").strip
  end
end
