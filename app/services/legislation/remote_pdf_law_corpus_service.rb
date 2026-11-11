# frozen_string_literal: true

require "digest"
require "json"
require "tmpdir"
require "uri"

module Legislation
  # @lat: [[legislation-pipeline#The legislation pipeline#Maryland PDF law corpus acquisition]]
  class RemotePdfLawCorpusService
    MAX_CATALOG_BYTES = 2 * 1024 * 1024
    MAX_LINK_BYTES = 32 * 1024
    MAX_PDF_BYTES = 64 * 1024 * 1024
    MAX_CORPUS_BYTES = 2 * 1024 * 1024 * 1024
    MAX_ARTICLES = 100
    CHUNK_BYTES = 64 * 1024
    MANIFEST_FILENAME = "manifest.json"

    def initialize(sway_locale:, law_root:, http: nil)
      @sway_locale = sway_locale
      @law_root = Pathname.new(law_root)
      @http = http
    end

    def call
      config = law_config
      @base_url = config[:base_url]
      raw_root = local_root(config)
      @law_root.mkpath
      File.open(@law_root.join(".configured-pdf-corpus.lock"), "w") do |lock|
        lock.flock(File::LOCK_EX)
        call_locked(config, raw_root)
      end
    rescue StageError
      raise
    rescue SystemCallError, IOError => e
      raise StageError, "fetch_law: configured PDF corpus is unavailable: #{diagnostic(e)}"
    end

    private

    def call_locked(config, raw_root)
      verified_manifest = read_verified_manifest(raw_root, config[:base_url])
      articles = begin
        discover_articles(config)
      rescue StageError, Faraday::Error, URI::Error, JSON::ParserError, BoundedResponseBody::TooLarge => e
        return cached_or_raise(verified_manifest, raw_root, e)
      end

      if verified_manifest && same_manifest?(verified_manifest, articles)
        return :unchanged
      end

      begin
        publish_corpus(raw_root, articles)
        :downloaded
      rescue StageError, Faraday::Error, URI::Error, JSON::ParserError,
        BoundedResponseBody::TooLarge, SystemCallError, IOError => e
        cached_or_raise(verified_manifest, raw_root, e)
      end
    end

    def law_config
      rules = @sway_locale.jurisdiction_rules&.law_rules
      config = rules.is_a?(Hash) ? rules.deep_symbolize_keys : {}
      raise StageError, "fetch_law: configured PDF corpus rules are missing for #{@sway_locale.name}" if config.empty?

      base_url = config[:base_url].to_s
      base_uri = URI.parse(base_url)
      unless base_uri.is_a?(URI::HTTPS) && base_uri.host.present? && base_uri.port == 443 && base_uri.userinfo.nil?
        raise StageError, "fetch_law: configured PDF corpus base_url must be an HTTPS origin"
      end

      endpoints = config[:endpoints]
      unless endpoints.is_a?(Hash) && endpoints[:catalog].present? && endpoints[:article_link].present?
        raise StageError, "fetch_law: configured PDF corpus endpoints are incomplete"
      end

      params = config[:params]
      unless params.is_a?(Hash) && params[:enactments].present?
        raise StageError, "fetch_law: configured PDF corpus enactments parameter is missing"
      end

      config
    rescue URI::InvalidURIError => e
      raise StageError, "fetch_law: invalid configured PDF corpus base_url: #{e.message}"
    end

    def local_root(config)
      value = config[:local_path].to_s
      relative = Pathname.new(value)
      parts = value.split(/[\\\/]/)
      root = @law_root.expand_path
      target = root.join(relative).cleanpath
      root_prefix = root.to_s + File::SEPARATOR

      if value.blank? || relative.absolute? || value.include?("\\") || parts.include?("..") ||
          !target.to_s.start_with?(root_prefix)
        raise StageError, "fetch_law: local_path must stay inside the law root"
      end

      @law_root.mkpath
      current = root
      parts.reject(&:empty?).each do |part|
        current = current.join(part)
        if current.symlink?
          raise StageError, "fetch_law: local_path cannot traverse symlinks"
        end
      end

      target
    rescue ArgumentError => e
      raise StageError, "fetch_law: invalid local_path: #{e.message}"
    end

    def discover_articles(config)
      params = string_params(config[:params])
      catalog = get_json(config[:endpoints][:catalog], params, MAX_CATALOG_BYTES, "article catalog")
      unless catalog.is_a?(Array)
        raise StageError, "fetch_law: MGA article catalog must be an array"
      end

      codes = catalog.map do |article|
        raise StageError, "fetch_law: MGA article catalog contains an invalid entry" unless article.is_a?(Hash)

        (article["Value"] || article["value"]).to_s.strip.downcase
      end.select { |code| code.match?(/\Ag[a-z0-9]+\z/) }.uniq.sort

      if codes.empty? || codes.size > MAX_ARTICLES
        raise StageError, "fetch_law: MGA statutory article catalog has an invalid count (#{codes.size})"
      end

      codes.to_h do |code|
        link_params = params.merge("articleCode" => code)
        link = get_json(config[:endpoints][:article_link], link_params, MAX_LINK_BYTES, "article #{code} link")
        url = if link.is_a?(String)
          link
        elsif link.is_a?(Hash)
          link["url"] || link["Url"] || link["URL"]
        end
        url = url.to_s.strip
        validate_pdf_url!(url, config[:base_url])
        [code, url]
      end
    end

    def get_json(endpoint, params, byte_limit, description)
      response = http_connection.get(endpoint.to_s) do |request|
        request.params.update(params)
      end
      unless response.status == 200
        raise StageError, "fetch_law: MGA #{description} request returned HTTP #{response.status}"
      end

      body = response.body.to_s
      if body.bytesize > byte_limit
        raise StageError, "fetch_law: MGA #{description} response exceeds #{byte_limit} bytes"
      end

      JSON.parse(body)
    rescue JSON::ParserError => e
      raise StageError, "fetch_law: malformed MGA #{description}: #{e.message.to_s[0, 200]}"
    end

    def validate_pdf_url!(url, base_url)
      base_uri = URI.parse(base_url)
      uri = URI.parse(url)
      unless uri.is_a?(URI::HTTPS) && uri.host == base_uri.host && uri.port == 443 && uri.userinfo.nil? &&
          uri.path.to_s.match?(/\.pdf\z/i) && uri.query.nil? && uri.fragment.nil?
        raise StageError, "fetch_law: unexpected or unsafe PDF URL"
      end

      uri.to_s
    rescue URI::InvalidURIError => e
      raise StageError, "fetch_law: invalid MGA PDF URL: #{e.message}"
    end

    def publish_corpus(raw_root, articles)
      raw_root.dirname.mkpath
      Dir.mktmpdir(".#{raw_root.basename}-stage-", raw_root.dirname.to_s) do |directory|
        staged_root = Pathname.new(directory).join(raw_root.basename)
        staged_root.mkpath
        manifest_articles = {}
        corpus_bytes = 0

        articles.each do |code, url|
          path = staged_root.join("#{code}.pdf")
          bytes = download_pdf(code, url)
          corpus_bytes += bytes.bytesize
          if corpus_bytes > MAX_CORPUS_BYTES
            raise StageError, "fetch_law: configured PDF corpus exceeds #{MAX_CORPUS_BYTES} bytes"
          end
          path.binwrite(bytes)
          manifest_articles[code] = {
            "url" => url,
            "file" => path.basename.to_s,
            "sha256" => Digest::SHA256.hexdigest(bytes)
          }
        end

        manifest = {"version" => 1, "articles" => manifest_articles}
        staged_root.join(MANIFEST_FILENAME).write(JSON.pretty_generate(manifest))
        publish_directory(staged_root, raw_root)
      end
    end

    def download_pdf(code, url)
      body = BoundedResponseBody.new(limit: MAX_PDF_BYTES, description: "MGA article #{code} PDF")
      response = http_connection.get(url) do |request|
        request.options.on_data = proc do |chunk, received, _env|
          body.receive(chunk, received)
        end
      end
      unless response.status == 200
        raise StageError, "fetch_law: MGA article #{code} PDF request returned HTTP #{response.status}"
      end

      advertised = response.headers["content-length"].to_s
      if advertised.match?(/\A\d+\z/) && advertised.to_i > MAX_PDF_BYTES
        raise StageError, "fetch_law: MGA article #{code} PDF advertises more than #{MAX_PDF_BYTES} bytes"
      end

      bytes = body.buffer
      bytes = response.body.to_s if bytes.empty?
      if bytes.bytesize > MAX_PDF_BYTES
        raise StageError, "fetch_law: MGA article #{code} PDF exceeds #{MAX_PDF_BYTES} bytes"
      end
      if advertised.match?(/\A\d+\z/) && response.headers["content-encoding"].blank? && advertised.to_i != bytes.bytesize
        raise StageError, "fetch_law: incomplete MGA article #{code} PDF response"
      end
      raise StageError, "fetch_law: MGA article #{code} response has no PDF signature" unless bytes.start_with?("%PDF-")

      bytes
    rescue BoundedResponseBody::TooLarge => e
      raise StageError, e.message
    end

    def publish_directory(staged_root, raw_root)
      backup = raw_root.dirname.join(".#{raw_root.basename}-backup-#{SecureRandom.hex(6)}")
      had_prior = raw_root.exist?
      File.rename(raw_root, backup) if had_prior
      begin
        File.rename(staged_root, raw_root)
      rescue SystemCallError, IOError
        File.rename(backup, raw_root) if had_prior && backup.exist?
        raise
      end
      FileUtils.rm_rf(backup) if had_prior
    end

    def same_manifest?(manifest, articles)
      expected = articles
      current = manifest.fetch("articles")
      current.keys.sort == expected.keys.sort && expected.all? do |code, url|
        current.dig(code, "url") == url && current.dig(code, "file") == "#{code}.pdf"
      end
    end

    def read_verified_manifest(raw_root, base_url)
      return nil unless raw_root.directory? && !raw_root.symlink?

      manifest_path = raw_root.join(MANIFEST_FILENAME)
      return nil unless manifest_path.file? && !manifest_path.symlink?

      manifest = JSON.parse(manifest_path.read)
      entries = manifest["articles"]
      return nil unless manifest["version"] == 1 && entries.is_a?(Hash) && entries.any? && entries.size <= MAX_ARTICLES

      total = 0
      entries.each do |code, entry|
        return nil unless code.match?(/\Ag[a-z0-9]+\z/) && entry.is_a?(Hash)
        return nil unless entry["file"] == "#{code}.pdf" && entry["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)

        validate_pdf_url!(entry["url"].to_s, base_url)
        path = raw_root.join(entry["file"])
        return nil unless path.file? && !path.symlink?

        bytes = path.binread
        return nil unless bytes.start_with?("%PDF-") && Digest::SHA256.hexdigest(bytes) == entry["sha256"]

        total += bytes.bytesize
        return nil if bytes.bytesize > MAX_PDF_BYTES || total > MAX_CORPUS_BYTES
      end

      manifest
    rescue JSON::ParserError, SystemCallError, IOError, StageError
      nil
    end

    def cached_or_raise(verified_manifest, raw_root, error)
      if verified_manifest
        SwayLogging.warn("fetch_law.configured_pdf_cached_offline", reason: diagnostic(error))
        return :cached_offline
      end

      raise StageError,
        "fetch_law: configured PDF corpus acquisition failed: #{diagnostic(error)}; no complete verified cache under #{raw_root}"
    end

    def string_params(params)
      params.to_h do |key, value|
        [key.to_s, value.to_s]
      end
    end

    def http_connection
      @http ||= Sway::FaradayStack.build(
        base_url: @base_url.to_s,
        timeout_seconds: 120,
        retry_options: Sway::FaradayStack::OPEN_DATA_DEFAULTS
      )
    end

    def diagnostic(error)
      "#{error.class.name.demodulize}: #{error.message.to_s.lines.first.to_s.strip[0, 300]}"
    end
  end
end
