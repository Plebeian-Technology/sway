# frozen_string_literal: true

require "json"
require "net/http"
require "tmpdir"
require "uri"

# @lat: [[pdf-extraction-mutool-ocr-fallback#The extraction rules]]
class MupdfExtractor
  include PdfSubprocessRunner

  # @lat: [[mupdf-preflight-tessdata-check#Why it moved out of the constructor]]
  class MissingTessdataError < RuntimeError
  end

  # @lat: [[mupdf-output-scrubbing-and-timeouts#Why ExtractionFailed only carries 500 characters of stderr]]
  class ExtractionFailed < RuntimeError
  end

  # @lat: [[mupdf-ocr-unavailable-detection#The bug that substring matching caused]]
  class OcrUnavailable < ExtractionFailed
  end

  # @lat: [[mupdf-ocr-unavailable-detection#Why the signature match always reads the FULL stderr, not a truncated copy]]
  OCR_DISABLED_SIGNATURE = "OCR Disabled in this build"

  # @lat: [[pdf-extraction-mutool-ocr-fallback#The extraction rules]]
  MIN_NATIVE_CHARS = 50

  # @lat: [[pdf-extraction-mutool-ocr-fallback#The extraction rules]]
  OCR_DPI = 300

  # @lat: [[mupdf-ocr-page-cap#How 50 pages was chosen]]
  MAX_OCR_PAGES = 50

  OCR_PAGE_TRUNCATION_NOTICE =
    "\n\n[... truncated: this document has more pages than the OCR page cap ...]"

  # @lat: [[mupdf-preflight-tessdata-check#Why the eager preflight! call at construction time is a documented test seam]]
  def self.preflight!
    return if Sway::Settings.legislation.pdf_extractor_url.present?

    tessdata = Sway::Settings.legislation.tessdata_prefix.to_s
    if tessdata.empty?
      raise MissingTessdataError,
        "TESSDATA_PREFIX env var not set; mutool OCR will silently produce empty output"
    end
    unless File.directory?(tessdata)
      raise MissingTessdataError,
        "TESSDATA_PREFIX directory #{tessdata.inspect} not found; mutool OCR will silently produce empty output"
    end
    # @lat: [[mupdf-preflight-tessdata-check#Why the glob is recursive]]
    has_traineddata = Dir.glob(File.join(tessdata, "**/*.traineddata")).any?
    unless has_traineddata
      raise MissingTessdataError,
        "TESSDATA_PREFIX #{tessdata.inspect} contains no .traineddata files; mutool OCR will silently produce empty output"
    end
  end

  # @lat: [[mupdf-preflight-tessdata-check#Why the eager preflight! call at construction time is a documented test seam]]
  def initialize(pdf_path)
    self.class.preflight!

    @pdf_path = pdf_path.to_s
  end

  def call
    if (url = Sway::Settings.legislation.pdf_extractor_url).present?
      return extract_remote(url)
    end

    native = run_mutool(["draw", "-F", "txt", @pdf_path])
    return native if native.length >= MIN_NATIVE_CHARS

    ocr_extract
  end

  # @lat: [[mupdf-ocr-unavailable-memoization#Why self.class, not the literal class name]]
  def self.reset_mutool_ocr_detection!
    @mutool_ocr_unavailable = nil
  end

  # @lat: [[mupdf-ocr-unavailable-memoization#Why self.class, not the literal class name]]
  def self.mutool_ocr_unavailable?
    @mutool_ocr_unavailable == true
  end

  private

  # @lat: [[pdf-extraction-mutool-ocr-fallback#Optional remote extraction service]]
  def extract_remote(base_url)
    uri = URI.parse("#{base_url.chomp("/")}/extract")
    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    req.body = {
      pdf_path: @pdf_path,
      min_native_chars: MIN_NATIVE_CHARS,
      ocr_dpi: OCR_DPI,
      max_ocr_pages: MAX_OCR_PAGES
    }.to_json

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
    text = Sway::Utf8.scrub(data["text"].to_s)
    if text.strip.empty?
      raise ExtractionFailed, "remote pdf extractor produced empty text for #{File.basename(@pdf_path)}"
    end

    data["truncated"] ? text + OCR_PAGE_TRUNCATION_NOTICE : text
  rescue ExtractionFailed
    raise
  rescue Timeout::Error => e
    raise ExtractionFailed, Sway::Utf8.scrub("remote pdf extractor timed out: #{e.message}")[0, 500]
  rescue => e
    scrubbed = Sway::Utf8.scrub("remote pdf extractor failed: #{e.class.name.to_s.demodulize}: #{e.message}")[0, 500]
    raise ExtractionFailed, scrubbed
  end

  # @lat: [[mupdf-empty-ocr-text-guard#What happened before this guard existed]]
  def ocr_extract
    text, truncated = run_ocr

    if text.strip.empty?
      raise ExtractionFailed,
        "ocr produced no text for #{File.basename(@pdf_path)} (exit 0, empty output — " \
        "unusable tessdata language data is the documented cause and preflight cannot see it)"
    end

    # @lat: [[mupdf-empty-ocr-text-guard#Ordering matters]]
    truncated ? text + OCR_PAGE_TRUNCATION_NOTICE : text
  end

  # @lat: [[mupdf-ocr-unavailable-detection#Why a missed detection is expensive]]
  def run_ocr
    return ocr_via_tesseract if self.class.mutool_ocr_unavailable?

    begin
      [run_mutool(["draw", "-F", "ocr.txt", "-r", OCR_DPI.to_s, @pdf_path]), false]
    rescue OcrUnavailable
      # @lat: [[mupdf-ocr-unavailable-memoization#Why self.class, not the literal class name]]
      self.class.instance_variable_set(:@mutool_ocr_unavailable, true)
      ocr_via_tesseract
    end
  end

  # @lat: [[pdf-extraction-mutool-ocr-fallback#How the standalone-tesseract fallback is implemented]]
  def ocr_via_tesseract
    Dir.mktmpdir("mupdf-ocr-") do |tmpdir|
      run_png_render(File.join(tmpdir, "page%d.png"))

      pages = Dir[File.join(tmpdir, "page*.png")].sort_by do |path|
        path[/page(\d+)\.png\z/, 1].to_i
      end
      if pages.empty?
        raise ExtractionFailed, "mutool png render produced no pages for #{@pdf_path}"
      end

      text = pages.first(MAX_OCR_PAGES).map { |png| run_tesseract(png) }.join("\n\n")
      return [text, false] if pages.length <= MAX_OCR_PAGES

      SwayLogging.warn(
        "mupdf_extractor.ocr_pages_truncated",
        pdf_path: File.basename(@pdf_path),
        rendered_pages: pages.length,
        max_ocr_pages: MAX_OCR_PAGES
      )
      [text, true]
    end
  rescue SystemCallError => e
    # @lat: [[mupdf-ocr-workspace-error-handling#Why it must become ExtractionFailed]]
    raise ExtractionFailed, "ocr workspace unavailable: #{e.class.name.demodulize}: #{e.message.to_s[0, 200]}"
  end

  # @lat: [[mupdf-ocr-workspace-error-handling#Why the message names the workspace, not a binary]]
  def run_png_render(png_template)
    run_subprocess_translated(
      "mutool", "draw", "-F", "png", "-r", OCR_DPI.to_s,
      "-o", png_template, @pdf_path,
      label: "mutool png render"
    )
    nil
  end

  def run_tesseract(png_path)
    run_subprocess_translated(
      "tesseract", png_path, "stdout", "-l", "eng",
      label: "tesseract",
      target: " on #{File.basename(png_path)}"
    )
  end

  # @lat: [[mupdf-output-scrubbing-and-timeouts#Why the output is scrubbed]]
  def run_mutool(args)
    run_subprocess_translated("mutool", *args, label: "mutool") do |stderr, _event|
      ocr_failure_class(stderr)
    end
  end

  # @lat: [[mupdf-ocr-unavailable-detection#Why the signature match always reads the FULL stderr, not a truncated copy]]
  def ocr_failure_class(stderr)
    stderr.to_s.include?(OCR_DISABLED_SIGNATURE) ? OcrUnavailable : ExtractionFailed
  end
end
