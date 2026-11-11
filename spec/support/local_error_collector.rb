# frozen_string_literal: true

require "json"
require "net/http"

# @lat: [[local-error-collector-browser-readback#Why an unavailable collector skips the spec instead of failing it]]
class LocalErrorCollector
  PROJECT_FILE = "config/rustrak_project.key"
  TOKEN_FILE = "config/rustrak_mcp.key"

  # Long enough for the browser to send and the collector to digest, short
  # enough that waiting for something that will never arrive still ends.
  DEFAULT_TIMEOUT_SECONDS = 20

  # @lat: [[local-error-collector-browser-readback#Why an unavailable collector skips the spec instead of failing it]]
  def self.unavailable_reason
    unless ENV["VITE_RUSTRAK_DSN"].to_s.strip.presence || file?(PROJECT_FILE)
      return "there is no collector address: VITE_RUSTRAK_DSN is unset and #{PROJECT_FILE} " \
        "is missing. Run `dip run dev` once."
    end
    return "#{TOKEN_FILE} is missing. Run `bin/rustrak-mcp-token`." unless file?(TOKEN_FILE)
    return "the collector is not answering on #{base_url}. Start it with `dip run dev`." unless answering?

    nil
  end

  # @lat: [[error-reporting-in-tests#Where a browser's error reports go during a spec run]]
  def self.dsn
    ENV["VITE_RUSTRAK_DSN"].to_s.strip.presence || read(PROJECT_FILE)
  end

  # Read back from the same address the browser just sent to.
  def self.base_url
    uri = URI.parse(dsn)
    port = uri.port ? ":#{uri.port}" : ""
    "#{uri.scheme}://#{uri.host}#{port}"
  rescue URI::InvalidURIError
    "http://127.0.0.1:#{ENV.fetch("RUSTRAK_PORT", "8482")}"
  end

  def self.project_id = dsn.split("/").last

  def self.file?(path) = Rails.root.join(path).file?

  def self.read(path) = Rails.root.join(path).read.strip

  def self.answering?
    get("/health") { |response| response.is_a?(Net::HTTPSuccess) } || false
  end

  # Internal, but public so callers need no `send`. Yields the response and
  # hands back whatever the block returns, or nil when the request could not be
  # made at all — the collector being down is an ordinary condition here.
  def self.get(path)
    uri = URI.join(base_url, path)
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{read(TOKEN_FILE)}" if file?(TOKEN_FILE)

    response = Net::HTTP.start(uri.hostname.to_s, uri.port, open_timeout: 2, read_timeout: 5) do |http|
      http.request(request)
    end
    yield response
  rescue
    nil
  end

  # Waits for the collector to hold an error whose text carries the marker, and
  # hands back everything it stored about it. Nil when nothing arrives in time.
  def wait_for_issue(marker, timeout_seconds: DEFAULT_TIMEOUT_SECONDS)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

    loop do
      found = issues.find { |issue| issue.to_json.include?(marker) }
      return found if found
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.5
    end
    nil
  end

  # The newest errors the collector holds for this project.
  def issues(limit: 25)
    body = self.class.get("/api/projects/#{self.class.project_id}/issues?limit=#{limit}") do |response|
      response.is_a?(Net::HTTPSuccess) ? response.body : nil
    end
    return [] if body.nil?

    parsed = JSON.parse(body)
    return [] unless parsed.is_a?(Hash)

    items = parsed["items"]
    items.is_a?(Array) ? items : []
  rescue JSON::ParserError
    []
  end
end
