# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

# @lat: [[testimony-text-extractor-design#Why it does not reuse or extend MupdfExtractor]]
class TestimonyTextExtractor
  include PdfSubprocessRunner

  class ExtractionFailed < RuntimeError
  end

  def initialize(pdf_path)
    @pdf_path = pdf_path.to_s
  end

  def call
    if (url = Sway::Settings.legislation.pdf_extractor_url).present?
      return extract_remote(url)
    end

    run_mutool(["draw", "-F", "txt", @pdf_path])
  end

  private

  # @lat: [[testimony-text-extractor-design#Why it does not reuse or extend MupdfExtractor]]
  def extract_remote(base_url)
    uri = URI.parse("#{base_url.chomp("/")}/extract")
    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    req.body = {pdf_path: @pdf_path, disable_ocr: true}.to_json

    res = Net::HTTP.start(
      uri.host.to_s, uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: 5,
      read_timeout: 300
    ) { |http| http.request(req) }

    unless res.is_a?(Net::HTTPSuccess)
      error_detail = Sway::Utf8.scrub(res.body.to_s)
      raise ExtractionFailed, Sway::Utf8.scrub("remote pdf extractor failed (HTTP #{res.code}): #{error_detail}")[0, 500]
    end

    data = JSON.parse(res.body)
    Sway::Utf8.scrub(data["text"].to_s)
  rescue ExtractionFailed
    raise
  rescue Timeout::Error => e
    raise ExtractionFailed, Sway::Utf8.scrub("remote pdf extractor timed out: #{e.message}")[0, 500]
  rescue => e
    scrubbed = Sway::Utf8.scrub("remote pdf extractor failed: #{e.class.name.to_s.demodulize}: #{e.message}")[0, 500]
    raise ExtractionFailed, scrubbed
  end

  # @lat: [[testimony-text-extractor-design#Why it does not reuse or extend MupdfExtractor]]
  def run_mutool(args)
    run_subprocess_translated("mutool", *args, label: "mutool")
  end
end
