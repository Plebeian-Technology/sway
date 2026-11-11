# frozen_string_literal: true

require "resolv"
require "ipaddr"
require "uri"
require "nokogiri"

# @lat: [[news-article-evidence#Immutable article text]]
# @lat: [[news-text#News text acquisition]]
# @lat: [[news-text#Robots exclusion policy enforcement]]
# @lat: [[outbound-fetch-safety#Every redirect hop is checked before it is followed]]
# @lat: [[outbound-fetch-safety#An oversized download is stopped rather than refused afterwards]]
# @lat: [[outbound-fetch-safety#A declared size is checked as well as the bytes that arrive]]
# @lat: [[news-source-configuration#Matching evidence]]
class NewsArticleTextFetchService
  MAX_REDIRECTS = 3
  MAX_DOWNLOAD_BYTES = 2 * 1024 * 1024
  MAX_EXTRACTED_TEXT_CHARS = 50_000
  OPEN_TIMEOUT_SECONDS = 10
  READ_TIMEOUT_SECONDS = 15
  MAX_ELAPSED_SECONDS = 25
  MIN_TEXT_CHARS = 50
  USER_AGENT = "SwayCivic/1.0 (+https://sway.vote; news-retrieval)"

  BLOCKED_CIDR_RANGES = [
    IPAddr.new("0.0.0.0/8"),
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("100.64.0.0/10"),
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("169.254.0.0/16"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.0.0.0/24"),
    IPAddr.new("192.0.2.0/24"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("198.51.100.0/24"),
    IPAddr.new("203.0.113.0/24"),
    IPAddr.new("224.0.0.0/4"),
    IPAddr.new("240.0.0.0/4"),
    IPAddr.new("255.255.255.255/32"),
    IPAddr.new("::/128"),
    IPAddr.new("::1/128"),
    IPAddr.new("fc00::/7"),
    IPAddr.new("fe80::/10"),
    IPAddr.new("ff00::/8")
  ].freeze

  DISALLOWED_HOST_SUFFIXES = %w[
    .localhost
    .local
    .internal
    .lan
    .home
    .home.arpa
    .arpa
    .corp
    .localdomain
    .test
    .example
    .invalid
  ].freeze

  DISALLOWED_EXACT_HOSTS = %w[
    localhost
    home.arpa
    arpa
    host.docker.internal
    gateway.docker.internal
    host.containers.internal
    web
    home
    localdomain
    lan
    broadcasthost
  ].freeze

  CHALLENGE_SELECTORS = [
    "#cf-wrapper",
    "#cf-challenge-running",
    "#challenge-running",
    "#cf-please-wait",
    ".cf-browser-verification",
    ".cf-challenge",
    ".cf-turnstile",
    "#challenge-form",
    "#captcha-form",
    "#captcha-container",
    ".g-recaptcha",
    ".h-captcha",
    "#px-captcha",
    "#px-captcha-modal",
    ".px-captcha",
    "iframe[src*='challenges.cloudflare.com']",
    "iframe[src*='recaptcha']",
    "iframe[src*='hcaptcha']",
    "iframe[src*='perimeterx']",
    "[data-sitekey]"
  ].join(", ").freeze

  CHALLENGE_TITLE_PATTERNS = /\A(human verification|verify you are human|verifying you are human|just a moment\.\.\.|attention required!\s*\|\s*cloudflare|security check|bot verification|ddos-guard|shieldsquare captcha|please wait\.\.\.\s*\|\s*cloudflare|cloudflare|access denied)(\s*[-|–—:].*)?\z/i

  CHALLENGE_PHRASES = /cf-browser-verification|verify you are human|verifying you are human|confirm (?:that )?you are not a robot|confirm you(?:'re| are) (?:not a robot|human)|verify (?:that )?you are not a robot|human verification|(?:we are )?checking (?:your browser|if the site connection is secure)(?: before accessing(?: (?:this|now)(?: (?:page|website))?)?)?|verifying your browser|attention required!\s*\|\s*cloudflare|please wait while (?:your request is being verified|we verify(?: your browser)?)|please solve (?:this|the) captcha|complete the security check to (?:continue|access)|complete the security check|access to this page has been denied because we believe you are using automation tools|this process is automatic|(?:you will be |will be )?redirected to the requested (?:story|page|url|content)|(?:once|after) verification completes|please keep this window open|perimeterx/i

  PAYWALL_SELECTORS = [
    ".paywall",
    "#paywall",
    ".article-paywall",
    ".paywall-content",
    ".paywall-barrier",
    ".locked-body",
    "#locked-body",
    ".locked-content",
    ".subscriber-only",
    ".subscription-gate",
    ".metered-barrier",
    ".metered-wall",
    "[data-paywall='true']",
    "[data-locked='true']",
    "[data-subscriber-restricted='true']"
  ].join(", ").freeze

  PAYWALL_PHRASES = /subscribe to continue|subscription required|this (?:article|content) is for subscribers only|subscribers only|you(?:'ve| have) reached your (?:free )?(?:article |monthly )?limit|log in or subscribe|sign in or subscribe|unlock this (?:article|story) with a subscription|access your (?:digital )?subscription|enter your email (?:address )?and password to access/i

  LOGIN_TITLE_PATTERNS = /\A(sign\s*in|log\s*in|login|subscriber\s*sign\s*in|subscriber\s*login|account\s*sign\s*in|account\s*login|sign\s*in\s*to\s*your\s*account|log\s*in\s*to\s*your\s*account)(\s*[-|–—:].*)?\z/i

  class << self
    def call(bill_news_article: nil, news_article: nil, requested_url: nil, force: false)
      new(
        bill_news_article: bill_news_article,
        news_article: news_article,
        requested_url: requested_url,
        force: force
      ).call
    end

    def safe_destination?(uri)
      new.send(:safe_destination?, uri)
    end

    def challenge_indicator?(first_arg, second_arg = nil)
      new.send(:challenge_indicator?, first_arg, second_arg)
    end
  end

  def initialize(bill_news_article: nil, news_article: nil, requested_url: nil, force: false)
    @bill_news_article = bill_news_article
    @news_article = news_article || bill_news_article&.news_article
    @requested_url = requested_url || @news_article&.canonical_url
    @force = force
  end

  def call
    raise ArgumentError, "news_article or bill_news_article is required" if news_article.nil?
    raise ArgumentError, "requested_url is required" if requested_url.blank?

    status, text, final_url = execute_retrieval
    version = persist_version(status: status, text: text, final_url: final_url)
    link_association(version)
    version
  end

  private

  attr_reader :bill_news_article, :news_article, :requested_url, :force

  def execute_retrieval
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + MAX_ELAPSED_SECONDS
    current_url = requested_url

    (MAX_REDIRECTS + 1).times do |hop|
      return [:failed, nil, current_url] if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      uri = parse_uri(current_url)
      return [:failed, nil, current_url] unless uri.is_a?(URI::HTTPS)
      return [:failed, nil, current_url] unless valid_uri?(uri)
      return [:failed, nil, current_url] unless safe_destination?(uri)
      return [:failed, nil, current_url] unless allowed_by_path_policy?(uri)

      robots_result = NewsArticleRobotsPolicy.check(uri, deadline: deadline, user_agent: USER_AGENT)
      unless robots_result.allowed?
        SwayLogging.warn(
          "news_article_text_fetch.robots_refused",
          refusal_reason: robots_result.refusal_reason,
          news_article_id: news_article&.id,
          bill_id: bill_news_article&.bill_id,
          url: current_url
        )
        return [:failed, nil, current_url]
      end

      response, raw_body = fetch_http(uri, deadline)
      return [:failed, nil, current_url] if response.nil? || raw_body.nil?

      if (300..399).cover?(response.status)
        return [:failed, nil, current_url] if hop >= MAX_REDIRECTS

        location = response.headers["location"].to_s.presence
        return [:failed, nil, current_url] if location.nil?

        next_url = resolve_redirect_url(current_url, location)
        return [:failed, nil, current_url] if next_url.nil?

        current_url = next_url
        next
      end

      if challenge_indicator?(raw_body)
        SwayLogging.warn("NewsArticleTextFetchService access barrier detected: challenge page for #{current_url}")
        return [:failed, nil, current_url]
      elsif [401, 403, 451].include?(response.status)
        return [:paywalled, nil, current_url]
      elsif response.status != 200
        return [:failed, nil, current_url]
      end

      content_type = response.headers["content-type"].to_s.downcase
      unless content_type.include?("text/html") || content_type.include?("application/xhtml+xml")
        return [:failed, nil, current_url]
      end

      status, text = extract_text_and_enrich_metadata(raw_body)
      return [status, text, current_url]
    end

    [:failed, nil, current_url]
  rescue ArgumentError => e
    SwayLogging.warn("NewsArticleTextFetchService retrieval failed: #{e.class}: #{e.message}")
    [:failed, nil, current_url]
  end

  def parse_uri(url_str)
    URI.parse(url_str)
  rescue URI::Error
    nil
  end

  def valid_uri?(uri)
    return false unless uri.is_a?(URI::HTTPS)
    return false unless uri.port == 443
    return false if uri.user.present? || uri.password.present?

    true
  end

  def safe_destination?(uri)
    host = uri.host.to_s.downcase.strip
    return false if host.blank?
    return false if DISALLOWED_EXACT_HOSTS.include?(host)
    return false if DISALLOWED_HOST_SUFFIXES.any? { |suffix| host.end_with?(suffix) }
    return false if ip_literal?(host)
    return false unless host.include?(".")
    return false unless ip_safe?(host)

    true
  end

  def ip_literal?(host)
    clean_host = host.sub(/\A\[/, "").sub(/\]\z/, "").chomp(".")
    return true if clean_host.match?(/\A(0x[0-9a-fA-F]+|\d+)(\.(0x[0-9a-fA-F]+|\d+))*\z/i)
    return true if clean_host.include?(":")

    begin
      IPAddr.new(clean_host)
      true
    rescue IPAddr::InvalidAddressError
      false
    end
  end

  def ip_safe?(host)
    return false if DISALLOWED_EXACT_HOSTS.include?(host) || DISALLOWED_HOST_SUFFIXES.any? { |suffix| host.end_with?(suffix) }

    addresses = resolve_host(host)
    if addresses.empty?
      return !Rails.env.production?
    end

    addresses.none? { |addr| blocked_address?(addr) }
  end

  def resolve_host(host)
    Resolv.getaddresses(host)
  rescue Resolv::ResolvError, SocketError
    []
  end

  def blocked_address?(addr)
    ip = IPAddr.new(addr)
    ip.loopback? || ip.private? || ip.link_local? || BLOCKED_CIDR_RANGES.any? { |r| r.include?(ip) }
  rescue IPAddr::InvalidAddressError
    true
  end

  def allowed_by_path_policy?(uri)
    locale = bill_news_article&.sway_locale
    return false unless locale

    doc_reader = begin
      SwayLocale::DocumentReader.current_for(locale)
    rescue
      nil
    end
    return false unless doc_reader&.respond_to?(:news_sources)

    sources = doc_reader.news_sources
    return false if sources.blank?

    target_host = uri.host.to_s.downcase.sub(/\Awww\./, "")
    return false if target_host.blank?

    target_path = uri.path.presence || "/"

    matching_sources = sources.select do |source|
      s_uri = URI.parse((source["url"] || source[:url]).to_s)
      s_host = s_uri.host.to_s.downcase.sub(/\Awww\./, "")
      s_host.present? && s_host == target_host
    rescue URI::Error, ArgumentError
      false
    end

    return false if matching_sources.empty?

    matching_sources.any? do |source|
      policy = (source["path_policy"] || source[:path_policy]).to_s
      if policy == "search_hint"
        true
      elsif policy == "restrict"
        s_uri = URI.parse((source["url"] || source[:url]).to_s)
        source_path = s_uri.path.presence || "/"
        target_path == source_path ||
          target_path.chomp("/") == source_path.chomp("/") ||
          target_path.start_with?("#{source_path.chomp("/")}/")
      else
        false
      end
    rescue URI::Error, ArgumentError
      false
    end
  end

  def resolve_redirect_url(base_url, location)
    URI.join(base_url, location).to_s
  rescue URI::Error, ArgumentError
    nil
  end

  def fetch_http(uri, deadline)
    conn = Faraday.new do |f|
      f.options.open_timeout = OPEN_TIMEOUT_SECONDS
      f.options.timeout = READ_TIMEOUT_SECONDS
      f.headers["User-Agent"] = USER_AGENT
      f.headers["Accept"] = "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8"
      f.adapter Faraday.default_adapter
    end

    bounded_body = BoundedResponseBody.new(
      limit: MAX_DOWNLOAD_BYTES,
      deadline: deadline,
      max_elapsed: MAX_ELAPSED_SECONDS,
      description: "article body"
    )

    response = conn.get(uri.to_s) do |req|
      req.options.on_data = proc do |chunk, overall_bytes, env|
        status = env.status.to_i
        is_redirect = (300..399).cover?(status)
        bounded_body.receive(chunk, overall_bytes, keep: !is_redirect)
      end
    end

    content_length = response.headers["content-length"].to_s
    if content_length.match?(/\A\d+\z/) && content_length.to_i > MAX_DOWNLOAD_BYTES
      return [nil, nil]
    end

    status = response.status.to_i
    is_redirect = (300..399).cover?(status)
    is_blocked = [401, 403, 429, 451, 503].include?(status)
    content_type = response.headers["content-type"].to_s.downcase

    unless is_redirect || is_blocked || content_type.include?("text/html") || content_type.include?("application/xhtml+xml")
      return [nil, nil]
    end

    buf = bounded_body.buffer
    raw_body = buf.empty? ? response.body.to_s : buf
    [response, raw_body]
  rescue BoundedResponseBody::TooLarge, BoundedResponseBody::TimeoutTooSlow,
    Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::Error,
    Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError,
    ArgumentError => e
    SwayLogging.warn("NewsArticleTextFetchService fetch failed: #{e.class}: #{e.message}")
    [nil, nil]
  end

  def extract_text_and_enrich_metadata(raw_body)
    raw_body = Sway::Utf8.scrub(raw_body)
    doc = Nokogiri::HTML(raw_body)

    if challenge_indicator?(doc, raw_body)
      SwayLogging.warn("NewsArticleTextFetchService access barrier detected: challenge page for #{requested_url}")
      return [:failed, nil]
    end

    if paywall_indicator?(doc, raw_body)
      return [:paywalled, nil]
    end

    meta_updates = extract_article_metadata(doc)

    doc.css(
      "script, style, noscript, nav, header, footer, aside, form, svg, iframe, " \
      "button, input, select, textarea, [role='navigation'], [role='banner'], " \
      "[role='contentinfo'], [role='complementary'], .advertisement, .ad, " \
      ".social-share, .newsletter, .cookie-banner, .comments"
    ).remove

    container = doc.at_css("article") ||
      doc.at_css("[itemprop='articleBody']") ||
      doc.at_css("main") ||
      doc.at_css(".article-body, .story-body, .entry-content, .post-content, #article-body") ||
      doc.at_css("body")

    paragraphs = []
    container&.css("p, blockquote, h1, h2, h3, h4, h5, h6, li")&.each do |node|
      t = Sway::Utf8.scrub(node.text).delete("\u0000").gsub(/[ \t]+/, " ").strip
      next if t.blank?

      paragraphs << if node.name == "blockquote"
        "\"#{t.sub(/\A["']/, "").sub(/["']\z/, "")}\""
      else
        t
      end
    end

    clean_text = paragraphs.join("\n\n").strip
    if clean_text.blank? && container
      fallback = Sway::Utf8.scrub(container.text).delete("\u0000").gsub(/[ \t]+/, " ").strip
      clean_text = fallback if fallback.present?
    end

    clean_text = clean_text[0...MAX_EXTRACTED_TEXT_CHARS] if clean_text.present?

    if clean_text.blank? || clean_text.length < MIN_TEXT_CHARS
      [:failed, nil]
    else
      apply_article_metadata_updates(meta_updates)
      [:extracted, clean_text]
    end
  end

  def remove_peripheral_chrome(doc)
    cleaned = doc.dup
    cleaned.css(
      "head, footer, nav, header, .comments, .newsletter, .newsletter-signup, " \
      ".ad, .advertisement, .social-share, .cookie-banner, " \
      "[role='navigation'], [role='banner'], [role='contentinfo']"
    ).remove

    article_container_selector = "article, main, [itemprop='articleBody'], " \
      ".article-body, .story-body, .entry-content, .post-content, #article-body"

    cleaned.css("aside").each do |aside|
      is_peripheral = aside["class"].to_s.downcase.match?(/\b(newsletter|ad|advertisement|social|comments)\b/) ||
        aside["id"].to_s.downcase.match?(/\b(newsletter|ad|advertisement|social|comments)\b/)

      if is_peripheral
        aside.remove
        next
      end

      is_in_article = aside.ancestors(article_container_selector).any?
      next if is_in_article

      has_barrier = begin
        aside.matches?(PAYWALL_SELECTORS) ||
          aside.at_css(PAYWALL_SELECTORS).present? ||
          aside.matches?(CHALLENGE_SELECTORS) ||
          aside.at_css(CHALLENGE_SELECTORS).present? ||
          aside.css("h1, h2, h3, h4, h5, h6").any? do |h|
            h.text.strip.match?(/\A\s*(subscribe to continue|subscription required|choose your subscription|subscribers only|unlock this (?:article|story)|log in or subscribe|sign in or subscribe|subscriber sign in|subscriber login|human verification|verify you are human|verifying you are human|security check|bot verification)\s*\z/i)
          end
      rescue
        false
      end

      aside.remove unless has_barrier
    end

    cleaned
  end

  def challenge_indicator?(first_arg, second_arg = nil)
    doc, raw_body = normalize_doc_and_body(first_arg, second_arg)

    return false if raw_body.blank? && doc.nil?

    doc ||= Nokogiri::HTML(raw_body)
    title = doc.at_css("title")&.text.to_s.strip
    return true if title.match?(CHALLENGE_TITLE_PATTERNS)
    return true if doc.at_css("#cf-wrapper, #cf-challenge-running, #challenge-running, .cf-browser-verification, #challenge-form, #px-captcha-modal")

    content_doc = remove_peripheral_chrome(doc)
    return true if content_doc.at_css(CHALLENGE_SELECTORS)

    active_challenge_heading = content_doc.css("h1, h2, h3, h4, h5, h6").any? do |h|
      h.text.strip.match?(/\A\s*(human verification|verify you are human|verifying you are human|security check|bot verification|please solve (?:this|the) captcha|complete the security check)\s*\z/i) ||
        h.text.match?(CHALLENGE_TITLE_PATTERNS)
    end
    return true if active_challenge_heading

    has_challenge_form = content_doc.css("form").any? do |f|
      f["action"].to_s.downcase.match?(/verify|captcha|challenge/)
    end
    has_captcha_input = content_doc.css("input").any? do |inp|
      inp["name"].to_s.downcase.match?(/captcha|answer|challenge/)
    end
    has_puzzle_img = content_doc.css("img").any? do |img|
      img["src"].to_s.downcase.match?(/puzzle|captcha/) || img["alt"].to_s.downcase.match?(/verification|captcha/)
    end
    has_verify_btn = content_doc.css("button, input[type='submit']").any? { |b| b.text.strip.match?(/\A(verify|submit challenge)\z/i) }

    return true if has_challenge_form || has_captcha_input || has_puzzle_img
    return true if content_doc.text.match?(CHALLENGE_PHRASES) && has_verify_btn

    if raw_body.match?(CHALLENGE_PHRASES) || content_doc.text.match?(CHALLENGE_PHRASES)
      article_node = content_doc.at_css("article") || content_doc.at_css("main") || content_doc.at_css("body")
      all_paragraphs = article_node&.css("p, blockquote, div")&.map { |p| p.text.strip }&.reject(&:blank?) || []
      all_paragraphs = [article_node.text.strip] if all_paragraphs.empty? && article_node&.text&.present?

      return true if all_paragraphs.empty?

      substantive_paragraphs = all_paragraphs.reject do |p_text|
        unquoted = p_text.gsub(/"[^"\n]{10,}"/, "")
          .gsub(/'[^'\n]{10,}'/, "")
          .gsub(/“[^\n”]{10,}”/, "")
          .gsub(/‘[^\n’]{10,}’/, "")
          .strip
        unquoted.match?(CHALLENGE_PHRASES) && unquoted.gsub(CHALLENGE_PHRASES, "").strip.length < MIN_TEXT_CHARS
      end

      total_text = all_paragraphs.join(" ")
      cleaned_text = total_text.gsub(CHALLENGE_PHRASES, "").gsub(/[[:punct:]\s]+/, " ").strip

      return true if substantive_paragraphs.empty? || cleaned_text.length < MIN_TEXT_CHARS
    end

    false
  end

  def paywall_indicator?(first_arg, second_arg = nil)
    doc, raw_body = normalize_doc_and_body(first_arg, second_arg)

    return false if raw_body.blank? && doc.nil?
    return true if raw_body.match?(/"isAccessibleForFree"\s*:\s*(false|"false")/i)

    doc ||= Nokogiri::HTML(raw_body)
    return true if microdata_paywalled?(doc)
    return true if login_gate?(doc, raw_body)

    content_area = remove_peripheral_chrome(doc)
    return true if content_area.at_css(PAYWALL_SELECTORS)

    active_sub_heading = content_area.css("h1, h2, h3, h4, h5, h6").any? do |h|
      h.text.strip.match?(/\A\s*(subscribe to continue|subscription required|choose your subscription|subscribers only|unlock this (?:article|story)|log in or subscribe|sign in or subscribe|subscriber sign in|subscriber login)\s*\z/i) ||
        h.text.match?(PAYWALL_PHRASES)
    end
    return true if active_sub_heading

    active_sub_cta = content_area.css("a, button, input[type='submit']").any? do |el|
      href = el["href"].to_s.downcase
      text = el.text.strip
      (href.include?("subscribe") || href.include?("subscription") || href.include?("membership") || href.include?("plans") || href.include?("join")) &&
        (text.match?(/subscribe|choose your subscription|unlock|join|membership/i) || content_area.text.match?(PAYWALL_PHRASES))
    end
    return true if active_sub_cta

    unquoted_area = content_area.dup
    unquoted_area.css("blockquote, q").remove
    unquoted_text = unquoted_area.text
      .gsub(/"[^"\n]{10,}"/, "")
      .gsub(/'[^'\n]{10,}'/, "")
      .gsub(/“[^\n”]{10,}”/, "")
      .gsub(/‘[^\n’]{10,}’/, "")

    return true if unquoted_text.match?(PAYWALL_PHRASES)

    if raw_body.match?(PAYWALL_PHRASES)
      article_node = content_area.at_css("article") || content_area.at_css("main")
      article_text = article_node&.css("p")&.map(&:text)&.join(" ")&.strip.to_s
      return true if article_text.blank? || article_text.length < MIN_TEXT_CHARS
    end

    false
  end

  def microdata_paywalled?(doc)
    doc.css("[itemprop='isAccessibleForFree']").any? do |node|
      val = (node["content"].presence || node["href"].presence || node.text).to_s.strip.downcase
      val.in?(%w[false 0 http://schema.org/false https://schema.org/false])
    end
  end

  def login_gate?(doc, raw_body)
    title = doc.at_css("title")&.text.to_s.strip
    has_login_title = title.match?(LOGIN_TITLE_PATTERNS)
    has_password_field = doc.at_css("input[type='password'], input[name*='password']").present?

    return true if has_login_title && (has_password_field || raw_body.match?(/subscription|subscriber|password/i))

    content_area = remove_peripheral_chrome(doc)
    main_password = content_area.at_css("input[type='password'], input[name*='password']").present?

    if main_password
      main_text = content_area.text
      if main_text.match?(PAYWALL_PHRASES) || main_text.match?(/subscription|subscriber|sign in|log in/i)
        return true
      end
    end

    has_auth_form = content_area.css("form").any? do |f|
      f_action = f["action"].to_s.downcase
      (f_action.include?("login") || f_action.include?("signin") || f_action.include?("auth") || f_action.include?("session")) &&
        f.text.match?(/subscriber|sign in|log in|welcome back/i)
    end
    return true if has_auth_form

    false
  end

  def normalize_doc_and_body(first_arg, second_arg)
    doc = if first_arg.respond_to?(:at_css)
      first_arg
    elsif second_arg.respond_to?(:at_css)
      second_arg
    end

    raw_body = if first_arg.is_a?(String)
      first_arg
    elsif second_arg.is_a?(String)
      second_arg
    elsif doc
      doc.to_s
    else
      ""
    end

    [doc, raw_body]
  end

  def extract_article_metadata(doc)
    author = doc.at_css("meta[name='author']")&.[]("content") ||
      doc.at_css("meta[property='article:author']")&.[]("content") ||
      doc.at_css("meta[name='dc.creator']")&.[]("content")
    author = author.strip if author.present?

    published_str = doc.at_css("meta[property='article:published_time']")&.[]("content") ||
      doc.at_css("meta[name='publish-date']")&.[]("content") ||
      doc.at_css("time[datetime]")&.[]("datetime")

    published_at = begin
      Time.zone.parse(published_str) if published_str.present?
    rescue ArgumentError, TypeError
      nil
    end

    {author_name: author, published_at: published_at}
  end

  def apply_article_metadata_updates(meta_updates)
    updates = {}
    updates[:author_name] = meta_updates[:author_name] if news_article.author_name.blank? && meta_updates[:author_name].present?
    updates[:published_at] = meta_updates[:published_at] if news_article.published_at.blank? && meta_updates[:published_at].present?
    news_article.update!(updates) if updates.present?
  end

  def persist_version(status:, text:, final_url:)
    status_str = status.to_s
    digest = Digest::SHA256.hexdigest(text || "")

    existing = news_article.text_versions.find_by(
      digest: digest,
      extraction_status: status_str
    )
    return existing if existing

    NewsArticleTextVersion.create!(
      news_article: news_article,
      origin: "retrieved",
      extraction_status: status_str,
      text: text,
      digest: digest,
      requested_url: requested_url,
      final_url: final_url
    )
  end

  def link_association(version)
    return unless bill_news_article

    current = bill_news_article.current_text_version
    return if current&.manual? || current&.admin?

    bill_news_article.update!(current_text_version: version)
  end
end
