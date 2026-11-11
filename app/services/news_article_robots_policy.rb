# frozen_string_literal: true

require "resolv"
require "ipaddr"
require "uri"
require "faraday"
require "nokogiri"

# @lat: [[news-article-evidence#Immutable article text]]
# @lat: [[news-text#Robots exclusion policy enforcement]]
# @lat: [[outbound-fetch-safety#Every redirect hop is checked before it is followed]]
# @lat: [[outbound-fetch-safety#An oversized download is stopped rather than refused afterwards]]
class NewsArticleRobotsPolicy
  MAX_ROBOTS_BYTES = 512 * 1024
  MAX_REDIRECTS = 3
  OPEN_TIMEOUT_SECONDS = 5
  READ_TIMEOUT_SECONDS = 5
  DEFAULT_CACHE_TTL = 86_400.0
  MAX_CACHE_ENTRIES = 500

  Verdict = Struct.new(:allowed, :refusal_reason, :message)
  class Verdict
    def allowed?
      allowed == true
    end

    def reason
      refusal_reason
    end
  end
  CheckResult = Verdict

  Rule = Struct.new(:type, :pattern, :regexp, :length)
  UserAgentGroup = Struct.new(:agents, :rules)
  CacheEntry = Struct.new(:policy, :cached_at, :expires_at)
  class CacheEntry
    def expired?(now = Time.current.to_f)
      now >= expires_at
    end
  end

  @cache = {}
  @cache_mutex = Mutex.new

  class << self
    def check(uri, deadline: nil, user_agent: NewsArticleTextFetchService::USER_AGENT)
      uri = URI.parse(uri) if uri.is_a?(String)
      origin = "#{uri.scheme}://#{uri.host}:#{uri.port}"
      policy = get_or_fetch_policy(origin, uri, deadline: deadline, user_agent: user_agent)
      return policy if policy.is_a?(Verdict)

      policy.check_uri(uri, user_agent: user_agent)
    end

    def allowed?(uri, deadline: nil, user_agent: NewsArticleTextFetchService::USER_AGENT)
      check(uri, deadline: deadline, user_agent: user_agent).allowed?
    end

    def reset_cache!
      @cache_mutex.synchronize { @cache.clear }
    end

    private

    def get_or_fetch_policy(origin, uri, deadline:, user_agent:)
      now = Time.current.to_f
      cached = @cache_mutex.synchronize do
        entry = @cache[origin]
        if entry && !entry.expired?(now)
          entry.policy
        else
          @cache.delete(origin)
          nil
        end
      end

      return cached if cached

      fresh_policy = fetch_origin_policy(origin, uri, deadline: deadline, user_agent: user_agent)
      if fresh_policy.is_a?(NewsArticleRobotsPolicy)
        @cache_mutex.synchronize do
          @cache.shift if @cache.size >= MAX_CACHE_ENTRIES
          @cache[origin] = CacheEntry.new(
            policy: fresh_policy,
            cached_at: now,
            expires_at: now + DEFAULT_CACHE_TTL.to_f
          )
        end
      end
      fresh_policy
    end

    def fetch_origin_policy(origin, target_uri, deadline:, user_agent:)
      robots_url = "#{origin}/robots.txt"
      current_url = robots_url

      (MAX_REDIRECTS + 1).times do |hop|
        if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          return Verdict.new(allowed: false, refusal_reason: :robots_inaccessible, message: "Robots deadline exceeded")
        end

        uri = begin
          URI.parse(current_url)
        rescue URI::Error
          nil
        end

        unless uri.is_a?(URI::HTTPS) && uri.port == 443
          return Verdict.new(allowed: false, refusal_reason: :robots_unsafe_destination, message: "Robots URL must be HTTPS on port 443")
        end

        unless NewsArticleTextFetchService.safe_destination?(uri)
          return Verdict.new(allowed: false, refusal_reason: :robots_unsafe_destination, message: "Robots destination unsafe: #{uri.host}")
        end

        response, body = fetch_http_robots(uri, deadline: deadline, user_agent: user_agent)

        if response.nil? || body.nil? || !response.is_a?(Faraday::Response)
          return Verdict.new(allowed: false, refusal_reason: :robots_inaccessible, message: "Robots fetch failed or timed out")
        end

        if (300..399).cover?(response.status)
          if hop >= MAX_REDIRECTS
            return Verdict.new(allowed: false, refusal_reason: :robots_redirect_limit_exceeded, message: "Robots redirect limit exceeded")
          end

          location = response.headers["location"].to_s.presence
          if location.nil?
            return Verdict.new(allowed: false, refusal_reason: :robots_inaccessible, message: "Robots redirect missing location header")
          end

          next_url = begin
            URI.join(current_url, location).to_s
          rescue URI::Error, ArgumentError
            nil
          end

          if next_url.nil?
            return Verdict.new(allowed: false, refusal_reason: :robots_inaccessible, message: "Robots invalid redirect location: #{location}")
          end

          current_url = next_url
          next
        end

        if response.status == 404 || response.status == 410
          if NewsArticleTextFetchService.challenge_indicator?(body)
            return Verdict.new(allowed: false, refusal_reason: :robots_challenged, message: "Robots challenge screen detected")
          end

          if paywall_or_login_barrier?(body)
            return Verdict.new(allowed: false, refusal_reason: :robots_inaccessible, message: "Robots access screen or HTML detected")
          end

          return new(origin: origin, groups: [], absent: true)
        elsif [401, 403, 429].include?(response.status)
          return Verdict.new(allowed: false, refusal_reason: :robots_inaccessible, message: "Robots HTTP #{response.status}")
        elsif response.status >= 500
          return Verdict.new(allowed: false, refusal_reason: :robots_server_error, message: "Robots HTTP #{response.status}")
        elsif response.status != 200
          return Verdict.new(allowed: false, refusal_reason: :robots_inaccessible, message: "Robots HTTP #{response.status}")
        end

        if NewsArticleTextFetchService.challenge_indicator?(body)
          return Verdict.new(allowed: false, refusal_reason: :robots_challenged, message: "Robots challenge screen detected")
        end

        if html_response?(response, body) || paywall_or_login_barrier?(body)
          return Verdict.new(allowed: false, refusal_reason: :robots_inaccessible, message: "Robots access screen or HTML detected")
        end

        groups = parse_robots_txt(body)
        return new(origin: origin, groups: groups, absent: false)
      end

      Verdict.new(allowed: false, refusal_reason: :robots_redirect_limit_exceeded, message: "Robots redirect limit exceeded")
    end

    def fetch_http_robots(uri, deadline:, user_agent:)
      remaining = deadline ? [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0.1].max : READ_TIMEOUT_SECONDS
      open_t = [remaining, OPEN_TIMEOUT_SECONDS].min
      read_t = [remaining, READ_TIMEOUT_SECONDS].min

      conn = Faraday.new do |f|
        f.options.open_timeout = open_t
        f.options.timeout = read_t
        f.headers["User-Agent"] = user_agent
        f.headers["Accept"] = "text/plain, text/*;q=0.9, */*;q=0.1"
        f.adapter Faraday.default_adapter
      end

      bounded_body = BoundedResponseBody.new(
        limit: MAX_ROBOTS_BYTES,
        deadline: deadline,
        max_elapsed: READ_TIMEOUT_SECONDS,
        description: "robots.txt body"
      )

      response = conn.get(uri.to_s) do |req|
        req.options.on_data = proc do |chunk, overall_bytes, env|
          status = env.status.to_i
          is_redirect = (300..399).cover?(status)
          bounded_body.receive(chunk, overall_bytes, keep: !is_redirect)
        end
      end

      content_length = response.headers["content-length"].to_s
      if content_length.match?(/\A\d+\z/) && content_length.to_i > MAX_ROBOTS_BYTES
        return [nil, nil]
      end

      buf = bounded_body.buffer
      body = buf.empty? ? response.body.to_s : buf
      [response, body]
    rescue BoundedResponseBody::TooLarge
      buf = bounded_body ? bounded_body.buffer : ""
      body = buf.empty? ? response&.body.to_s : buf
      [response, body]
    rescue => e
      class_name = e.class.name
      cause_class_name = e.cause&.class&.name
      if class_name == "WebMock::NetConnectNotAllowedError" ||
          cause_class_name == "WebMock::NetConnectNotAllowedError" ||
          class_name == "VCR::Errors::UnhandledHTTPRequestError" ||
          cause_class_name == "VCR::Errors::UnhandledHTTPRequestError"
        target_error = (cause_class_name == "WebMock::NetConnectNotAllowedError" || cause_class_name == "VCR::Errors::UnhandledHTTPRequestError") ? e.cause : e
        raise target_error
      end

      SwayLogging.warn("NewsArticleRobotsPolicy fetch failed: #{e.class}: #{e.message}")
      [nil, nil]
    end

    def html_response?(response, body)
      content_type = response.headers["content-type"].to_s.downcase
      if content_type.present? && !content_type.include?("text/plain")
        if content_type.include?("text/html") ||
            content_type.include?("application/xhtml+xml") ||
            content_type.include?("application/xml") ||
            content_type.include?("application/json") ||
            content_type.include?("application/pdf")
          return true
        end
      end

      html_document?(body)
    end

    def html_document?(body)
      str = body.to_s.strip
      return false if str.empty?

      return true if str.match?(/\A\s*<!doctype\s+html/i)
      return true if str.match?(/\A\s*<html/i)
      return true if str.match?(/\A\s*<head/i)
      return true if str.match?(/\A\s*<body/i)
      return true if str.match?(/\A\s*<\?xml/i)
      return true if str.match?(/\A\s*<title/i)
      return true if str.match?(/<html[^>]*>|<body[^>]*>|<title[^>]*>/i)
      return true if str.match?(/<(?:div|form|p|h[1-6]|main|article|section|table|script|style|nav|header|footer)\b[^>]*>/i)

      false
    end

    def paywall_or_login_barrier?(body)
      str = body.to_s
      return false if str.blank?

      return true if str.match?(NewsArticleTextFetchService::PAYWALL_PHRASES)

      if str.match?(/<title[^>]*>([^<]+)<\/title>/i)
        title_text = Regexp.last_match(1).to_s.strip
        return true if title_text.match?(NewsArticleTextFetchService::LOGIN_TITLE_PATTERNS)
      end

      doc = Nokogiri::HTML(str)

      title_node = doc.at_css("title")
      if title_node && title_node.text.strip.match?(NewsArticleTextFetchService::LOGIN_TITLE_PATTERNS)
        return true
      end

      return true if doc.at_css("input[type='password'], input[name*='password']").present?

      has_auth_form = doc.css("form").any? do |f|
        action = f["action"].to_s.downcase
        action.match?(/login|signin|auth|session/) ||
          f.text.match?(/sign in|log in|subscriber|welcome back/i)
      end
      return true if has_auth_form && (doc.at_css("input[type='password'], input[name*='password']").present? || doc.text.match?(/sign in|log in|password|subscriber/i))

      has_login_heading = doc.css("h1, h2, h3, h4, h5, h6").any? do |h|
        h_text = h.text.strip
        h_text.match?(NewsArticleTextFetchService::LOGIN_TITLE_PATTERNS) ||
          h_text.match?(/\A\s*(sign\s*in|log\s*in|login|subscriber\s*sign\s*in|subscriber\s*login|account\s*sign\s*in|account\s*login|sign\s*in\s*to\s*your\s*account|log\s*in\s*to\s*your\s*account)(\s*[-|–—:].*)?\z/i)
      end
      return true if has_login_heading

      has_login_button = doc.css("button, input[type='submit']").any? do |b|
        val = b["value"].to_s.strip.presence || b.text.strip
        val.match?(/\A\s*(sign\s*in|log\s*in|login)\s*\z/i)
      end
      return true if has_login_button && (doc.at_css("form").present? || doc.at_css("input").present?)

      return true if doc.at_css(NewsArticleTextFetchService::PAYWALL_SELECTORS).present?
      return true if doc.at_css(NewsArticleTextFetchService::CHALLENGE_SELECTORS).present?

      false
    end

    def parse_robots_txt(content)
      groups = []
      current_agents = []
      current_rules = []
      in_rules = false

      normalized_content = normalize_robots_content(content)

      normalized_content.each_line do |line|
        clean_line = line.split("#", 2).first.to_s.strip
        next if clean_line.blank?

        parts = clean_line.split(":", 2)
        next unless parts.size == 2

        field = parts[0].strip.downcase
        value = parts[1].strip

        case field
        when "user-agent"
          next if value.blank?

          if in_rules
            groups << UserAgentGroup.new(agents: current_agents.dup, rules: current_rules.dup) if current_agents.any?
            current_agents.clear
            current_rules.clear
            in_rules = false
          end
          current_agents << value.downcase unless current_agents.include?(value.downcase)
        when "allow"
          next if current_agents.empty?

          in_rules = true
          next if value.blank?

          rule = compile_rule(:allow, value)
          current_rules << rule if rule
        when "disallow"
          next if current_agents.empty?

          in_rules = true
          next if value.blank?

          rule = compile_rule(:disallow, value)
          current_rules << rule if rule
        end
      end

      if current_agents.any?
        groups << UserAgentGroup.new(agents: current_agents, rules: current_rules)
      end

      groups
    end

    def normalize_robots_content(content)
      str = content.to_s.dup.force_encoding(Encoding::UTF_8).scrub
      str = str.delete_prefix("\uFEFF")
      str.gsub(/\r\n?/, "\n")
    end

    def compile_rule(type, pattern)
      pattern = "/#{pattern}" unless pattern.start_with?("/") || pattern.empty?
      has_end_anchor = pattern.end_with?("$")
      pat_body = (has_end_anchor ? pattern[0...-1] : pattern) || ""

      normalized_parts = pat_body.split("*", -1).map do |part|
        normalize_percent_encoding(part)
      end

      escaped_parts = normalized_parts.map do |part|
        Regexp.escape(part)
      end

      regex_str = "\\A" + escaped_parts.join(".*")
      regex_str += "\\z" if has_end_anchor

      normalized_pattern = normalized_parts.join("*") + (has_end_anchor ? "$" : "")

      Rule.new(
        type: type,
        pattern: pattern,
        regexp: Regexp.new(regex_str),
        length: normalized_pattern.bytesize
      )
    rescue RegexpError
      nil
    end

    def normalize_percent_encoding(str)
      return "" if str.nil?

      normalized = str.to_s.gsub(/%([0-9a-fA-F]{2})/) do |match|
        byte = Regexp.last_match(1).to_i(16)
        if byte.between?(0x30, 0x39) ||
            byte.between?(0x41, 0x5A) ||
            byte.between?(0x61, 0x7A) ||
            byte == 0x2D || byte == 0x2E || byte == 0x5F || byte == 0x7E
          byte.chr(Encoding::ASCII_8BIT)
        else
          match.upcase
        end
      end

      normalized.bytes.map do |b|
        if b >= 0x80
          format("%%%02X", b)
        else
          b.chr(Encoding::ASCII_8BIT)
        end
      end.join.force_encoding(Encoding::UTF_8)
    end
  end

  attr_reader :origin, :groups, :absent

  def initialize(origin:, groups:, absent: false)
    @origin = origin
    @groups = groups
    @absent = absent
  end

  def check_uri(uri, user_agent: NewsArticleTextFetchService::USER_AGENT)
    return Verdict.new(allowed: true, refusal_reason: nil, message: "Robots file absent") if absent
    return Verdict.new(allowed: true, refusal_reason: nil, message: "Robots file implicitly allowed") if uri.path == "/robots.txt"

    target_path = uri.path.presence || "/"
    target_path += "?#{uri.query}" if uri.query.present?
    target_path = self.class.send(:normalize_percent_encoding, target_path)

    rules = resolve_rules_for(user_agent)
    return Verdict.new(allowed: true, refusal_reason: nil, message: "No matching rules for user agent") if rules.empty?

    matching_rules = rules.select { |r| r.regexp.match?(target_path) }
    return Verdict.new(allowed: true, refusal_reason: nil, message: "No matching rules for path") if matching_rules.empty?

    max_len = matching_rules.map(&:length).max
    tied_rules = matching_rules.select { |r| r.length == max_len }

    winning_rule = tied_rules.find { |r| r.type == :allow } || tied_rules.first
    if winning_rule.type == :allow
      Verdict.new(allowed: true, refusal_reason: nil, message: "Allowed by rule: #{winning_rule.pattern}")
    else
      Verdict.new(allowed: false, refusal_reason: :robots_disallowed, message: "Disallowed by rule: #{winning_rule.pattern}")
    end
  end

  private

  def resolve_rules_for(user_agent)
    token = extract_product_token(user_agent).downcase

    specific_groups = groups.select do |g|
      g.agents.any? { |a| matches_token?(a, token) }
    end
    return specific_groups.flat_map(&:rules) if specific_groups.any?

    wildcard_groups = groups.select { |g| g.agents.include?("*") }
    return wildcard_groups.flat_map(&:rules) if wildcard_groups.any?

    []
  end

  def matches_token?(agent_pattern, token)
    agent_pattern = agent_pattern.downcase.split("/").first.to_s.strip
    return false if agent_pattern == "*"

    agent_pattern == token
  end

  def extract_product_token(user_agent)
    user_agent.to_s.split("/").first.to_s.strip
  end
end
