# frozen_string_literal: true

# @lat: [[legislation-pipeline#Parsed references are replaced together]]
class ParseSectionsService
  Result = Struct.new(
    :section_reference_ids,
    :operation_ids,
    :amendment_source,
    :no_sections_found,
    :unresolved_keys
  )

  # @lat: [[legislation-pipeline#Law sections stay within their jurisdiction]]
  FUZZY_THRESHOLD_SAME_LENGTH = 97
  FUZZY_THRESHOLD_DIFF_LENGTH = 90

  # @lat: [[legislation-pipeline#The legislation pipeline#Parsed references are replaced together#The first header mention selects the body of law]]
  CHARTER_KEYWORDS = [
    "City Charter",
    "Charter of Baltimore City",
    "Baltimore City Charter",
    "City of Baltimore Charter"
  ].freeze
  CODE_KEYWORDS = [
    "City Code",
    "Public Local Laws",
    "Annotated Code",
    "Maryland Code",
    "Laws of Maryland",
    "United States Code",
    "U.S.C."
  ].freeze

  UNICODE_DASHES = /[-‐‑‒–—―−]/

  # @lat: [[legislation-pipeline#Typographic markup and declared target resolution]]
  CITE_PATTERNS = [
    /§\s*(?<section>(?<article>[A-Z0-9]+)-[A-Z0-9-]+)\b(?!\.[A-Za-z0-9])(?!\s*(?:\([A-Za-z0-9\-‐‑‒–—―−]+\))*\s+of\s+the\s+(?:Article\s*[-‐‑‒–—―−]\s*)?[A-Za-z0-9 \t\-‐‑‒–—―−]+?\s+Article\b)/,
    /Article\s+(?<article>[A-Za-z0-9-]+)\s*,?\s*Sections?\s+(?:§\s*)?(?<section>[A-Za-z0-9.\-‐‑‒–—―−]+(?:\([A-Za-z0-9\-‐‑‒–—―−]+\))*)/i,
    /Article\s*[-‐‑‒–—―−]\s*(?<article>[A-Za-z0-9 \t\-‐‑‒–—―−]+?)\s*,?\s*Sections?\s+(?:§\s*)?(?<section>[A-Za-z0-9.\-‐‑‒–—―−]+(?:\([A-Za-z0-9\-‐‑‒–—―−]+\))*)/i,
    /(?:Sections?\s+(?:§\s*)?|§§?\s*)(?<section>[A-Za-z0-9.\-‐‑‒–—―−]+(?:\([A-Za-z0-9\-‐‑‒–—―−]+\))*)\s+of\s+the\s+(?:Article\s*[-‐‑‒–—―−]\s*)?(?<article>[A-Za-z0-9 \t\-‐‑‒–—―−]+?)\s+Article/i,
    /Title\s+(?<article>\d+)\s*,\s*United\s+States\s+Code\s*,?\s*(?:is\s+amended\s+.*?)?Sections?\s+(?:§\s*)?(?<section>[A-Za-z0-9.-]+)/i,
    /Sections?\s+(?:§\s*)?(?<section>[A-Za-z0-9.-]+)\s+of\s+[Tt]itle\s+(?<article>\d+)\s*,\s*United\s+States\s+Code/i,
    /(?<article>\d+)\s+U\.?S\.?C\.?(?:A\.?)?\s*(?:§\s*|Sections?\s+)?(?<section>[A-Za-z0-9.-]+)/i,
    /(?:Public\s+Law|P\.?L\.?)\s+(?<article>\d+)[-–—](?<section>\d+)/i
  ].freeze

  BY_HEADER_PATTERN = /BY\s+(?:repealing|adding|amending|re-ordaining|re-enacting|reenacting)[^\n]*\n+(?:\s*\d+\s*\n+)?(?:Article\s*[-‐‑‒–—―−.]\s*(?<article>[A-Za-z0-9 \t\-‐‑‒–—―−]+?)|Article\s+(?<article>[A-Za-z0-9-]+)(?:\s*[-‐‑‒–—―−.]\s*[^\n]+)?)\n+(?:\s*\d+\s*\n+)?(?:Sections?\s+)+(?:§\s*)?(?<section>[A-Za-z0-9.\-‐‑‒–—―−]+(?:\([A-Za-z0-9\-‐‑‒–—―−]+\))*)/im

  def initialize(bill:, bill_run: nil, run: nil)
    @bill = bill
    @bill_run = bill_run
    @run = run
  end

  def call
    raise BillProcessingError, "bill ##{@bill.id} has no extracted_text" if @bill.extracted_text.blank?
    sway_locale = @bill.sway_locale

    text = @bill.extracted_text.to_s
    target, target_log = classify_target(text)
    section_refs = extract_section_references(text, sway_locale)
    text_ops = ::Legislation::TextPatternOps.text_pattern_fallback(text)
    markup_ops = ::Legislation::MarkupOps.markup_fallback(text)

    amendment_source =
      if markup_ops.any?
        "markup"
      elsif text_ops.any?
        "text_pattern"
      else
        "none"
      end

    section_ref_ids = [] #: Array[Integer]
    op_ids = [] #: Array[Integer]

    ::ActiveRecord::Base.transaction do
      # @lat: [[legislation-pipeline#Parsed references are replaced together]]
      ::BillAmendmentOperation.where(bill_id: @bill.id).delete_all
      ::BillSectionReference.where(bill_id: @bill.id).delete_all

      section_refs.each_with_index do |sec, idx|
        ref = ::BillSectionReference.create!(
          bill: @bill,
          key: sec[:key],
          article: sec[:article],
          section: sec[:section],
          title: sec[:title],
          anchor: sec[:anchor],
          resolution: sec[:resolution],
          fuzzy_score: sec[:fuzzy_score],
          ordinal: idx,
          authoritative: sec[:authoritative] || false
        )
        section_ref_ids << ref.id
      end

      # @lat: [[legislation-pipeline#The legislation pipeline#Law sections stay within their jurisdiction#Typed citation indexes]]
      ordered_refs = section_refs.each_with_index.map { |sec, idx|
        {
          char_start: locate_section_char_start(text, sec),
          section_ref_id: section_ref_ids[idx],
          target_law_section_id: sec[:target_law_section_id]
        } #: ParseSectionsService::ordered_ref
      }.sort_by { |h| h[:char_start] }

      all_ops = (text_ops + markup_ops).sort_by { |op| op[:char_start].to_i }

      all_ops.each_with_index do |op, op_idx|
        attribution = nearest_preceding_section(op[:char_start], ordered_refs)
        bao = ::BillAmendmentOperation.create!(
          bill: @bill,
          bill_section_reference_id: attribution&.dig(:section_ref_id),
          target_law_section_id: attribution&.dig(:target_law_section_id),
          operation: op[:operation],
          source: op[:source],
          # @lat: [[legislation-pipeline#The legislation pipeline#Parsed references are replaced together#Operation text columns]]
          anchor_text: (op[:operation] == :insert) ? nil : op[:anchor_text],
          replacement_text: (op[:operation] == :insert) ? op[:anchor_text] : nil,
          char_start: op[:char_start],
          char_end: op[:char_end],
          ordinal: op_idx
        )
        op_ids << bao.id
      end

      @bill.update!(
        amendment_source: amendment_source,
        parsing_target: target,
        parsing_target_log: target_log,
        parsed_at: ::Time.current
      )
    end

    unresolved = section_refs.select { |s| s[:resolution] == :unresolved }.pluck(:key)

    Result.new(
      section_reference_ids: section_ref_ids,
      operation_ids: op_ids,
      amendment_source: amendment_source,
      no_sections_found: section_refs.empty?,
      unresolved_keys: unresolved
    )
  rescue ::ActiveRecord::RecordInvalid => e
    raise BillProcessingError, "parse_sections failed for bill ##{@bill.id}: #{e.message[0, 500]}"
  end

  private

  def classify_target(text)
    head = text[0, 4_096].to_s
    charter_hit = earliest_keyword(head, CHARTER_KEYWORDS)
    code_hit = earliest_keyword(head, CODE_KEYWORDS)
    if charter_hit && (code_hit.nil? || charter_hit.first < code_hit.first)
      ["charter", "keyword match: '#{charter_hit.last}'"]
    elsif code_hit
      ["code", "keyword match: '#{code_hit.last}'"]
    else
      ["code", "no charter keywords found; defaulting to code"]
    end
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Parsed references are replaced together#The first header mention selects the body of law]]
  def earliest_keyword(head, keywords)
    found = [] #: Array[[Integer, String]]
    keywords.each do |keyword|
      at = head.index(keyword)
      next if at.nil?

      found << [at, keyword]
    end
    found.min_by { |position, _| position }
  end

  def extract_section_references(text, sway_locale)
    head = text[0, 4_096].to_s
    declared_cites = scan_for_declared_targets(head)
    target_cite = declared_cites.find { |c| !without_amendments_header?(c[:anchor]) } || declared_cites.first
    other_declared_cites = declared_cites.reject { |c| c.equal?(target_cite) }
    raw_cites = deduplicate_cites(other_declared_cites + scan_for_section_cites(text))

    # @lat: [[legislation-pipeline#Law sections stay within their jurisdiction]]
    rows = ::LawSection.by_sway_locale(sway_locale).pluck(:id, :key, :article, :section, :title)
    # @type var exact_index: Hash[String, [Integer, String, String, String, String?]]
    exact_index = {}
    rows.each do |row|
      key_str = row[1].to_s
      title_val = row[4].is_a?(::String) ? row[4] : nil #: String?
      exact_index[key_str] = [
        Integer(row[0]),
        key_str,
        row[2].to_s,
        row[3].to_s,
        title_val
      ]
    end
    locale_keys = exact_index.keys
    title_prefix_map = build_title_prefix_map(exact_index)

    refs = [] #: Array[section_ref_payload]

    if target_cite
      target_key = normalize_to_key(target_cite[:article], target_cite[:section])
      resolved_target = resolve_against_indexed_law_sections(
        target_key, exact_index, locale_keys,
        article: target_cite[:article], section: target_cite[:section],
        title_prefix_map: title_prefix_map
      )
      refs << {
        key: resolved_target[:key],
        article: resolved_target[:article] || target_cite[:article],
        section: resolved_target[:section] || target_cite[:section],
        title: resolved_target[:title],
        anchor: target_cite[:anchor],
        resolution: resolved_target[:resolution],
        fuzzy_score: resolved_target[:fuzzy_score],
        target_law_section_id: resolved_target[:target_law_section_id],
        authoritative: true
      }
    end

    raw_cites.each do |cite|
      next if target_cite && duplicate_of_target?(cite, target_cite, title_prefix_map)

      key = normalize_to_key(cite[:article], cite[:section])
      resolved = resolve_against_indexed_law_sections(
        key, exact_index, locale_keys,
        article: cite[:article], section: cite[:section],
        title_prefix_map: title_prefix_map
      )
      refs << {
        key: resolved[:key],
        article: resolved[:article] || cite[:article],
        section: resolved[:section] || cite[:section],
        title: resolved[:title],
        anchor: cite[:anchor],
        resolution: resolved[:resolution],
        fuzzy_score: resolved[:fuzzy_score],
        target_law_section_id: resolved[:target_law_section_id],
        authoritative: false
      }
    end

    refs
  end

  def scan_for_declared_target(head)
    declared = scan_for_declared_targets(head)
    declared.find { |c| !without_amendments_header?(c[:anchor]) } || declared.first
  end

  def scan_for_declared_targets(head)
    # @type var cites: Array[cite_payload]
    cites = []
    head.to_enum(:scan, BY_HEADER_PATTERN).each do
      m = ::Regexp.last_match
      next if m.nil?
      cites << {
        article: normalize_citation_article(m[:article].to_s),
        section: normalize_citation_section(m[:section].to_s),
        anchor: m[0].to_s,
        char_start: m.begin(0).to_i
      }
    end
    cites
  end

  def without_amendments_header?(anchor)
    anchor.to_s.lines.first.to_s.match?(/without\s+amendments/i)
  end

  def duplicate_of_target?(cite, target_cite, title_prefix_map)
    cite_sec = cite[:section].to_s
    target_sec = target_cite[:section].to_s
    cite_art = cite[:article].to_s
    target_art = target_cite[:article].to_s

    if cite_sec.casecmp?(target_sec)
      return true if cite_art.casecmp?(target_art)

      canon_cite_art = title_prefix_map[cite_art.downcase] || cite_art
      canon_target_art = title_prefix_map[target_art.downcase] || target_art
      return true if canon_cite_art.casecmp?(canon_target_art)

      if cite_sec.downcase.start_with?("#{cite_art.downcase}-") && target_art.match?(/\A\d+[A-Za-z]?\z/)
        return true
      end
    end

    cite_art.casecmp?(target_art) && target_sec.downcase.start_with?("#{cite_sec.downcase}-")
  end

  def scan_for_section_cites(text)
    # @type var cites: Array[cite_payload]
    cites = []
    CITE_PATTERNS.each do |regex|
      text.to_enum(:scan, regex).each do
        m = ::Regexp.last_match
        next if m.nil?
        cites << {
          article: normalize_citation_article(m[:article].to_s),
          section: normalize_citation_section(m[:section].to_s),
          anchor: m[0].to_s,
          char_start: m.begin(0).to_i
        }
      end
    end
    deduplicate_cites(cites)
  end

  def deduplicate_cites(cites)
    # @type var seen: Hash[Array[String], bool]
    seen = {}
    cites.each_with_object([]) do |c, acc|
      k = [c[:article].to_s.downcase, c[:section].to_s.downcase]
      next if seen[k]
      seen[k] = true
      acc << c
    end
  end

  def normalize_citation_article(raw_article)
    raw_article
      .gsub(UNICODE_DASHES, "-")
      .gsub(/\s*-\s*/, " - ")
      .gsub(/[ \t]+/, " ")
      .strip
  end

  def normalize_citation_section(raw_section)
    raw_section
      .gsub(UNICODE_DASHES, "-")
      .sub(/(?:\([A-Za-z0-9-]+\))+\z/, "")
      .strip
  end

  def build_title_prefix_map(exact_index)
    # @type var map: Hash[String, String]
    map = {}
    exact_index.each_value do |r|
      next unless r[4]
      if (m = r[4].to_s.match(/\AArticle\s*[-‐‑‒–—―−]\s*(.+?)\s*§/i))
        norm_name = normalize_citation_article(m[1].to_s).downcase
        map[norm_name] ||= r[2].to_s
      end
    end
    map
  end

  def normalize_to_key(article_id, section_num)
    "art_#{article_id.to_s.strip}__sec_#{section_num.to_s.strip}"
  end

  def derive_short_key(key)
    if (m = key.match(/\Aart_([A-Z0-9-]+)__sec_\1-([A-Z0-9-]+)\z/i))
      "art_#{m[1]}__sec_#{m[2]}"
    end
  end

  # @lat: [[legislation-pipeline#Law sections stay within their jurisdiction]]
  def resolve_against_indexed_law_sections(key, exact_index, locale_keys, article: nil, section: nil, title_prefix_map: nil)
    if (row = exact_index[key])
      return {
        key: row[1].to_s,
        article: row[2].to_s,
        section: row[3].to_s,
        title: row[4],
        resolution: :exact,
        fuzzy_score: nil,
        target_law_section_id: row[0]
      }
    end

    if (short_key = derive_short_key(key)) && (row = exact_index[short_key])
      return {
        key: row[1].to_s,
        article: row[2].to_s,
        section: row[3].to_s,
        title: row[4],
        resolution: :exact,
        fuzzy_score: nil,
        target_law_section_id: row[0]
      }
    end

    if (title_key = key.sub(/\Aart_/, "title_")) && (row = exact_index[title_key])
      return {
        key: row[1].to_s,
        article: row[2].to_s,
        section: row[3].to_s,
        title: row[4],
        resolution: :exact,
        fuzzy_score: nil,
        target_law_section_id: row[0]
      }
    end

    title_prefix_map ||= build_title_prefix_map(exact_index)

    if article && section
      usc_key = "#{article}_usc_#{section}"
      if (row = exact_index[usc_key])
        return {
          key: row[1].to_s,
          article: row[2].to_s,
          section: row[3].to_s,
          title: row[4],
          resolution: :exact,
          fuzzy_score: nil,
          target_law_section_id: row[0]
        }
      end

      art_s = article.to_s.strip
      sec_s = section.to_s.strip
      canonical_article = title_prefix_map[art_s.downcase]

      if canonical_article
        canonical_key = normalize_to_key(canonical_article, sec_s)
        if (row = exact_index[canonical_key])
          return {
            key: row[1].to_s,
            article: row[2].to_s,
            section: row[3].to_s,
            title: row[4],
            resolution: :exact,
            fuzzy_score: nil,
            target_law_section_id: row[0]
          }
        end
      end

      found_row = exact_index.values.find do |r|
        (
          r[2].to_s.casecmp?(art_s) ||
          r[2].to_s.casecmp?("title_#{art_s}") ||
          r[2].to_s.casecmp?("art_#{art_s}") ||
          (canonical_article && r[2].to_s.casecmp?(canonical_article)) ||
          r[4].to_s.downcase.start_with?("article - #{art_s.downcase} §")
        ) && r[3].to_s.casecmp?(sec_s)
      end
      if found_row
        return {
          key: found_row[1].to_s,
          article: found_row[2].to_s,
          section: found_row[3].to_s,
          title: found_row[4],
          resolution: :exact,
          fuzzy_score: nil,
          target_law_section_id: found_row[0]
        }
      end
    end

    best_key = nil #: String?
    best_score = -1 #: Integer
    locale_keys.each do |candidate|
      score = ::ParseSectionsService::FuzzyRatio.ratio(key, candidate)
      threshold = (candidate.length == key.length) ? FUZZY_THRESHOLD_SAME_LENGTH : FUZZY_THRESHOLD_DIFF_LENGTH
      next if score < threshold
      if best_key.nil? || score > best_score
        best_key = candidate
        best_score = score
      end
    end

    # @lat: [[legislation-pipeline#The legislation pipeline#Law sections stay within their jurisdiction#Typed citation indexes]]
    matched_key = best_key
    if matched_key.is_a?(::String)
      if (row = exact_index[matched_key])
        return {
          key: row[1].to_s,
          article: row[2].to_s,
          section: row[3].to_s,
          title: row[4],
          resolution: :fuzzy,
          fuzzy_score: best_score,
          target_law_section_id: row[0]
        }
      end
    end

    if article && section
      art_s = article.to_s.strip
      sec_s = section.to_s.strip
      canonical_article = title_prefix_map[art_s.downcase]
      if canonical_article
        return {
          key: normalize_to_key(canonical_article, sec_s),
          article: canonical_article,
          section: sec_s,
          title: nil,
          resolution: :unresolved,
          fuzzy_score: nil,
          target_law_section_id: nil
        }
      end
    end

    {
      key: key,
      article: nil,
      section: nil,
      title: nil,
      resolution: :unresolved,
      fuzzy_score: nil,
      target_law_section_id: nil
    }
  end

  def locate_section_char_start(text, sec)
    needle = sec[:anchor].to_s
    return ::Float::INFINITY if needle.empty?
    return ::Float::INFINITY if !sec[:authoritative] && needle.match?(/\ABY\s+/i)
    idx = text.index(needle)
    idx.nil? ? ::Float::INFINITY : idx
  end

  def nearest_preceding_section(op_char_start, ordered_refs)
    ordered_refs.rfind { |r| r[:char_start] <= op_char_start } || ordered_refs.first
  end
end
