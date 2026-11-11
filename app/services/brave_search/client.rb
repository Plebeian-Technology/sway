# frozen_string_literal: true

module BraveSearch
  # @lat: [[llm-summaries#LLM bill summaries#Output is validated, not trusted#Cited local news reporting and domain-restricted web search#Pre-summarization search and article persistence]]
  class Client
    class Error < StandardError; end

    PROVIDER_NAME = "brave_search"
    MODEL_NAME = "web_search"
    SEARCH_PATH = "/res/v1/web/search"
    MAX_QUERY_CHARS = 400
    MAX_QUERY_WORDS = 50
    MAX_BASE_QUERY_CHARS = 160
    MAX_BASE_QUERY_WORDS = 20
    MAX_COUNT = 20
    MAX_CITED_TEXT_CHARS = 150

    def self.configured?
      EnvSecret.read("BRAVE_SEARCH_API_KEY").present?
    end

    def self.redact_api_key(text)
      scrubbed = SwayLogging.redact_anthropic_key(text.to_s)
      key = EnvSecret.read("BRAVE_SEARCH_API_KEY")
      if key.present?
        scrubbed.gsub(key, "[FILTERED]")
      else
        scrubbed
      end
    end

    def initialize(connection: nil)
      @connection = connection || Sway::FaradayStack.brave_search
    end

    def search(query:, allowed_domains:, count: MAX_COUNT)
      base_query = sanitize_base_query(query)
      return [] if base_query.empty?

      domains = normalize_allowed_domains(allowed_domains)
      return [] if domains.empty?

      batches = partition_batches(base_query, domains)
      return [] if batches.empty?

      api_key = EnvSecret.brave_search_api_key!
      clamped_count = count.to_i.clamp(1, MAX_COUNT)
      candidates = []
      seen_canonical_urls = Set.new

      batches.each do |batch|
        batch_query = format_batch_query(base_query, batch)
        batch_candidates = execute_batch(batch_query, clamped_count, api_key)

        batch_candidates.each do |candidate|
          canonical_url = SwayLocale::DocumentReader.normalize_news_source_url(candidate["url"])
          if seen_canonical_urls.add?(canonical_url)
            candidates << candidate
          end
        end
      end

      candidates
    end

    private

    def sanitize_base_query(query)
      clean = Sway::Utf8.scrub(query.to_s).delete("\u0000").strip
      return "" if clean.empty?

      words = clean.gsub(/\s+/, " ").split(" ").first(MAX_BASE_QUERY_WORDS)
      return "" if words.blank?

      words.join(" ")[0, MAX_BASE_QUERY_CHARS].to_s.strip
    end

    def normalize_allowed_domains(allowed_domains)
      return [] unless allowed_domains.is_a?(Enumerable)

      normalized = allowed_domains.filter_map do |domain|
        d_str = domain.to_s.strip
        next if d_str.empty?

        Llm::AllowedDomain.from_url("https://#{d_str.sub(%r{\Ahttps?://}i, "")}")
      end.uniq

      normalized.first(Llm::AllowedDomain::MAX_ALLOWED_DOMAINS)
    end

    def format_batch_query(base_query, domains)
      if domains.size == 1
        "#{base_query} site:#{domains.first}"
      else
        "#{base_query} (#{domains.map { |d| "site:#{d}" }.join(" OR ")})"
      end
    end

    def query_within_limits?(query_str)
      query_str.length <= MAX_QUERY_CHARS && query_str.split(/\s+/).size <= MAX_QUERY_WORDS
    end

    def partition_batches(base_query, domains)
      batches = []
      current_batch = []

      domains.each do |domain|
        candidate_batch = current_batch + [domain]
        candidate_query = format_batch_query(base_query, candidate_batch)

        if query_within_limits?(candidate_query)
          current_batch = candidate_batch
        else
          batches << current_batch if current_batch.any?
          single_query = format_batch_query(base_query, [domain])
          current_batch = query_within_limits?(single_query) ? [domain] : []
        end
      end

      batches << current_batch if current_batch.any?
      batches
    end

    def execute_batch(batch_query, count, api_key)
      response = begin
        @connection.get(
          SEARCH_PATH,
          {q: batch_query, count: count},
          {"X-Subscription-Token" => api_key}
        )
      rescue Faraday::Error => e
        raise wrap_error(e)
      end

      if response.status < 200 || response.status >= 300
        raise wrap_error(nil, status: response.status, body: response.body)
      end

      parsed = begin
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise wrap_error(e)
      end

      extract_candidates(parsed)
    end

    def extract_candidates(parsed)
      return [] unless parsed.is_a?(Hash)

      web = parsed["web"]
      return [] unless web.is_a?(Hash)

      results = web["results"]
      return [] unless results.is_a?(Array)

      candidates = []
      results.each do |item|
        next unless item.is_a?(Hash)

        url = item["url"].to_s.strip
        next if url.empty?

        title = item["title"].to_s.strip
        description = item["description"].to_s.strip
        extra_snippets = Array(item["extra_snippets"]).map(&:to_s).map(&:strip).reject(&:empty?)
        snippet = extra_snippets.first

        cited_text = [description, snippet].compact.reject(&:empty?).join(" ")[0, MAX_CITED_TEXT_CHARS] || ""

        published_at = (item["page_age"] || item["age"]).to_s.strip.presence
        profile = item["profile"]
        outlet_name = (profile.is_a?(Hash) ? profile["name"] : nil).to_s.strip.presence

        candidates << {
          "url" => url,
          "title" => title,
          "cited_text" => cited_text,
          "published_at" => published_at,
          "outlet_name" => outlet_name
        }.compact
      end

      candidates
    end

    def wrap_error(exception, status: nil, body: nil)
      if status
        body_str = self.class.redact_api_key(Sway::Utf8.scrub(body.to_s).strip)
        message = if body_str.empty?
          "Brave Search API HTTP #{status}"
        else
          "Brave Search API HTTP #{status}: #{body_str}"
        end
        Error.new(message)
      else
        redacted_message = self.class.redact_api_key(Sway::Utf8.scrub(exception.message))
        Error.new("#{exception.class}: #{redacted_message}")
      end
    end
  end
end
