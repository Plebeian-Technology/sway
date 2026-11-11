# frozen_string_literal: true

require "json"
require "stringio"
require "zlib"
require "rubygems/package"

# @lat: [[fetch-law-corpus-service#Why the byte caps are sized the way they are]]
class FetchLawCorpusService
  DEFAULT_REPO = "baltimore-legref/law-xml"
  DEFAULT_BRANCH = "main"

  def self.commits_url(repo = DEFAULT_REPO, branch = DEFAULT_BRANCH)
    "https://api.github.com/repos/#{repo}/commits/#{branch}"
  end

  def self.tarball_url(repo = DEFAULT_REPO, branch = DEFAULT_BRANCH)
    "https://github.com/#{repo}/archive/refs/heads/#{branch}.tar.gz"
  end

  # @lat: [[fetch-law-corpus-service#Why REQUIRED_CORPUS_FILE is charter.xml]]
  REQUIRED_CORPUS_FILE = "charter.xml"

  # @lat: [[fetch-law-corpus-service#Why the byte caps are sized the way they are]]
  MAX_TARBALL_BYTES = 64 * 1024 * 1024

  # @lat: [[fetch-law-corpus-service#Why REPO and BRANCH are read with EnvSecret.read + ||, not ENV.fetch]]
  REDIRECT_STATUSES = (300..399)
  MAX_EXTRACTED_BYTES = 256 * 1024 * 1024

  class TooLarge < StandardError
  end

  attr_reader :sway_locale

  def initialize(run: nil, http: Sway::FaradayStack.github, sway_locale: nil)
    @run = run
    @http = http
    @sway_locale = sway_locale || run&.effective_sway_locale
  end

  def repo
    (@repo.presence || resolve_repo_config[:repo]).to_s
  end

  def branch
    (@branch.presence || resolve_repo_config[:branch]).to_s
  end

  def commits_url
    self.class.commits_url(repo, branch)
  end

  def tarball_url
    self.class.tarball_url(repo, branch)
  end

  def call
    sway_locale = @sway_locale
    if sway_locale
      adapter = Legislation::Adapters::GenericLawAdapter.new(sway_locale)
      if adapter.retrieval == :unavailable || adapter.engine == :unavailable
        raise StageError,
          "fetch_law_corpus: law acquisition is unavailable for #{sway_locale.name}"
      end

      @repo = adapter.config[:repo]&.to_s
      @branch = adapter.config[:branch].presence&.to_s || "main"

      if @repo.blank?
        raise StageError,
          "fetch_law_corpus: law corpus repository is not configured for #{sway_locale.name} (law source: #{adapter.engine})"
      end
    else
      @repo ||= DEFAULT_REPO
      @branch ||= DEFAULT_BRANCH
    end

    raw_root.mkpath
    latest = latest_commit_sha

    if latest && unchanged?(latest) && corpus_present?
      SwayLogging.info("fetch_law_corpus.unchanged", run_id: @run&.id, sha: latest)
      return :unchanged
    end

    body = download_tarball
    return fallback_or_raise("tarball download returned a non-success status") if body.nil?

    extract_tarball(body)
    persist_commit_sha(latest)

    unless corpus_present?
      raise StageError, "fetch_law_corpus: #{REQUIRED_CORPUS_FILE} not found after extracting #{tarball_url}"
    end

    SwayLogging.info("fetch_law_corpus.downloaded", run_id: @run&.id, sha: latest || "unknown")
    :downloaded
  rescue Faraday::Error => e
    fallback_or_raise("network error #{e.class}: #{e.message.to_s[0, 200]}")
  rescue TooLarge => e
    fallback_or_raise(e.message)
  end

  private

  def resolve_repo_config
    if @sway_locale
      adapter = Legislation::Adapters::GenericLawAdapter.new(@sway_locale)
      repo = adapter.config[:repo]&.to_s
      branch = adapter.config[:branch].presence&.to_s || "main"
      {repo: repo.presence || DEFAULT_REPO, branch: branch}
    else
      {repo: DEFAULT_REPO, branch: DEFAULT_BRANCH}
    end
  end

  def fallback_or_raise(reason)
    if corpus_present?
      SwayLogging.warn("fetch_law_corpus.cached_offline", run_id: @run&.id, reason: reason)
      return :cached_offline
    end

    raise StageError, "fetch_law_corpus: #{reason}; no cached corpus on disk under #{raw_root}"
  end

  def raw_root
    Legislation::Paths.law.join("raw")
  end

  def sha_file
    raw_root.join(".commit_sha")
  end

  def corpus_present?
    Pathname.glob(raw_root.join("**", REQUIRED_CORPUS_FILE).to_s).any?
  end

  def unchanged?(sha)
    sha_file.exist? && sha_file.read.strip == sha
  rescue SystemCallError, IOError
    # @lat: [[fetch-law-corpus-service#Why REQUIRED_CORPUS_FILE is charter.xml]]
    false
  end

  # @lat: [[fetch-law-corpus-service#Why this service exists]]
  def latest_commit_sha
    resp = @http.get(commits_url)
    return nil unless resp.status.between?(200, 299)

    parsed = JSON.parse(resp.body.to_s)
    parsed.is_a?(Hash) ? parsed["sha"]&.to_s : nil
  rescue Faraday::Error, JSON::ParserError
    nil
  end

  # @lat: [[fetch-law-corpus-service#Why this service exists]]
  def download_tarball
    body = BoundedResponseBody.new(limit: MAX_TARBALL_BYTES, description: "tarball")

    resp = @http.get(tarball_url) do |request|
      request.options.on_data = proc do |chunk, overall_received_bytes, env|
        body.receive(chunk, overall_received_bytes, keep: !REDIRECT_STATUSES.cover?(env.status.to_i))
      end
    end
    return nil unless resp.status.between?(200, 299)

    advertised = resp.headers["content-length"].to_s
    if advertised.match?(/\A\d+\z/) && advertised.to_i > MAX_TARBALL_BYTES
      raise TooLarge, "tarball advertises #{advertised} bytes, over the #{MAX_TARBALL_BYTES}-byte cap"
    end

    body.buffer
  rescue BoundedResponseBody::TooLarge => e
    raise TooLarge, e.message
  end

  # @lat: [[fetch-law-corpus-service#Why this service exists]]
  # @lat: [[fetch-law-corpus-service#Why the byte caps are sized the way they are]]
  def extract_tarball(bytes)
    extracted_bytes = 0

    # @lat: [[fetch-law-corpus-service#Why extract_tarball needs two narrow Steep suppressions]]
    Zlib::GzipReader.wrap(StringIO.new(bytes)) do |gz| # steep:ignore
      Gem::Package::TarReader.new(gz) do |tar| # steep:ignore
        tar.each do |entry|
          entry_size = entry.size #: Integer
          extracted_bytes += entry_size
          if extracted_bytes > MAX_EXTRACTED_BYTES
            raise TooLarge, "extracted corpus exceeds #{MAX_EXTRACTED_BYTES} bytes"
          end

          dest = safe_destination(entry.full_name.to_s)
          next if dest.nil?

          if entry.directory?
            dest.mkpath
          elsif entry.file?
            dest.dirname.mkpath
            dest.binwrite(entry.read.to_s)
          end
        end
      end
    end
  end

  # @lat: [[fetch-law-corpus-service#Why this service exists]]
  def safe_destination(name)
    cleaned = Pathname.new(name).cleanpath
    return nil if cleaned.absolute?
    return nil if cleaned.to_s.split("/").include?("..")

    dest = raw_root.join(cleaned)
    root_prefix = raw_root.to_s + File::SEPARATOR
    return nil unless dest.to_s == raw_root.to_s || dest.to_s.start_with?(root_prefix)

    dest
  end

  def persist_commit_sha(sha)
    return if sha.nil?

    sha_file.binwrite(sha)
  rescue SystemCallError, IOError => e
    # @lat: [[fetch-law-corpus-service#Why REQUIRED_CORPUS_FILE is charter.xml]]
    SwayLogging.warn(
      "[FetchLawCorpusService] could not persist #{sha_file}: #{e.class.name}: #{e.message.to_s[0, 200]}"
    )
  end
end
