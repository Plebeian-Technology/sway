# frozen_string_literal: true

# @lat: [[news-article-evidence#Grounding decisions]]
class NewsClaimGroundingService
  # @lat: [[news-article-evidence#Grounding decisions]]
  class ClaimAssessment
    attr_reader :claim_text, :evidence_excerpt, :citation_url,
      :bill_news_article_id, :text_version_id,
      :verdict, :reason, :phase, :source_use_record

    alias_attribute :status, :verdict

    def initialize(
      claim_text:,
      evidence_excerpt:,
      citation_url:,
      bill_news_article_id:,
      text_version_id:,
      verdict:,
      reason:,
      phase:,
      source_use_record: nil
    )
      @claim_text = claim_text
      @evidence_excerpt = evidence_excerpt
      @citation_url = citation_url
      @bill_news_article_id = bill_news_article_id
      @text_version_id = text_version_id
      @verdict = verdict
      @reason = reason
      @phase = phase
      @source_use_record = source_use_record
    end

    def supported?
      verdict == "supported"
    end

    def unsupported?
      verdict == "unsupported"
    end

    def indeterminate?
      verdict == "indeterminate"
    end
  end

  # @lat: [[news-article-evidence#Grounding decisions]]
  class Result
    attr_reader :verdict, :claim_assessments, :deterministic_errors, :route, :prompt_version

    alias_method :status, :verdict
    alias_method :grounding_status, :verdict
    alias_method :claim_results, :claim_assessments
    alias_method :verdicts, :claim_assessments

    def initialize(
      verdict:,
      claim_assessments: [],
      deterministic_errors: [],
      route: nil,
      prompt_version: nil
    )
      @verdict = verdict
      @claim_assessments = claim_assessments
      @deterministic_errors = deterministic_errors
      @route = route
      @prompt_version = prompt_version
    end

    def supported?
      verdict == "supported" || verdict == "none"
    end

    def unsupported?
      verdict == "unsupported"
    end

    def indeterminate?
      verdict == "indeterminate"
    end

    def none?
      verdict == "none"
    end

    def valid?
      supported?
    end

    def errors
      deterministic_errors + claim_assessments.reject(&:supported?).map(&:reason)
    end
  end

  def self.call(
    bill:,
    content: nil,
    text: nil,
    source_uses: nil,
    snapshot: nil,
    news_usage: nil,
    persist: false,
    route: nil,
    adapter: nil,
    model: nil
  )
    new(
      bill: bill,
      content: (content || text).to_s,
      source_uses: source_uses,
      snapshot: snapshot,
      news_usage: news_usage,
      persist: persist,
      route: route,
      adapter: adapter,
      model: model
    ).call
  end

  class << self
    alias_method :assess, :call
  end

  def initialize(
    bill:,
    content:,
    source_uses: nil,
    snapshot: nil,
    news_usage: nil,
    persist: false,
    route: nil,
    adapter: nil,
    model: nil
  )
    @bill = bill
    @content = content.to_s
    @raw_source_uses = source_uses
    @snapshot = snapshot
    @news_usage = news_usage
    @persist = persist
    @route = route
    @adapter = adapter
    @model = model
  end

  def call
    normalized_uses = extract_normalized_source_uses
    prose_news_urls = extract_prose_news_urls

    news_usage_str = news_usage&.to_s

    if news_usage_str.present? && !%w[none cited].include?(news_usage_str)
      return Result.new(
        verdict: "unsupported",
        deterministic_errors: ["Missing or invalid news_usage declaration: #{news_usage.inspect}"]
      )
    end

    if news_usage_str == "none"
      if prose_news_urls.any?
        return Result.new(
          verdict: "unsupported",
          deterministic_errors: ["Declared no-news usage but content contains visible news citations: #{prose_news_urls.join(", ")}"]
        )
      end

      if normalized_uses.empty?
        return Result.new(
          verdict: "none",
          deterministic_errors: [],
          claim_assessments: []
        )
      end

      return Result.new(
        verdict: "unsupported",
        deterministic_errors: ["Declared no-news usage but source-use manifest is not empty"]
      )
    end

    manifest_urls = normalized_uses.pluck(:citation_url).compact.uniq

    if normalized_uses.empty? && news_usage_str != "cited"
      return Result.new(
        verdict: "unsupported",
        deterministic_errors: ["Missing or invalid news_usage declaration: #{news_usage.inspect}"]
      )
    end

    if normalized_uses.empty? && prose_news_urls.empty?
      return Result.new(
        verdict: "unsupported",
        deterministic_errors: ["Declared cited news usage but source-use manifest is empty"]
      )
    end

    if prose_news_urls.any?
      unmanifested_urls = prose_news_urls.reject { |u| manifest_urls.include?(u) }
      url_errors = unmanifested_urls.filter_map { |u| validate_prose_url_deterministically(u) }
      if url_errors.any?
        return Result.new(
          verdict: "unsupported",
          deterministic_errors: url_errors
        )
      end
    end

    if normalized_uses.empty? && prose_news_urls.empty?
      return Result.new(
        verdict: "supported",
        claim_assessments: [],
        deterministic_errors: []
      )
    end

    deterministic_errors = []
    assessments = []
    semantic_queue = []

    normalized_uses.each do |item|
      check_result = validate_claim_deterministically(item)
      if check_result
        assessments << check_result
      else
        item[:candidate_prose] = candidate_news_prose_for_url(item[:citation_url]).join("\n\n")
        semantic_queue << item
      end
    end

    if assessments.none?(&:unsupported?) && deterministic_errors.empty?
      approved_by_url = @bill.bill_news_articles.includes(:news_article, :current_text_version).each_with_object({}) do |bna, map|
        canonical = bna.news_article&.canonical_url
        map[canonical] = bna if canonical.present? && bna.approved?
      end

      (manifest_urls | prose_news_urls).each do |url|
        candidate_sentences = candidate_news_prose_for_url(url)
        associated_uses = normalized_uses.select { |u| u[:citation_url] == url }
        first_use = associated_uses.first
        bna = approved_by_url[url]
        bna_id = first_use ? first_use[:bill_news_article_id] : bna&.id
        tv_id = first_use ? first_use[:text_version_id] : bna&.current_text_version_id
        tv = (first_use && first_use[:text_version_instance]) || (tv_id && NewsArticleTextVersion.find_by(id: tv_id)) || bna&.current_text_version
        next if bna_id.nil? || tv_id.nil?

        queued_for_url = false
        candidate_sentences.each do |sentence|
          clean_sentence = sentence
            .gsub(/\[(?:\s*source\s*|\s*link\s*|\s*citation\s*|\d+)\]\([^)]+\)/i, "")
            .gsub(/\[(?:\s*source\s*|\s*link\s*|\s*citation\s*|\d+)\]\[[^\]]*\]/i, "")
            .gsub(/\[([^\]]*)\]\([^)]+\)/, '\1')
            .gsub(/\[([^\]]*)\]\[[^\]]*\]/, '\1')
            .gsub(/<https?:\/\/[^\s>]+>/, "")
            .gsub(/https?:\/\/[^\s)\]"'><]+/, "")
            .strip
            .sub(/[.,;:!?]+\z/, "")
          next if clean_sentence.blank?

          is_mapped = associated_uses.any? do |u|
            normalized_claim = u[:claim_text].to_s.strip.sub(/[.,;:!?]+\z/, "")
            sentence.include?(u[:claim_text]) ||
              sentence.downcase.include?(u[:claim_text].downcase) ||
              (normalized_claim.present? && (clean_sentence.downcase.include?(normalized_claim.downcase) || normalized_claim.downcase.include?(clean_sentence.downcase)))
          end
          next if is_mapped

          omitted_item = {
            bill_news_article_id: bna_id,
            text_version_id: tv_id,
            claim_text: clean_sentence,
            evidence_excerpt: "",
            citation_url: url,
            record: nil,
            text_version_instance: tv,
            candidate_prose: candidate_sentences.join("\n\n")
          }
          semantic_queue << omitted_item
          queued_for_url = true
        end

        if associated_uses.empty? && !queued_for_url
          fallback_claim = candidate_sentences.join("\n\n").presence || content.strip
          if fallback_claim.present?
            semantic_queue << {
              bill_news_article_id: bna_id,
              text_version_id: tv_id,
              claim_text: fallback_claim,
              evidence_excerpt: "",
              citation_url: url,
              record: nil,
              text_version_instance: tv,
              candidate_prose: candidate_sentences.join("\n\n")
            }
          end
        end
      end
    end

    resolved_route_string = nil
    prompt_version = nil

    if assessments.any?(&:unsupported?) || deterministic_errors.any?
      # @lat: [[news-article-evidence#Grounding decisions]]
    elsif semantic_queue.any?
      resolved_route = @route || Llm::RouteResolver.resolve(purpose: :summary)
      resolved_route_string = "#{resolved_route.provider}/#{resolved_route.api_model}"
      prompt_version = Llm::NewsClaimGroundingPromptBuilder::PROMPT_VERSION

      effective_adapter = @adapter || Llm::Client.build(provider: resolved_route.provider.to_sym)
      effective_model = @model || resolved_route.api_model
      reasoning_effort = resolved_route&.reasoning_effort

      semantic_queue.each do |item|
        assessments << evaluate_claim_semantically(
          item: item,
          adapter: effective_adapter,
          model: effective_model,
          reasoning_effort: reasoning_effort
        )
      end
    end

    if @persist
      assessments.each do |assessment|
        record = assessment.source_use_record
        next unless record&.persisted?

        NewsArticleSourceUse.where(id: record.id).update_all(
          grounding_status: assessment.verdict,
          grounding_reason: assessment.reason,
          updated_at: Time.current
        )
        record.reload
      end
    end

    overall_verdict = aggregate_verdict(deterministic_errors, assessments)

    Result.new(
      verdict: overall_verdict,
      claim_assessments: assessments,
      deterministic_errors: deterministic_errors,
      route: resolved_route_string,
      prompt_version: prompt_version
    )
  end

  private

  attr_reader :bill, :content, :raw_source_uses, :snapshot, :news_usage

  def extract_normalized_source_uses
    sources = if raw_source_uses
      raw_source_uses.to_a
    elsif (snap = snapshot)
      snap.source_uses.to_a
    else
      []
    end

    sources.filter_map do |src|
      if src.is_a?(NewsArticleSourceUse)
        {
          bill_news_article_id: src.bill_news_article_id,
          text_version_id: src.text_version_id,
          claim_text: src.claim_text,
          evidence_excerpt: src.evidence_excerpt,
          citation_url: src.citation_url,
          record: src
        }
      elsif src.is_a?(Hash)
        h = src.with_indifferent_access
        {
          bill_news_article_id: h[:bill_news_article_id]&.to_i,
          text_version_id: h[:text_version_id]&.to_i,
          claim_text: h[:claim_text].to_s,
          evidence_excerpt: (h[:evidence_excerpt] || h[:verbatim_excerpt]).to_s,
          citation_url: h[:citation_url].to_s,
          record: nil
        }
      end
    end
  end

  def extract_prose_news_urls
    @extract_prose_news_urls ||= if content.blank?
      []
    else
      prose_urls = SummaryCitationValidator.extract_prose_urls(content)
      official_url = SummaryCitationValidator.official_bill_url(bill)

      prose_urls.reject do |url|
        SummaryCitationValidator.official_url?(url, official_url)
      end
    end
  end

  def validate_prose_url_deterministically(url)
    bna = bill.bill_news_articles.includes(:news_article, :current_text_version).find do |candidate|
      candidate.news_article&.canonical_url == url
    end

    if bna.nil?
      return "Citation URL #{url} does not belong to an approved news article for this bill"
    end

    unless bna.approved?
      return "Bill news article approval is false or has been withdrawn"
    end

    if bna.current_text_version_id.blank? || bna.current_text_version.nil?
      return "Bill news article #{bna.id} has no selected current text version"
    end

    tv = bna.current_text_version

    unless tv.usable_text?
      return "Text version is not usable text (extraction_status: #{tv.extraction_status})"
    end

    if (snap = snapshot)
      if snap.bill_id != bill.id
        return "Referenced snapshot does not belong to bill #{bill.id}"
      end

      captured_entry = snap.captured_source_entries.find do |entry|
        h = entry.respond_to?(:to_h) ? entry.to_h.stringify_keys : entry
        (h["bill_news_article_id"] || h[:bill_news_article_id])&.to_i == bna.id
      end

      if captured_entry.nil?
        return "Bill news article #{bna.id} is not present in referenced snapshot"
      end

      h_entry = captured_entry.respond_to?(:to_h) ? captured_entry.to_h.stringify_keys : captured_entry

      captured_tv_id = (h_entry["text_version_id"] || h_entry[:text_version_id] || h_entry["news_article_text_version_id"])&.to_i
      if captured_tv_id.nil? || captured_tv_id <= 0 || captured_tv_id != tv.id
        return "Text version #{tv.id} does not match captured snapshot text version #{captured_tv_id}"
      end

      captured_version = (h_entry["review_version"] || h_entry[:review_version])&.to_i
      if captured_version.present? && captured_version != bna.review_version
        return "Review version mismatch against snapshot: captured #{captured_version} != current #{bna.review_version}"
      end
    end

    nil
  end

  def validate_claim_deterministically(item)
    claim_text = item[:claim_text]
    evidence_excerpt = item[:evidence_excerpt]
    citation_url = item[:citation_url]
    bna_id = item[:bill_news_article_id]
    tv_id = item[:text_version_id]

    if claim_text.blank? || evidence_excerpt.blank? || citation_url.blank?
      return ClaimAssessment.new(
        claim_text: claim_text,
        evidence_excerpt: evidence_excerpt,
        citation_url: citation_url,
        bill_news_article_id: bna_id,
        text_version_id: tv_id,
        verdict: "unsupported",
        reason: "Claim text, evidence excerpt, and citation URL must be present",
        phase: :deterministic,
        source_use_record: item[:record]
      )
    end

    unless content.include?(claim_text)
      return ClaimAssessment.new(
        claim_text: claim_text,
        evidence_excerpt: evidence_excerpt,
        citation_url: citation_url,
        bill_news_article_id: bna_id,
        text_version_id: tv_id,
        verdict: "unsupported",
        reason: "Claim text does not appear in prose",
        phase: :deterministic,
        source_use_record: item[:record]
      )
    end

    unless extract_prose_news_urls.include?(citation_url)
      return ClaimAssessment.new(
        claim_text: claim_text,
        evidence_excerpt: evidence_excerpt,
        citation_url: citation_url,
        bill_news_article_id: bna_id,
        text_version_id: tv_id,
        verdict: "unsupported",
        reason: "Manifest citation URL #{citation_url} does not appear in visible prose",
        phase: :deterministic,
        source_use_record: item[:record]
      )
    end

    bna = bill.bill_news_articles.find_by(id: bna_id)
    if bna.nil?
      return ClaimAssessment.new(
        claim_text: claim_text,
        evidence_excerpt: evidence_excerpt,
        citation_url: citation_url,
        bill_news_article_id: bna_id,
        text_version_id: tv_id,
        verdict: "unsupported",
        reason: "Bill news article #{bna_id} does not belong to bill #{bill.id}",
        phase: :deterministic,
        source_use_record: item[:record]
      )
    end

    unless bna.approved?
      return ClaimAssessment.new(
        claim_text: claim_text,
        evidence_excerpt: evidence_excerpt,
        citation_url: citation_url,
        bill_news_article_id: bna_id,
        text_version_id: tv_id,
        verdict: "unsupported",
        reason: "Bill news article approval is false or has been withdrawn",
        phase: :deterministic,
        source_use_record: item[:record]
      )
    end

    article_canonical = bna.news_article&.canonical_url
    unless article_canonical.present? && article_canonical == citation_url
      return ClaimAssessment.new(
        claim_text: claim_text,
        evidence_excerpt: evidence_excerpt,
        citation_url: citation_url,
        bill_news_article_id: bna_id,
        text_version_id: tv_id,
        verdict: "unsupported",
        reason: "Citation URL #{citation_url} does not belong to referenced article",
        phase: :deterministic,
        source_use_record: item[:record]
      )
    end

    tv = NewsArticleTextVersion.find_by(id: tv_id)
    if tv.nil? || tv.news_article_id != bna.news_article_id
      return ClaimAssessment.new(
        claim_text: claim_text,
        evidence_excerpt: evidence_excerpt,
        citation_url: citation_url,
        bill_news_article_id: bna_id,
        text_version_id: tv_id,
        verdict: "unsupported",
        reason: "Text version does not belong to article",
        phase: :deterministic,
        source_use_record: item[:record]
      )
    end

    if bna.current_text_version_id.blank?
      return ClaimAssessment.new(
        claim_text: claim_text,
        evidence_excerpt: evidence_excerpt,
        citation_url: citation_url,
        bill_news_article_id: bna_id,
        text_version_id: tv_id,
        verdict: "unsupported",
        reason: "Bill news article #{bna_id} has no selected current text version",
        phase: :deterministic,
        source_use_record: item[:record]
      )
    end

    if tv.id != bna.current_text_version_id
      return ClaimAssessment.new(
        claim_text: claim_text,
        evidence_excerpt: evidence_excerpt,
        citation_url: citation_url,
        bill_news_article_id: bna_id,
        text_version_id: tv_id,
        verdict: "unsupported",
        reason: "Text version is not the current text version for article",
        phase: :deterministic,
        source_use_record: item[:record]
      )
    end

    unless tv.usable_text?
      return ClaimAssessment.new(
        claim_text: claim_text,
        evidence_excerpt: evidence_excerpt,
        citation_url: citation_url,
        bill_news_article_id: bna_id,
        text_version_id: tv_id,
        verdict: "unsupported",
        reason: "Text version is not usable text (extraction_status: #{tv.extraction_status})",
        phase: :deterministic,
        source_use_record: item[:record]
      )
    end

    if (snap = snapshot)
      if snap.bill_id != bill.id
        return ClaimAssessment.new(
          claim_text: claim_text,
          evidence_excerpt: evidence_excerpt,
          citation_url: citation_url,
          bill_news_article_id: bna_id,
          text_version_id: tv_id,
          verdict: "unsupported",
          reason: "Referenced snapshot does not belong to bill #{bill.id}",
          phase: :deterministic,
          source_use_record: item[:record]
        )
      end

      captured_entry = snap.captured_source_entries.find do |entry|
        h = entry.respond_to?(:to_h) ? entry.to_h.stringify_keys : entry
        (h["bill_news_article_id"] || h[:bill_news_article_id])&.to_i == bna.id
      end

      if captured_entry.nil?
        return ClaimAssessment.new(
          claim_text: claim_text,
          evidence_excerpt: evidence_excerpt,
          citation_url: citation_url,
          bill_news_article_id: bna_id,
          text_version_id: tv_id,
          verdict: "unsupported",
          reason: "Bill news article #{bna.id} is not present in referenced snapshot",
          phase: :deterministic,
          source_use_record: item[:record]
        )
      end

      h_entry = captured_entry.respond_to?(:to_h) ? captured_entry.to_h.stringify_keys : captured_entry

      captured_tv_id = (h_entry["text_version_id"] || h_entry[:text_version_id] || h_entry["news_article_text_version_id"])&.to_i
      if captured_tv_id.present? && captured_tv_id != tv.id
        return ClaimAssessment.new(
          claim_text: claim_text,
          evidence_excerpt: evidence_excerpt,
          citation_url: citation_url,
          bill_news_article_id: bna_id,
          text_version_id: tv_id,
          verdict: "unsupported",
          reason: "Text version #{tv.id} does not match captured snapshot text version #{captured_tv_id}",
          phase: :deterministic,
          source_use_record: item[:record]
        )
      end

      captured_version = (h_entry["review_version"] || h_entry[:review_version])&.to_i
      if captured_version.present? && captured_version != bna.review_version
        return ClaimAssessment.new(
          claim_text: claim_text,
          evidence_excerpt: evidence_excerpt,
          citation_url: citation_url,
          bill_news_article_id: bna_id,
          text_version_id: tv_id,
          verdict: "unsupported",
          reason: "Review version mismatch against snapshot: captured #{captured_version} != current #{bna.review_version}",
          phase: :deterministic,
          source_use_record: item[:record]
        )
      end
    end

    unless tv.text.to_s.include?(evidence_excerpt)
      return ClaimAssessment.new(
        claim_text: claim_text,
        evidence_excerpt: evidence_excerpt,
        citation_url: citation_url,
        bill_news_article_id: bna_id,
        text_version_id: tv_id,
        verdict: "unsupported",
        reason: "Evidence excerpt does not appear verbatim in article text version",
        phase: :deterministic,
        source_use_record: item[:record]
      )
    end

    item[:text_version_instance] = tv
    nil
  end

  def evaluate_claim_semantically(item:, adapter:, model:, reasoning_effort: nil)
    tv = item[:text_version_instance] || (item[:text_version_id] && NewsArticleTextVersion.find_by(id: item[:text_version_id]))
    raise "Missing text version for news claim grounding assessment" if tv.nil?

    prompt_builder = Llm::NewsClaimGroundingPromptBuilder.new(
      claim_text: item[:claim_text],
      evidence_excerpt: item[:evidence_excerpt],
      source_context: tv.text.to_s,
      candidate_prose: item[:candidate_prose]
    )

    grounding_kwargs = {}
    if reasoning_effort.present? && adapter.respond_to?(:provider_label) && adapter.provider_label == "openrouter"
      grounding_kwargs[:reasoning_effort] = reasoning_effort
    end

    begin
      payload = prompt_builder.build
      response = adapter.generate_news_claim_grounding(
        prompt: payload,
        model: model,
        schema: NEWS_CLAIM_GROUNDING_SCHEMA_HASH,
        **grounding_kwargs
      )

      verdict = response["verdict"].to_s
      reason = response["reason"].to_s

      unless %w[supported unsupported indeterminate].include?(verdict)
        reason = "Unrecognized grounding verdict returned: #{verdict.inspect}"
        verdict = "indeterminate"
      end

      ClaimAssessment.new(
        claim_text: item[:claim_text],
        evidence_excerpt: item[:evidence_excerpt],
        citation_url: item[:citation_url],
        bill_news_article_id: item[:bill_news_article_id],
        text_version_id: item[:text_version_id],
        verdict: verdict,
        reason: reason,
        phase: :semantic,
        source_use_record: item[:record]
      )
    rescue => e
      ClaimAssessment.new(
        claim_text: item[:claim_text],
        evidence_excerpt: item[:evidence_excerpt],
        citation_url: item[:citation_url],
        bill_news_article_id: item[:bill_news_article_id],
        text_version_id: item[:text_version_id],
        verdict: "indeterminate",
        reason: "Transport or schema error: #{e.message}",
        phase: :semantic,
        source_use_record: item[:record]
      )
    end
  end

  def aggregate_verdict(deterministic_errors, assessments)
    return "unsupported" if deterministic_errors.any?
    return "unsupported" if assessments.any?(&:unsupported?)
    return "indeterminate" if assessments.any?(&:indeterminate?)
    return "supported" if assessments.any? && assessments.all?(&:supported?)

    "indeterminate"
  end

  def candidate_news_prose_for_url(target_url)
    @candidate_news_prose_by_url ||= {}
    @candidate_news_prose_by_url[target_url] ||= extract_attributed_sentences_for_url(target_url)
  end

  def extract_attributed_sentences_for_url(target_url)
    return [] if content.blank?

    cleaned = content.to_s.gsub(/\r\n?/, "\n")
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
        norm_label = SummaryCitationValidator.normalize_markdown_label(raw_label)
        definitions[norm_label] ||= clean_url if clean_url && clean_url =~ /\Ahttps?:\/\//i
        true
      else
        false
      end
    end.join

    target_labels = definitions.select { |_, url| url == target_url }.keys
    paragraphs = cleaned.split(/\n{2,}/).map(&:strip).compact_blank

    matching_segments = []

    paragraphs.each do |para|
      chunks = para.split(/(?<=[.!?])\s+(?=[A-Z0-9"'(\[])|(?<=\))\s+(?=[A-Z0-9"'(\[])|(?<=\])\s+(?=[A-Z0-9"'(\[])/)

      merged = []
      chunks.each do |c|
        c_stripped = c.strip
        next if c_stripped.empty?

        if merged.any? && c_stripped =~ /\A(?:\[[^\]]+\](?:\([^)]+\)|\[[^\]]*\])?|<https?:\/\/[^\s>]+>)\.?\z/
          merged[-1] = "#{merged[-1]} #{c_stripped}"
        else
          merged << c_stripped
        end
      end

      merged.each do |sent|
        cites_target = false
        if sent.include?(target_url)
          cites_target = true
        elsif target_labels.any? { |lbl| sent =~ /\[[^\]]*\]\[\s*#{Regexp.escape(lbl)}\s*\]/i || sent =~ /\[\s*#{Regexp.escape(lbl)}\s*\]\[\s*\]/i || sent =~ /\[\s*#{Regexp.escape(lbl)}\s*\](?![\[(])/i }
          cites_target = true
        end

        matching_segments << sent if cites_target
      end
    end

    matching_segments
  end
end
