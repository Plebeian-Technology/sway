# frozen_string_literal: true

require "json"
require "fileutils"
require "nokogiri"

# @lat: [[legislation-pipeline#Upstream jurisdiction adapters]]
module Legislation
  module Adapters
    class GenericLawAdapter
      CHARTER_FILE = "charter.xml"
      USLM_NAMESPACE = "http://xml.house.gov/schemas/uslm/1.0"
      PDF_SECTION_DASHES = /[-‐‑‒–—−]/
      PDF_SECTION_MARKER = /\A§([0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*[-‐‑‒–—−][0-9A-Za-z.‐‑‒–—−-]+?)(?:\.(?=\s|\z)|\z)\s*(.*)\z/u
      PDF_SECTION_SPACED_MARKER = /\A§\s+([0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*[-‐‑‒–—−][0-9A-Za-z.‐‑‒–—−-]+?)\.(?:\s+(.*)|\z)/u
      PDF_SECTION_START_REGEX = PDF_SECTION_MARKER
      PDF_STRUCTURAL_DIVIDER = /\A(?:Title|Subtitle|Part|Subpart|Chapter|Division)\s+[0-9IVXLCDM]+[A-Za-z0-9–-]*\.(?:\s+.*)?\z/
      PDF_ARTICLE_DIVIDER = /\AArticle\s*[-‐‑‒–—−]\s*.+\z/i
      STATUS_NOTE_REGEX = /\A(?:\[.*\]|Repealed\b|Reserved\b|Abrogated\b|Terminated\b|Transferred\b|Redesignated\b)/i
      EFFECTIVE_BANNER_REGEX = /\A(?:\*\*|\/\/|IN\s+EFFECT\b|TAKES\s+EFFECT\b|NOT\s+IN\s+EFFECT\b|CONTINGENCY\b)/i

      attr_reader :config, :engine, :retrieval, :parsing, :base_url, :connection, :service

      def initialize(config_or_locale = {}, connection: nil, service: nil, **kwargs)
        @connection = connection
        @service = service
        base_config = extract_config(config_or_locale)
        @config = kwargs.any? ? base_config.merge(kwargs) : base_config
        raw_engine = @config[:engine].presence
        raw_retrieval = @config[:retrieval].presence || @config[:retrieval_strategy].presence
        raw_parsing = @config[:parsing].presence || @config[:parser_format].presence

        @engine = (raw_engine || raw_retrieval || :generic_rest).to_sym
        @retrieval = (raw_retrieval || @engine).to_sym
        @parsing = (raw_parsing || @engine).to_sym
        @base_url = @config[:base_url]
        @parsed_sections = 0
        @variant_titles = {}
      end

      def load_corpus(run:, sway_locale:, law_root:, service: nil)
        if @retrieval == :unavailable || @engine == :unavailable
          raise StageError, "fetch_law: law acquisition is unavailable for #{sway_locale&.name}"
        end

        case @retrieval
        when :configured_pdf_catalog
          Legislation::RemotePdfLawCorpusService.new(
            sway_locale: sway_locale,
            law_root: law_root,
            http: @connection
          ).call
          if @parsing == :pdf_statute_sections
            load_pdf_corpus(sway_locale: sway_locale, law_root: law_root)
          else
            load_raw_corpus(sway_locale: sway_locale, law_root: law_root)
          end
        when :akoma_ntoso, :git_repo, :git_tarball
          load_akoma_ntoso_corpus(run: run, sway_locale: sway_locale, law_root: law_root, service: service)
        when :uslm_xml, :congress_service
          if defined?(Legislation::CongressLawCorpusService)
            stats = {"sections_upserted" => 0, "files_written" => 0, "articles_processed" => 0}
            section_index = {}
            seen_titles = Set.new
            @parsed_sections = 0
            @variant_titles = {}

            yielded = false
            begin
              LawSection.transaction do
                Legislation::CongressLawCorpusService.new(law_root: law_root).call do |raw_root|
                  yielded = true
                  Pathname.glob(raw_root.join("**", "*.xml").to_s).sort.each do |path|
                    before_count = @parsed_sections
                    ingest_xml(path, law_root, sway_locale, stats, section_index, seen_titles)
                    if @parsed_sections == before_count
                      raise StageError, "fetch_law: US Code XML contains no statutory sections"
                    end
                  end
                  Pathname.glob(raw_root.join("**", "*.json").to_s).sort.each do |path|
                    ingest_json(path, law_root, sway_locale, stats, section_index, seen_titles)
                  end
                  raise StageError, "fetch_law: US Code corpus contains no statutory sections" if section_index.empty?
                end
              end
            rescue JSON::ParserError => e
              raise StageError, "fetch_law: malformed US Code corpus: #{e.message.to_s[0, 300]}"
            end

            if yielded
              stats["articles_processed"] = seen_titles.size

              index_file = Legislation::Paths.law_section_index_file(sway_locale: sway_locale)
              FileUtils.mkdir_p(index_file.dirname)
              Legislation::AtomicWrite.write(index_file) do |temporary_index|
                File.write(temporary_index, JSON.pretty_generate(section_index))
              end
              return {
                "sections_upserted" => stats.fetch("sections_upserted", 0),
                "files_written" => stats.fetch("files_written", 0),
                "articles_processed" => stats.fetch("articles_processed", 0)
              }
            end
          end
          load_raw_corpus(sway_locale: sway_locale, law_root: law_root)
        when :generic_xml, :generic_rest, :generic_html, :local_raw, :filesystem, :local
          if @parsing == :pdf_statute_sections
            load_pdf_corpus(sway_locale: sway_locale, law_root: law_root)
          else
            load_raw_corpus(sway_locale: sway_locale, law_root: law_root)
          end
        else
          raise StageError, "fetch_law: unsupported law engine #{@engine.inspect}"
        end
      end

      private

      def load_pdf_corpus(sway_locale:, law_root:)
        raw_root = resolve_configured_local_dir(law_root)
        pdf_paths = Pathname.glob(raw_root.join("*.pdf").to_s).sort
        if pdf_paths.empty?
          raise StageError, "fetch_law: missing #{sway_locale.name} PDF law corpus under #{raw_root}"
        end

        sections = []
        article_codes = Set.new
        pdf_paths.each do |path|
          article = path.basename.sub_ext("").to_s.downcase
          unless article.match?(/\Ag[a-z0-9]+\z/) && path.file? && !path.symlink?
            raise StageError, "fetch_law: invalid statutory article PDF #{path.basename}"
          end

          signature = path.binread(5)
          raise StageError, "fetch_law: #{path.basename} has no PDF signature" unless signature == "%PDF-"

          text = MupdfExtractor.new(path.to_s).call
          article_sections = parse_pdf_article(text, article, path)
          raise StageError, "fetch_law: #{path.basename} contains no statutory sections" if article_sections.empty?

          sections.concat(article_sections)
          article_codes << article
        rescue StageError
          raise
        rescue => e
          raise StageError, "fetch_law: could not parse #{path.basename}: #{e.message.to_s.lines.first.to_s.strip[0, 250]}"
        end

        persist_pdf_sections(sections, article_codes, sway_locale, law_root)
      end

      def resolve_configured_local_dir(law_root)
        value = (@config[:local_path] || @config["local_path"]).to_s
        relative = Pathname.new(value)
        parts = value.split(/[\\\/]/)
        root = law_root.expand_path
        raw_root = root.join(relative).cleanpath
        prefix = root.to_s + File::SEPARATOR
        if value.blank? || relative.absolute? || value.include?("\\") || parts.include?("..") ||
            !raw_root.to_s.start_with?(prefix)
          raise StageError, "fetch_law: local_path must stay inside the law root"
        end

        current = root
        parts.reject(&:empty?).each do |part|
          current = current.join(part)
          raise StageError, "fetch_law: local_path cannot traverse symlinks" if current.symlink?
        end
        raw_root
      rescue ArgumentError => e
        raise StageError, "fetch_law: invalid local_path: #{e.message}"
      end
      alias_method :configured_raw_root, :resolve_configured_local_dir

      def parse_pdf_article(text, article, path)
        pages = text.to_s.split("\f", -1)
        has_compact_headers = text.match?(/^§[0-9]/)
        header_regex = has_compact_headers ? PDF_SECTION_MARKER : PDF_SECTION_SPACED_MARKER

        first_page = pages.first.to_s
        article_match = first_page.lines.map(&:strip).find { |l| l.match?(/\AArticle\s*[-‐‑‒–—−]\s*(.+)\z/i) }&.match(/\AArticle\s*[-‐‑‒–—−]\s*(.+)\z/i)
        article_heading = if article_match
          name = article_match[1].to_s.gsub(PDF_SECTION_DASHES, "-").gsub(/\s*-\s*/, " - ").gsub(/\s+/, " ").strip
          "Article - #{name}"
        end

        repeated_headers = pages.flat_map do |page|
          page.lines.map(&:strip).compact_blank.take_while { |line| !line.match?(header_regex) }.reject do |line|
            line.match?(/[.;:]\z/) || line.match?(/\A\([a-z0-9]+\)/i)
          end
        end.tally.select { |_line, count| count > 1 }.keys.to_set

        sections = []
        # @type var current: Hash[Symbol, untyped]?
        current = nil
        first_malformed_marker = nil
        any_has_content = false

        pages.each do |page|
          in_header = true
          page.lines.each do |raw_line|
            line = raw_line.to_s.strip
            next if strip_pdf_noise?(line)

            if in_header && repeated_headers.include?(line)
              next
            end
            in_header = false

            if line.start_with?("§")
              match = line.match(header_regex)
              if match
                has_content = append_pdf_section(sections, current, article, path, article_heading)
                any_has_content ||= has_content
                match2 = match[2].to_s.strip
                title = ""
                body_lines = []
                has_initial_content = false
                if match2.present?
                  if match2.match?(EFFECTIVE_BANNER_REGEX)
                    body_lines << match2
                    body_lines << ""
                  else
                    title = normalize_pdf_heading(match2)
                    has_initial_content = true
                  end
                end
                current = {
                  section: canonical_pdf_section(match[1]),
                  title: title,
                  body_lines: body_lines,
                  has_content: has_initial_content
                }
              elsif current
                current[:body_lines] << line
                current[:has_content] = true
              else
                first_malformed_marker ||= line
              end
            elsif current
              current[:body_lines] << line
              current[:has_content] = true
            end
          end
        end
        has_content = append_pdf_section(sections, current, article, path, article_heading)
        any_has_content ||= has_content

        if sections.empty?
          if first_malformed_marker
            raise StageError, "fetch_law: malformed section marker in #{path.basename}: #{first_malformed_marker.to_s[0, 120]}"
          else
            raise StageError, "fetch_law: #{path.basename} contains no statutory sections"
          end
        end

        unless any_has_content
          raise StageError, "fetch_law: incomplete statutory section in #{path.basename}"
        end

        sections
      end

      def strip_pdf_noise?(line)
        return true if line.blank?
        return true if line.match?(/\A(?:page\s+)?\d+\z/i)
        return true if line.match?(/\A-\s*\d+\s*-\z/)
        return true if line.match?(PDF_STRUCTURAL_DIVIDER)
        return true if line.match?(PDF_ARTICLE_DIVIDER)

        false
      end

      def append_pdf_section(sections, current, article, path, article_heading = nil)
        return false if current.nil?

        body = normalize_pdf_body(current[:body_lines])
        title = current[:title].to_s.strip
        has_content = current[:has_content] == true

        if title.present?
          body = title if body.blank?
        elsif current[:body_lines].size == 1 && current[:body_lines].first.to_s.strip.match?(STATUS_NOTE_REGEX)
          note = normalize_pdf_heading(current[:body_lines].first)
          body = note
          title = article_heading ? "#{article_heading} § #{current[:section]}" : note
          has_content = true
        elsif current[:body_lines].empty?
          title = article_heading ? "#{article_heading} § #{current[:section]}" : "Repealed or reserved"
          body = "Repealed or reserved"
          has_content = false
        else
          title = article_heading ? "#{article_heading} § #{current[:section]}" : "§ #{current[:section]}"
          if body.blank?
            body = "Repealed or reserved"
            has_content = false
          else
            has_content = true
          end
        end

        sections << {
          article: article,
          section: current.fetch(:section),
          title: title,
          body: body
        }
        has_content
      end

      def canonical_pdf_section(value)
        value.to_s.gsub(PDF_SECTION_DASHES, "-").gsub(/\s+/, "")
      end

      def normalize_pdf_heading(value)
        value.to_s.gsub(/\s+/, " ").strip.sub(/[.:]+\z/, "").strip
      end

      def normalize_pdf_body(lines)
        paragraphs = []
        current = []
        lines.each do |line|
          if line.blank?
            paragraphs << current.join(" ") if current.any?
            current = []
          else
            current << line.to_s.strip
          end
        end
        paragraphs << current.join(" ") if current.any?
        paragraphs.join("\n\n").gsub(/[ \t]+/, " ").strip
      end

      def persist_pdf_sections(sections, article_codes, sway_locale, law_root)
        merged_sections = []
        # @type var merged_by_key: Hash[String, Hash[Symbol, untyped]]
        merged_by_key = {}
        sections.each do |section|
          key = "art_#{section.fetch(:article)}__sec_#{section.fetch(:section)}"
          if (existing = merged_by_key[key])
            existing[:body] = "#{existing[:body]}\n\n---\n\n#{section.fetch(:body)}"
            existing_titles = existing[:title].to_s.split("; ").map(&:strip)
            new_title = section.fetch(:title).to_s.strip
            existing[:title] = (existing_titles + [new_title]).compact_blank.uniq.join("; ")
          else
            entry = section.dup
            merged_by_key[key] = entry
            merged_sections << entry
          end
        end

        section_index = {}
        merged_sections.each do |section|
          key = "art_#{section.fetch(:article)}__sec_#{section.fetch(:section)}"
          section_index[key] = {
            "path" => "code/#{section.fetch(:article)}/#{section.fetch(:section)}.md",
            "article" => section.fetch(:article),
            "title" => section.fetch(:title),
            "status" => "active"
          }
        end

        law_root.mkpath
        index_file = Legislation::Paths.law_section_index_file(sway_locale: sway_locale)
        code_root = law_root.join("code")
        old_code = law_root.join(".code-backup-#{SecureRandom.hex(6)}")
        old_index = law_root.join(".section-index-backup-#{SecureRandom.hex(6)}")
        had_code = false
        had_index = false
        new_code = false
        new_index = false

        Dir.mktmpdir(".pdf-law-sections-", law_root.to_s) do |directory|
          stage = Pathname.new(directory)
          staged_code = stage.join("code")
          staged_code.mkpath
          merged_sections.each do |section|
            path = staged_code.join(section.fetch(:article), "#{section.fetch(:section)}.md")
            path.dirname.mkpath
            path.write(section.fetch(:body))
          end
          staged_index = stage.join("section_index.json")
          staged_index.write(JSON.pretty_generate(section_index))

          begin
            LawSection.transaction do
              merged_sections.each do |section|
                FetchLawService::LawSectionUpsert.call(
                  sway_locale: sway_locale,
                  key: "art_#{section.fetch(:article)}__sec_#{section.fetch(:section)}",
                  article: section.fetch(:article),
                  section: section.fetch(:section),
                  title: section.fetch(:title),
                  body: section.fetch(:body),
                  source_path: "code/#{section.fetch(:article)}/#{section.fetch(:section)}.md"
                )
              end

              if code_root.exist?
                File.rename(code_root, old_code)
                had_code = true
              end
              if index_file.exist?
                File.rename(index_file, old_index)
                had_index = true
              end
              File.rename(staged_code, code_root)
              new_code = true
              File.rename(staged_index, index_file)
              new_index = true
            end
          rescue
            FileUtils.rm_rf(code_root) if new_code && code_root.exist?
            FileUtils.rm_f(index_file) if new_index && index_file.exist?
            File.rename(old_code, code_root) if had_code && old_code.exist?
            File.rename(old_index, index_file) if had_index && old_index.exist?
            raise
          end
        end

        FileUtils.rm_rf(old_code) if had_code
        FileUtils.rm_f(old_index) if had_index
        {
          "sections_upserted" => merged_sections.size,
          "files_written" => merged_sections.size,
          "articles_processed" => article_codes.size
        }
      end

      def extract_config(input)
        return input.deep_symbolize_keys if input.is_a?(Hash)

        rules = if input.is_a?(SwayLocale)
          @sway_locale = input
          input.jurisdiction_rules
        elsif input.is_a?(SwayLocale::JurisdictionRules)
          input
        elsif input.respond_to?(:jurisdiction_rules)
          input.jurisdiction_rules
        elsif input.respond_to?(:law_rules)
          input
        end

        if rules&.respond_to?(:law_rules)
          l_rules = rules.law_rules
          if l_rules.is_a?(Hash) && l_rules.any?
            cfg = l_rules.deep_symbolize_keys
            if cfg[:retrieval].blank? && rules.respond_to?(:law_retrieval)
              ret = rules.law_retrieval
              cfg[:retrieval] = ret.to_sym if ret.present?
            elsif cfg[:retrieval].blank? && rules.respond_to?(:retrieval_for)
              ret = rules.retrieval_for(:law)
              cfg[:retrieval] = ret.to_sym if ret.present?
            end
            if cfg[:parsing].blank? && rules.respond_to?(:law_parsing)
              pr = rules.law_parsing
              cfg[:parsing] = pr.to_sym if pr.present?
            elsif cfg[:parsing].blank? && rules.respond_to?(:parsing_for)
              pr = rules.parsing_for(:law)
              cfg[:parsing] = pr.to_sym if pr.present?
            end
            return cfg
          end
        end

        {}
      end

      def load_raw_corpus(sway_locale:, law_root:)
        if @parsing == :pdf_statute_sections || @parsing.to_s == "pdf_statute_sections"
          return load_pdf_corpus(sway_locale: sway_locale, law_root: law_root)
        end

        raw_root = if @config[:local_path].present? || @config["local_path"].present?
          resolve_configured_local_dir(law_root)
        else
          [law_root.join("code-xml"), law_root.join("raw"), law_root].find(&:exist?) || law_root.join("raw")
        end

        raise StageError, "fetch_law: missing #{sway_locale&.name} law corpus under #{law_root}" unless raw_root.exist?

        xml_files = Pathname.glob(raw_root.join("**", "*.xml").to_s).sort
        json_files = Pathname.glob(raw_root.join("**", "*.json").to_s).sort
        if xml_files.empty? && json_files.empty?
          raise StageError, "fetch_law: missing #{sway_locale&.name} law corpus under #{law_root}"
        end

        stats = {"sections_upserted" => 0, "files_written" => 0, "articles_processed" => 0}
        section_index = {}
        seen_articles = Set.new

        xml_files.each { |f| ingest_xml(f, law_root, sway_locale, stats, section_index, seen_articles) }
        json_files.each { |f| ingest_json(f, law_root, sway_locale, stats, section_index, seen_articles) }

        if section_index.empty?
          raise StageError, "fetch_law: statutory law corpus contains no sections"
        end

        stats["articles_processed"] = seen_articles.size

        index_file = Legislation::Paths.law_section_index_file(sway_locale: sway_locale)
        FileUtils.mkdir_p(index_file.dirname)
        File.write(index_file, JSON.pretty_generate(section_index))

        stats #: untyped
      end

      def ingest_xml(path, law_root, sway_locale, stats, section_index, seen_articles)
        if uslm_file?(path)
          ingest_uslm_file(path, law_root, sway_locale, stats, section_index, seen_articles)
          return
        end

        doc = Nokogiri::XML(File.read(path)) { |config| config.strict.nonet }

        if doc.css("article").any?
          doc.css("article").each do |art_node|
            article_name = art_node["name"] || art_node["title"] || path.basename.sub_ext("").to_s
            seen_articles << article_name

            art_node.css("section").each do |sec_node|
              number = (sec_node["number"] || sec_node["id"])&.to_s&.strip
              title = (sec_node["heading"] || sec_node["title"] || sec_node["name"])&.to_s&.strip || ""
              body = (sec_node.at_css("body")&.text || sec_node.text).to_s.strip
              if number.blank? || body.blank?
                SwayLogging.warn("[GenericLawAdapter] skipping section with blank number or body in #{path}: article=#{article_name} number=#{number.inspect}")
                next
              end

              record_section(article_name, number, title, body, law_root, sway_locale, stats, section_index)
            end
          end
        elsif doc.xpath("//title").any?
          doc.xpath("//title").each do |title_node|
            title_num = (title_node["number"] || title_node["name"])&.to_s&.sub(/\ATitle\s+/i, "")&.strip
            title_num = path.basename.sub_ext("").to_s if title_num.blank?
            seen_articles << title_num

            title_node.xpath(".//section").each do |sec_node|
              number = (sec_node["number"] || sec_node["id"])&.to_s&.strip
              title = (sec_node["heading"] || sec_node["title"] || sec_node["name"])&.to_s&.strip || ""
              body = (sec_node.at_xpath("./body")&.text || sec_node.text).to_s.strip
              if number.blank? || body.blank?
                SwayLogging.warn("[GenericLawAdapter] skipping section with blank number or body in #{path}: title=#{title_num} number=#{number.inspect}")
                next
              end

              record_section(title_num, number, title, body, law_root, sway_locale, stats, section_index)
            end
          end
        else
          doc.xpath("//section[@title and @number]").each do |sec_node|
            title_num = sec_node["title"].to_s.sub(/\ATitle\s+/i, "").strip
            number = (sec_node["number"] || sec_node["id"])&.to_s&.strip
            next if title_num.blank? || number.blank?

            seen_articles << title_num
            title = (sec_node["heading"] || sec_node["title"] || sec_node["name"])&.to_s&.strip || ""
            body = (sec_node.at_xpath("./body")&.text || sec_node.text).to_s.strip
            next if body.blank?

            record_section(title_num, number, title, body, law_root, sway_locale, stats, section_index)
          end
        end
      end

      def uslm_file?(path)
        File.open(path) do |input|
          reader = Nokogiri::XML::Reader(input, nil, nil, Nokogiri::XML::ParseOptions::NONET)
          reader.each do |node|
            next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT

            return node.namespace_uri == USLM_NAMESPACE
          end
        end
        false
      end

      def ingest_uslm_file(path, law_root, sway_locale, stats, section_index, seen_titles)
        # @type var title_num: String?
        # @type var main_depth: Integer?
        # @type var skip_depth: Integer?
        title_num = nil
        main_depth = nil
        skip_depth = nil
        File.open(path) do |input|
          reader = Nokogiri::XML::Reader(input, nil, nil, Nokogiri::XML::ParseOptions::NONET)
          reader.each do |node|
            next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
            next unless node.namespace_uri == USLM_NAMESPACE
            next if skip_depth && node.depth > skip_depth

            skip_depth = nil
            if %w[notes sourceCredit quotedContent].include?(node.local_name)
              skip_depth = node.depth
              next
            end
            main_depth = node.depth if node.local_name == "main"
            if node.local_name == "title" && main_depth && node.depth == main_depth + 1
              title_num = node.attribute("identifier").to_s[/\A\/us\/usc\/t(\d+a?)\z/, 1]
              seen_titles << title_num if title_num
            end
            next unless title_num && node.local_name == "section"

            section_num = node.attribute("identifier").to_s[/\A\/us\/usc\/t#{Regexp.escape(title_num)}\/s([^\/]+)\z/, 1]
            next unless section_num

            section_node = Nokogiri::XML(node.outer_xml) { |config| config.strict.nonet }.root
            next unless section_node

            heading = section_node.at_xpath("./u:heading", {"u" => USLM_NAMESPACE})&.text.to_s.strip
            heading = "Section #{section_num}" if heading.empty?
            body = statutory_body(section_node).presence || heading
            status = node.attribute("status").to_s
            record_section(title_num, section_num, heading, body, law_root, sway_locale, stats, section_index, status: status)
            skip_depth = node.depth
          end
        end
        raise StageError, "fetch_law: US Code XML has no statutory main title" unless title_num
      end

      def statutory_body(section_node)
        section_node.xpath("./u:num | ./u:heading | .//u:notes | .//u:sourceCredit | .//u:toc", {"u" => USLM_NAMESPACE}).remove
        section_node.xpath(".//u:content | .//u:p | .//u:subsection | .//u:paragraph | .//u:subparagraph | .//u:clause | .//u:subclause | .//u:item | .//u:chapeau | .//u:continuation", {"u" => USLM_NAMESPACE}).each do |block|
          block.add_next_sibling(Nokogiri::XML::Text.new("\n", section_node.document))
        end
        section_node.text.gsub(/[ \t]+/, " ").gsub(/ *\n */, "\n").gsub(/\n{3,}/, "\n\n").strip
      end

      def ingest_json(path, law_root, sway_locale, stats, section_index, seen_articles)
        data = begin
          JSON.parse(File.read(path))
        rescue JSON::ParserError => e
          SwayLogging.warn("[GenericLawAdapter] failed to parse JSON in #{path}: #{e.message}")
          {}
        end
        article_name = (data.is_a?(Hash) && (data["article"] || data[:article])) || path.basename.sub_ext("").to_s
        seen_articles << article_name.to_s

        sections = if data.is_a?(Array)
          data
        elsif data.is_a?(Hash)
          data["sections"] || data[:sections] || []
        else
          []
        end

        sections.each do |sec|
          next unless sec.is_a?(Hash)

          number = (sec["number"] || sec[:number] || sec["id"] || sec[:id])&.to_s&.strip
          title = (sec["title"] || sec[:title] || sec["name"] || sec[:name])&.to_s&.strip || ""
          body = (sec["body"] || sec[:body]).to_s.strip
          if number.blank? || body.blank?
            SwayLogging.warn("[GenericLawAdapter] skipping section with blank number or body in #{path}: article=#{article_name} number=#{number.inspect}")
            next
          end

          record_section(article_name, number, title, body, law_root, sway_locale, stats, section_index)
        end
      end

      def record_section(article, section, title, body, law_root, sway_locale, stats, section_index, status: "")
        if section.blank? || body.blank?
          SwayLogging.warn("[GenericLawAdapter] skipping section with blank section number or body: article=#{article} section=#{section.inspect}")
          return
        end

        art_str = article.to_s
        sec_str = section.to_s

        if %i[uslm_xml uslm].include?(@parsing) || @engine == :uslm_xml
          if art_str.blank? || art_str.match?(/[\/\\\x00]/) || %w[. ..].include?(art_str) || sec_str.blank? || sec_str.match?(/[\/\\\x00]/) || %w[. ..].include?(sec_str)
            raise StageError, "fetch_law: unsafe US Code section identifier"
          end
          @parsed_sections = (@parsed_sections || 0) + 1
          key = "art_#{art_str}__sec_#{sec_str}"
          source_path = "code/#{art_str}/#{sec_str}.md"
          status = status.presence || title[/repealed|reserved|transferred|omitted/i]&.downcase || "active"
          @variant_titles ||= {}
          previous = section_index[key]
          if previous
            previous_body = law_root.join(source_path).read
            unless @variant_titles.key?(key)
              @variant_titles[key] = [previous.fetch("title")]
              previous_body = "## #{previous.fetch("title")}\n\n#{previous_body}"
            end
            body = "#{previous_body}\n\n---\n\n## #{title}\n\n#{body}"
            @variant_titles.fetch(key) << title unless @variant_titles.fetch(key).include?(title)
            title = @variant_titles.fetch(key).join("; ")
            status = [previous.fetch("status"), status].include?("active") ? "active" : previous.fetch("status")
          end
        else
          key = "art_#{art_str}__sec_#{sec_str}"
          source_path = "code/#{art_str}/#{sec_str}.md"
          status = "active"
        end

        begin
          FetchLawService::LawSectionUpsert.call(
            sway_locale: sway_locale,
            key: key,
            article: art_str,
            section: sec_str,
            title: title,
            body: body,
            source_path: source_path
          )
        rescue ActiveRecord::RecordInvalid => e
          SwayLogging.warn("[GenericLawAdapter] validation failed for section #{key}: #{e.message}")
          return
        end
        stats["sections_upserted"] += 1 unless previous

        abs_path = law_root.join(source_path)
        FileUtils.mkdir_p(abs_path.dirname)
        File.write(abs_path, body)
        stats["files_written"] += 1 unless previous

        section_index[key] = {
          "path" => source_path,
          "article" => article,
          "title" => title,
          "status" => status
        }
      end

      def load_akoma_ntoso_corpus(run:, sway_locale:, law_root:, service: nil)
        svc = service || @service
        raise ArgumentError, "FetchLawService required for Akoma Ntoso law loading" if svc.nil?

        FetchLawCorpusService.new(run: run).call

        stats = {"sections_upserted" => 0, "files_written" => 0, "articles_processed" => 0}
        section_index = {}

        charter_path = svc.send(:locate_xml, CHARTER_FILE)
        case charter_path
        when Pathname then svc.send(:ingest_corpus, charter_path, "charter", stats, section_index)
        else raise StageError, "fetch_law: missing #{CHARTER_FILE} under #{law_root}"
        end

        svc.send(:locate_code_xmls).each { |code_path| svc.send(:ingest_corpus, code_path, "code", stats, section_index) }

        svc.send(:write_section_index, section_index)
        {
          "sections_upserted" => stats.fetch("sections_upserted", 0),
          "files_written" => stats.fetch("files_written", 0),
          "articles_processed" => stats.fetch("articles_processed", 0)
        }
      end
    end
  end
end

GenericLawAdapter = Legislation::Adapters::GenericLawAdapter
