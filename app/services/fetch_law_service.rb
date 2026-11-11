# frozen_string_literal: true

require "json"
require "nokogiri"

# @lat: [[legislation-pipeline#Upstream jurisdiction adapters]]
# @lat: [[legislation-pipeline#Law artifact readiness]]
class FetchLawService
  CHARTER_FILE = "charter.xml"

  def initialize(run:)
    @run = run
    @sway_locale = resolve_sway_locale(run)
  end

  def call
    adapter = Legislation::Adapters::GenericLawAdapter.new(@sway_locale, service: self)
    if adapter.retrieval == :unavailable || adapter.engine == :unavailable
      raise StageError, "fetch_law: law acquisition is unavailable for #{@sway_locale.name}"
    end

    adapter.load_corpus(run: @run, sway_locale: @sway_locale, law_root: law_root, service: self)
  rescue Nokogiri::XML::SyntaxError => e
    raise StageError, "fetch_law: malformed XML — #{e.message.to_s[0, 500]}"
  end

  private

  # @lat: [[legislation-pipeline#How a stage resolves its SwayLocale]]
  def resolve_sway_locale(run)
    candidate = run&.effective_sway_locale
    sway_locale = candidate || resolve_default_sway_locale
    if sway_locale.is_a?(SwayLocale) || sway_locale.respond_to?(:jurisdiction_rules)
      sway_locale
    else
      raise StageError, "fetch_law: no default SwayLocale found"
    end
  end

  # @lat: [[legislation-pipeline#How a stage resolves its SwayLocale]]
  def resolve_default_sway_locale
    sway_locale = SwayLocale.resolve_by_computed_name(LegislationIngestionService::DEFAULT_LOCALE_NAME)
    sway_locale || raise(StageError, "fetch_law: no default SwayLocale found")
  end

  def law_root
    Legislation::Paths.law(sway_locale: @sway_locale)
  end

  def ingest_corpus(xml_path, corpus_type, stats, section_index)
    parser = AkomaNtosoParser.new(xml_path, corpus_type: corpus_type)
    result = parser.parse

    stats["articles_processed"] += result.fetch(:articles).size

    result.fetch(:sections).each do |sec|
      LawSectionUpsert.call(
        sway_locale: @sway_locale,
        key: sec.fetch(:key),
        article: sec.fetch(:article),
        section: sec.fetch(:section),
        title: sec.fetch(:title),
        body: sec.fetch(:body),
        source_path: sec.fetch(:source_path)
      )
      stats["sections_upserted"] += 1

      write_section_file(sec)
      stats["files_written"] += 1

      section_index[sec.fetch(:key)] = {
        "path" => sec.fetch(:source_path),
        "article" => sec.fetch(:article),
        "title" => sec.fetch(:title),
        "status" => detect_status(sec.fetch(:title))
      }
    end
  end

  def locate_xml(filename)
    raw_root = law_root.join("raw")
    return nil unless raw_root.exist?

    Pathname.glob(raw_root.join("**", filename).to_s).first
  end

  # @lat: [[legislation-pipeline#Upstream jurisdiction adapters]]
  def locate_code_xmls
    raw_root = law_root.join("raw")
    return [] unless raw_root.exist?

    Pathname.glob(raw_root.join("**", "*.xml").to_s).select { |path|
      path.basename.to_s != CHARTER_FILE &&
        path.to_s.split(File::SEPARATOR).any? { |part| part.downcase == "code" }
    }.sort
  end

  def write_section_file(sec)
    abs_path = law_root.join(sec.fetch(:source_path))
    abs_path.dirname.mkpath
    abs_path.write(sec.fetch(:body))
  end

  def write_section_index(section_index)
    target = Legislation::Paths.law_section_index_file(sway_locale: @sway_locale)
    target.dirname.mkpath
    target.write(JSON.pretty_generate(section_index))
  end

  def detect_status(title)
    text = title.to_s
    return "reserved" if text.include?("Reserved")
    return "repealed" if text.include?("Repealed")

    "active"
  end
end
