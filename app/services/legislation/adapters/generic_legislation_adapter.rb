# frozen_string_literal: true

require "faraday"
require "json"
require "fileutils"
require "zlib"
require "nokogiri"

# @lat: [[legislation-pipeline#Upstream jurisdiction adapters]]
module Legislation
  module Adapters
    class GenericLegislationAdapter
      attr_reader :config, :engine, :retrieval, :parsing, :base_url, :endpoints, :metadata_mapping, :connection, :service

      DEFAULT_MATTER_TYPE = "Ordinance"
      PAGE_SIZE = 1000
      READER_NAME_PATTERN = /\b(\d+)(?:st|nd|rd|th)\s+reader\b/i
      FALLBACK_CLASSIFICATION_PREFERENCE = %i[bill_text undecided procedural ambiguous_bill_text testimony].freeze

      def initialize(config_or_locale = {}, connection: nil, service: nil)
        @config = extract_config(config_or_locale)
        raw_engine = @config[:engine].presence
        raw_retrieval = @config[:retrieval].presence || @config[:retrieval_strategy].presence
        raw_parsing = @config[:parsing].presence || @config[:parser_format].presence
        @engine = (raw_engine || raw_retrieval || :generic_rest).to_sym
        @retrieval = (raw_retrieval || @engine).to_sym
        @parsing = (raw_parsing || @engine).to_sym
        @base_url = @config[:base_url]
        @endpoints = (@config[:endpoints] || {}).deep_symbolize_keys
        @metadata_mapping = (@config[:metadata_mapping] || {}).deep_symbolize_keys
        @connection = connection
        @service = service
      end

      def legistar_client(sway_locale = nil)
        target_locale = sway_locale || (@service.respond_to?(:sway_locale) ? @service.sway_locale : nil)
        leg_rules = target_locale&.jurisdiction_rules&.legislation_rules
        client_name = (leg_rules&.[](:client) || leg_rules&.[]("client")).presence ||
          (leg_rules&.[](:jurisdiction) || leg_rules&.[]("jurisdiction")).presence ||
          leg_rules&.dig(:params, :client).presence ||
          leg_rules&.dig("params", "client").presence ||
          @config[:client].presence ||
          @config["client"].presence ||
          @config[:jurisdiction].presence ||
          @config["jurisdiction"].presence ||
          @config.dig(:params, :client).presence ||
          @config.dig("params", "client").presence
        raise ArgumentError, "No client configured for Legistar legislation adapter" if client_name.blank?

        @legistar_clients ||= {}
        @legistar_clients[client_name.to_s] ||= Legistar::Client.new(
          client: client_name.to_s,
          connection: @connection || default_connection
        )
      end

      def accepted_matter_types(sway_locale = nil)
        types = @config[:accepted_matter_types] || sway_locale&.jurisdiction_rules&.accepted_matter_types
        types.presence || [DEFAULT_MATTER_TYPE]
      end

      def detail_url_resolver
        @detail_url_resolver ||= Legistar::DetailUrlResolver.new
      end

      def resolve_detail_url(matter_id)
        return nil if matter_id.blank?

        detail_url_resolver.resolve(matter_id)
      rescue => e
        SwayLogging.warn("[GenericLegislationAdapter] detail URL resolution failed for matter #{matter_id}: #{e.class.name}: #{e.message.to_s[0, 200]}")
        nil
      end

      def map_status(raw_status)
        return nil unless raw_status.is_a?(String)
        return raw_status if Bill::STATUSES.include?(raw_status)

        case @parsing
        when :legistar
          # @lat: [[legistar-matter-status-mapping#Ingestion pipeline status boundary]]
          Legistar::StatusMapper.map(raw_status)
        else
          if @config[:status_mapping].is_a?(Hash)
            cleaned = raw_status.strip.downcase
            mapped = @config[:status_mapping][cleaned] || @config[:status_mapping][cleaned.to_sym]
            return mapped.to_s if mapped.present?
          end
          raw_status
        end
      end

      def repair_missing_metadata(external_id, sway_locale, connection = nil)
        return false unless @retrieval == :legistar

        segment = Legislation::Paths.external_id_segment(external_id)
        return false if segment.nil?

        conn = connection || @connection || default_connection
        rows = legistar_client(sway_locale).get("Matters", filter: "MatterFile eq '#{segment}'", top: 1)
        return false unless rows.is_a?(Array)

        matter = rows.find { |row| row.is_a?(::Hash) }
        return false if matter.nil?

        metadata = build_legistar_metadata(matter, sway_locale, conn)
        return false if metadata.nil?

        dir = Legislation::Paths.bill_artifact_dir(external_id, sway_locale: sway_locale&.name)
        FileUtils.mkdir_p(dir)
        File.write(dir.join("metadata.json"), JSON.pretty_generate(metadata))

        pdf_url = metadata[:pdf_url].to_s
        pdf_filename = metadata[:pdf_filename].presence || "#{external_id.downcase}.pdf"
        download_pdf(dir, pdf_url, pdf_filename, connection: conn) if pdf_url.present?

        !Legislation::BillMetadata.matter_id(external_id, sway_locale: sway_locale&.name).nil?
      rescue Faraday::Error, Legistar::Client::Error
        false
      end

      def build_metadata(matter, sway_locale = nil, conn = nil)
        build_legistar_metadata(matter, sway_locale, conn || @connection || default_connection)
      end

      def fetch_all_matters(sway_locale = nil, conn = nil)
        fetch_all_legistar_matters(conn || @connection || default_connection, sway_locale)
      end

      def fetch_attachments(matter_id, sway_locale = nil)
        parsed = legistar_client(sway_locale).matter_attachments(matter_id)
        return [] unless parsed.is_a?(Array)

        parsed.select { |raw| raw.is_a?(::Hash) }
      rescue Faraday::Error, Legistar::Client::Error
        []
      end

      def fetch_attachments_safely(matter_id, external_id, sway_locale, conn)
        fetch_attachments(matter_id, sway_locale)
      rescue Faraday::Error, Legistar::Client::Error => e
        SwayLogging.warn("[GenericLegislationAdapter] attachments fetch failed for bill #{external_id} (matter_id=#{matter_id}): #{e.class.name}: #{e.message.to_s[0, 200]}")
        []
      end

      def select_primary_attachment(attachments, sway_locale = nil)
        pdfs = attachments.select { |a| pdf_attachment?(a) }
        return nil if pdfs.empty?

        candidates = []
        pdfs.each do |a|
          match = READER_NAME_PATTERN.match(a["MatterAttachmentName"].to_s)
          next unless match

          candidates << {
            attachment: a,
            reading: match[1].to_s.to_i,
            modified: a["MatterAttachmentLastModifiedUtc"].to_s
          }
        end
        best_candidate = candidates.max_by { |c| [c[:reading], c[:modified]] }
        return best_candidate[:attachment] if best_candidate

        best_non_testimony_pdf(pdfs, sway_locale)
      end

      def pdf_attachment?(attachment)
        Legislation::Paths.upstream_file_name(attachment["MatterAttachmentFileName"])
          .to_s.downcase.end_with?(".pdf")
      end

      def best_non_testimony_pdf(pdfs, sway_locale = nil)
        locale_name = if sway_locale.is_a?(String)
          sway_locale
        elsif sway_locale.respond_to?(:name)
          sway_locale.name
        end
        locale_name ||= (@service.respond_to?(:sway_locale_name) ? @service.send(:sway_locale_name) : nil)
        by_label = pdfs.group_by { |a| ::Testimony::NameRules.classify(a["MatterAttachmentName"].to_s, sway_locale: locale_name) }
        FALLBACK_CLASSIFICATION_PREFERENCE.each do |label|
          tier = by_label[label]
          return tier.max_by { |a| a["MatterAttachmentLastModifiedUtc"].to_s } if tier
        end
        pdfs.max_by { |a| a["MatterAttachmentLastModifiedUtc"].to_s }
      end

      def discover(sway_locale:, start_time: nil, budget_seconds: nil, run_bill: nil, service: nil)
        return [] if @retrieval != :legistar && budget_exceeded?(start_time, budget_seconds)
        return [] if @retrieval == :unavailable

        svc = service || @service
        conn = @connection || (svc.respond_to?(:conn, true) ? svc.send(:conn) : nil) || default_connection

        case @retrieval
        when :congress_dot_gov, :congress
          discover_congress_bills(conn, sway_locale, start_time: start_time, budget_seconds: budget_seconds, run_bill: run_bill)
        when :generic_rest
          discover_rest_bills(conn, sway_locale, start_time: start_time, budget_seconds: budget_seconds, run_bill: run_bill)
        when :legistar
          discover_legistar(conn, sway_locale, start_time: start_time, budget_seconds: budget_seconds, run_bill: run_bill, svc: svc)
        when :generic_html
          discover_html_bills(conn, sway_locale, start_time: start_time, budget_seconds: budget_seconds, run_bill: run_bill)
        else
          raise BillProcessingError, "fetch_bills: unsupported legislation retrieval #{@retrieval.inspect}"
        end
      end

      def backfill_bill(bill, ready: nil, undiscovered: nil, service: nil)
        svc = service || @service
        locale_name = bill.sway_locale&.name
        dir = Legislation::Paths.bill_artifact_dir(bill.external_id, sway_locale: locale_name)
        meta_file = Legislation::Paths.bill_metadata_file(bill.external_id, sway_locale: locale_name)

        if @retrieval == :legistar
          meta_file = Legislation::Paths.bill_metadata_file(bill.external_id, sway_locale: locale_name)
          if !meta_file.exist?
            undiscovered << [bill.external_id, locale_name] if undiscovered
            return
          end

          metadata = load_metadata(meta_file, bill, locale_name)
          if metadata.nil?
            undiscovered << [bill.external_id, locale_name] if undiscovered
            return
          end

          matter_id = metadata[:matter_id] || Legislation::BillMetadata.matter_id(bill.external_id, sway_locale: locale_name)
          if matter_id.nil?
            undiscovered << [bill.external_id, locale_name] if undiscovered
            return
          end

          ready << [bill.external_id, locale_name, matter_id] if ready

          if metadata[:pdf_url].blank? && matter_id.present?
            attachments = fetch_attachments(matter_id, bill.sway_locale)
            primary = select_primary_attachment(attachments, bill.sway_locale)
            if primary
              metadata[:pdf_url] = primary["MatterAttachmentHyperlink"]
              metadata[:pdf_filename] = primary["MatterAttachmentFileName"]
              Legislation::AtomicWrite.write(meta_file) { |tmp| File.write(tmp, JSON.pretty_generate(metadata)) }
            end
          end

          pdf_url = metadata[:pdf_url].to_s
          pdf_filename = metadata[:pdf_filename].presence || "#{bill.external_id.downcase}.pdf"
          conn = @connection || (svc.respond_to?(:conn, true) ? svc.send(:conn) : nil) || default_connection
          download_pdf(dir, pdf_url, pdf_filename, connection: conn)
          return
        end

        metadata = load_metadata(meta_file, bill, locale_name)
        if (metadata.nil? || metadata[:pdf_url].blank?) && @retrieval == :generic_html
          base = require_base_url!
          session = determine_session(bill.sway_locale)
          if session.blank?
            undiscovered << [bill.external_id, locale_name] if undiscovered
            return nil
          end

          slug = bill.external_id.to_s.strip.downcase
          chamber = slug[0..1]
          pdf_filename = "#{slug}f.pdf"
          pdf_url = "#{base}/#{session}/bills/#{chamber}/#{pdf_filename}"
          matter_id = metadata&.[](:matter_id) || self.class.matter_id_for(bill.external_id)
          metadata = (metadata || {}).merge(
            external_id: bill.external_id,
            matter_id: matter_id,
            title: bill.title,
            pdf_url: pdf_url,
            pdf_filename: pdf_filename
          )
        end
        unless metadata.is_a?(Hash)
          undiscovered << [bill.external_id, locale_name] if undiscovered
          return nil
        end

        FileUtils.mkdir_p(dir)
        Legislation::AtomicWrite.write(meta_file) { |tmp| File.write(tmp, JSON.pretty_generate(metadata)) } unless meta_file.exist?

        conn = @connection || (svc.respond_to?(:conn, true) ? svc.send(:conn) : nil) || Faraday.new
        pdf_url = metadata[:pdf_url].to_s
        pdf_filename = metadata[:pdf_filename].presence || "#{bill.external_id.downcase}.pdf"

        download_pdf(dir, pdf_url, pdf_filename, connection: conn)

        sanitized_filename = Legislation::Paths.upstream_file_name(pdf_filename)
        pdf_path = sanitized_filename ? dir.join(sanitized_filename) : nil
        matter_id = metadata[:matter_id] || self.class.matter_id_for(bill.external_id)

        if pdf_path&.exist? && pdf_path.size > 0
          ready << [bill.external_id, locale_name, matter_id] if ready
        elsif undiscovered
          undiscovered << [bill.external_id, locale_name]
        end
      end

      def download_pdf(dir, pdf_url, pdf_filename, connection: nil)
        sanitized_name = Legislation::Paths.upstream_file_name(pdf_filename)
        return nil if sanitized_name.nil?

        FileUtils.mkdir_p(dir)
        path = dir.join(sanitized_name)
        conn = connection || @connection || Faraday.new
        response =
          begin
            if @retrieval == :legistar
              Legistar::AttachmentFetch.new(connection: conn).call(pdf_url)
            elsif pdf_url.present?
              conn.get(pdf_url)
            end
          rescue Faraday::Error, Legistar::AttachmentFetch::Rejected => e
            SwayLogging.warn("[GenericLegislationAdapter] refusing bill PDF download: #{e.message}")
            nil
          end

        chosen_url = pdf_url

        unless pdf_response?(response)
          match = dir.basename.to_s.match(/\A(\d+)-([a-zA-Z]+)-(\d+)\z/) ||
            sanitized_name.match(/\A(\d+)-([a-zA-Z]+)-(\d+)\.pdf\z/)
          if match
            congress = match[1].to_s.downcase
            type = match[2].to_s.downcase
            number = match[3].to_s.downcase
            external_id = "#{congress}-#{type}-#{number}"
            candidates = published_pdf_urls(conn, congress, type, number)
            candidates << self.class.introduced_pdf_url(congress, type, number)
            candidates.uniq.reject { |u| u == pdf_url }.each do |url|
              res = begin
                conn.get(url)
              rescue Faraday::Error
                nil
              end
              next unless pdf_response?(res)

              response = res
              chosen_url = url
              break
            end

            unless pdf_response?(response)
              reason = response ? "HTTP #{response.status} without usable PDF bytes" : "network request failed"
              raise BillProcessingError, "fetch_bills: no usable Congress PDF for #{external_id} (#{reason})"
            end
          end
        end

        return nil unless pdf_response?(response)

        written = File.binwrite(path, response.body.to_s)
        update_metadata_pdf_url(dir, chosen_url) if chosen_url != pdf_url
        written
      end

      def pdf_response?(response)
        return false if response.nil?

        response.status.between?(200, 299) && response.body.to_s.start_with?(FetchBillsService::PDF_MAGIC_BYTES)
      end

      def update_metadata_pdf_url(dir, url)
        file = dir.join("metadata.json")
        return unless file.file?

        metadata = JSON.parse(file.read)
        raise BillProcessingError, "fetch_bills: Congress PDF metadata is not an object" unless metadata.is_a?(Hash)

        metadata["pdf_url"] = url
        Legislation::AtomicWrite.write(file) { |tmp| File.write(tmp, JSON.pretty_generate(metadata)) }
      rescue JSON::ParserError
        raise BillProcessingError, "fetch_bills: Congress PDF metadata is not valid JSON"
      end

      def published_pdf_urls(conn, congress, type, number)
        params = {format: "json"}
        secret_name = @config[:api_key_secret]
        if secret_name.present?
          key = EnvSecret.read(secret_name.to_s)
          params[:api_key] = key if key.present?
        end

        response = conn.get("bill/#{congress}/#{type}/#{number}/text", params)
        return [] unless response.status.between?(200, 299)

        data = JSON.parse(response.body)
        return [] unless data.is_a?(Hash) && data["textVersions"].is_a?(Array)

        data["textVersions"].flat_map do |version|
          next [] unless version.is_a?(Hash) && version["formats"].is_a?(Array)

          version["formats"].filter_map do |format|
            next unless format.is_a?(Hash) && format["type"] == "PDF"

            url = format["url"]
            url if url.is_a?(String) && url.present?
          end
        end.uniq
      rescue Faraday::Error, JSON::ParserError
        []
      end

      def self.matter_id_for(external_id)
        str = external_id.to_s.strip
        if str =~ /\A([A-Za-z]+)0*(\d+)\z/
          prefix = Regexp.last_match(1).to_s.upcase
          num = Regexp.last_match(2).to_i
          offset = (prefix == "HB") ? 100_000 : 200_000
          offset + num
        elsif str =~ /\A(\d+)-([a-zA-Z]+)-(\d+)\z/
          match = Regexp.last_match
          congress = match ? match[1].to_i : 0
          type_str = match ? match[2].to_s.downcase : ""
          type_code = if type_str == "hr"
            1
          else
            ((type_str == "s") ? 2 : 3)
          end
          num = match ? match[3].to_i : 0
          (congress * 1_000_000) + (type_code * 100_000) + num
        else
          (Zlib.crc32(str) % (2**30)) + 1
        end
      end

      def self.introduced_pdf_url(congress, type, number)
        normalized_type = type.to_s.downcase
        version = case normalized_type
        when "hr", "hjres", "hconres", "hres" then "ih"
        when "s", "sjres", "sconres", "sres" then "is"
        else
          raise BillProcessingError, "fetch_bills: unrecognized Congress bill type #{type.inspect}"
        end
        package = "BILLS-#{congress}#{normalized_type}#{number}#{version}"
        "https://www.govinfo.gov/content/pkg/#{package}/pdf/#{package}.pdf"
      end

      delegate :matter_id_for, :introduced_pdf_url, to: :class

      private

      def extract_config(input)
        return input.deep_symbolize_keys if input.is_a?(Hash)

        rules = if input.is_a?(SwayLocale)
          input.jurisdiction_rules
        elsif input.is_a?(SwayLocale::JurisdictionRules)
          input
        elsif input.respond_to?(:jurisdiction_rules)
          input.jurisdiction_rules
        elsif input.respond_to?(:legislation_rules)
          input
        end

        leg_rules = rules.try(:legislation_rules) if rules
        return leg_rules.deep_symbolize_keys if leg_rules.is_a?(Hash) && leg_rules.any?

        {}
      end

      def default_connection
        Faraday.new(url: @base_url) do |f|
          f.adapter Faraday.default_adapter
        end
      end

      def budget_exceeded?(start_time, budget_seconds)
        return false if start_time.nil? || budget_seconds.nil?
        elapsed = Time.current.to_f - start_time.to_f
        elapsed >= budget_seconds.to_f
      end

      def discover_rest_bills(conn, sway_locale, start_time: nil, budget_seconds: nil, run_bill: nil)
        return [] if @base_url.blank?

        initial_endpoint = @endpoints[:bills] || "/bills"
        interpolated_path = interpolate_endpoint(initial_endpoint, sway_locale, run_bill)
        page_param = @config[:page_param] || :page
        offset_param = @config[:offset_param] || :offset
        max_pages = (@config[:max_pages] || 50).to_i

        results = []
        current_path = interpolated_path
        page = 1
        offset = 0

        loop do
          break if budget_exceeded?(start_time, budget_seconds)
          break if page > max_pages

          response =
            begin
              conn.get(current_path)
            rescue Faraday::Error => e
              raise BillProcessingError, "fetch_bills: network error: #{e.message.to_s[0, 500]}"
            end

          unless response.status.between?(200, 299)
            raise BillProcessingError, "fetch_bills: HTTP #{response.status}"
          end

          parsed = begin
            JSON.parse(response.body)
          rescue
            {}
          end

          raw_items = extract_raw_bill_items(parsed)
          break if raw_items.empty?

          page_results = process_bill_items(raw_items, sway_locale, run_bill)
          results.concat(page_results)

          break if run_bill && page_results.any?

          next_link = extract_next_link(parsed, response)
          if next_link.present?
            current_path = next_link
            page += 1
          elsif parsed.is_a?(Hash) && (parsed["pagination"].is_a?(Hash) || parsed[:pagination].is_a?(Hash))
            pag = parsed["pagination"] || parsed[:pagination]
            total = (pag["count"] || pag["total"] || pag[:count] || pag[:total]).to_i
            max_page = (pag["max_page"] || pag[:max_page]).to_i

            if max_page > 0
              break if page >= max_page
              page += 1
              current_path = update_query_param(interpolated_path, page_param, page)
            elsif total > 0
              offset += raw_items.size
              break if offset >= total
              page += 1
              current_path = update_query_param(interpolated_path, offset_param, offset)
            else
              break
            end
          elsif @config[:paginate] == true
            page += 1
            current_path = update_query_param(interpolated_path, page_param, page)
          else
            break
          end
        end

        results
      end

      def discover_legistar(conn, sway_locale, start_time: nil, budget_seconds: nil, run_bill: nil, svc: nil)
        matters = fetch_all_legistar_matters(conn, sway_locale)
        metadatas = build_legistar_metadatas_within_budget(matters, sway_locale, conn, start_time, budget_seconds)
        if svc.respond_to?(:scope_to_run_bill, true)
          svc.send(:scope_to_run_bill, metadatas)
        elsif run_bill
          target_id = if run_bill.respond_to?(:external_id)
            run_bill.external_id
          else
            (run_bill.respond_to?(:bill_external_id) ? run_bill.bill_external_id : run_bill.to_s)
          end
          metadatas.select { |m| m[:external_id].to_s.casecmp?(target_id.to_s) }
        else
          metadatas
        end
      rescue Faraday::Error, Legistar::Client::Error => e
        raise BillProcessingError, "fetch_bills: #{e.class.name}: #{e.message.to_s[0, 500]}"
      end

      def fetch_all_legistar_matters(conn, sway_locale)
        years = [Time.current.year - 1, Time.current.year]
        min_year = years.min
        max_year = years.max + 1
        types = accepted_matter_types(sway_locale)
        type_filter = if types.length == 1
          "MatterTypeName eq '#{types.first}'"
        else
          "(" + types.map { |t| "MatterTypeName eq '#{t}'" }.join(" or ") + ")"
        end
        filter_str = "MatterIntroDate ge datetime'#{min_year}-01-01T00:00:00'" \
                     " and MatterIntroDate lt datetime'#{max_year}-01-01T00:00:00'" \
                     " and #{type_filter}"

        matters = []
        last_id = 0
        loop do
          page = legistar_client(sway_locale).get(
            "Matters",
            filter: "MatterId gt #{last_id} and #{filter_str}",
            orderby: "MatterId asc",
            top: PAGE_SIZE
          )
          break unless page.is_a?(Array)
          break if page.empty?

          rows = page.select { |row| row.is_a?(Hash) }
          matters.concat(rows)
          last_id_value = rows.last&.[]("MatterId")
          unless last_id_value.is_a?(Integer) && last_id_value > last_id
            break
          end
          last_id = last_id_value
          break if page.size < PAGE_SIZE
        end
        matters
      end

      def build_legistar_metadatas_within_budget(matters, sway_locale, conn, start_time, budget_seconds)
        metadatas = []
        matters.each_with_index do |matter, index|
          if budget_exceeded?(start_time, budget_seconds)
            SwayLogging.warn(
              "[GenericLegislationAdapter] discovery budget of #{budget_seconds}s used up after " \
              "#{index} of #{matters.length} matters; the rest are left for the next run"
            )
            return metadatas
          end

          meta = build_legistar_metadata(matter, sway_locale, conn)
          metadatas << meta if meta
        end
        metadatas
      end

      def build_legistar_metadata(matter, sway_locale, conn)
        matter_type = matter["MatterTypeName"].to_s
        types = accepted_matter_types(sway_locale)
        return nil if types.present? && !types.include?(matter_type)

        external_id_raw = matter["MatterFile"]
        matter_id_raw = matter["MatterId"]
        external_id = Legislation::Paths.external_id_segment(external_id_raw.to_s)
        return nil if external_id.nil?
        return nil unless matter_id_raw.is_a?(Integer)

        attachments = fetch_attachments_safely(matter_id_raw, external_id, sway_locale, conn)
        primary = select_primary_attachment(attachments, sway_locale)

        pdf_url_raw = primary ? primary["MatterAttachmentHyperlink"] : nil
        pdf_filename_raw = primary ? primary["MatterAttachmentFileName"] : nil
        pdf_url = pdf_url_raw.is_a?(String) ? pdf_url_raw : nil
        pdf_filename = Legislation::Paths.upstream_file_name(pdf_filename_raw)
        intro_date_raw = matter["MatterIntroDate"]
        status = Legistar::StatusMapper.map(matter["MatterStatusName"])
        link = resolve_detail_url(matter_id_raw)

        {
          external_id: external_id,
          matter_id: matter_id_raw,
          title: matter["MatterTitle"].to_s,
          introduction_date: intro_date_raw,
          bill_number: external_id,
          matter_type: matter_type,
          pdf_url: pdf_url,
          pdf_filename: pdf_filename,
          status: status,
          link: link
        }
      end

      def discover_html_bills(conn, sway_locale, start_time: nil, budget_seconds: nil, run_bill: nil)
        require_base_url!
        session = determine_session(sway_locale).to_s
        raise BillProcessingError, "No active session found for HTML legislation discovery" if session.blank?

        if run_bill
          discover_single_html_bill(conn, run_bill, session: session)
        else
          discover_all_html_bills(conn, session: session, start_time: start_time, budget_seconds: budget_seconds)
        end
      rescue Faraday::Error => e
        raise BillProcessingError, "fetch_bills: network error: #{e.message.to_s[0, 500]}"
      end

      def determine_session(locale)
        config_session = @config[:session] || @config["session"] || @config[:current_session] || @config["current_session"]
        return config_session.to_s if config_session.present?

        active_session = (locale&.current_legislative_session unless locale.is_a?(String))
        if active_session
          return active_session.upstream_name.to_s if active_session.respond_to?(:upstream_name) && active_session.upstream_name.present?
          return active_session.name.to_s if active_session.name.present?
        end

        nil
      end

      def discover_single_html_bill(conn, run_bill, session:)
        ext_id = if run_bill.respond_to?(:bill_external_id)
          run_bill.bill_external_id
        elsif run_bill.respond_to?(:external_id)
          run_bill.external_id
        else
          run_bill
        end.to_s.strip

        details_endpoint = @endpoints[:details] || "/mgawebsite/Legislation/Details/:external_id?ys=:session"
        url = details_endpoint.gsub(":external_id", ext_id.downcase).gsub(":session", session)
        response = conn.get(url)
        return [] unless response.status.between?(200, 299)

        doc = Nokogiri::HTML(response.body)
        meta = parse_html_details_page(doc, ext_id, session)
        meta ? [meta] : []
      end

      def discover_all_html_bills(conn, session:, start_time:, budget_seconds:)
        index_endpoint = @endpoints[:index] || "/mgawebsite/Legislation/Index?ys=:session"
        url = index_endpoint.gsub(":session", session)
        response = conn.get(url)
        return [] unless response.status.between?(200, 299)

        doc = Nokogiri::HTML(response.body)
        table = doc.at_css("table#billIndex")
        return [] if table.nil?

        metadatas = []
        table.css("tbody tr").each do |row|
          break if budget_exceeded?(start_time, budget_seconds)

          meta = parse_html_index_row(row, session)
          metadatas << meta if meta
        end
        metadatas
      end

      def parse_html_index_row(row, session)
        link = row.at_css("td:first-child a")
        return nil if link.nil?

        raw_id = link.text.strip
        return nil if raw_id.empty?

        ext_id = raw_id.upcase
        title_td = row.css("td")[1]
        title = title_td&.text&.strip.presence || "Legislation #{ext_id}"

        slug = ext_id.downcase
        chamber = slug[0..1]
        pdf_filename = "#{slug}f.pdf"
        base = require_base_url!
        pdf_url = "#{base}/#{session}/bills/#{chamber}/#{pdf_filename}"

        {
          external_id: ext_id,
          matter_id: self.class.matter_id_for(ext_id),
          title: title,
          introduction_date: "#{/^[0-9]{4}/.match?(session.to_s) ? session.to_s[0..3] : Time.current.year}-01-14",
          bill_number: format_bill_number(ext_id),
          matter_type: "Bill",
          pdf_url: pdf_url,
          pdf_filename: pdf_filename
        }
      end

      def parse_html_details_page(doc, ext_id, session)
        title_el = doc.at_css(".bill-title, h1, h2")
        title = title_el&.text&.strip.presence || "Legislation #{ext_id}"

        pdf_link = doc.at_css("a[href*='.pdf']")
        slug = ext_id.downcase
        chamber = slug[0..1]
        pdf_filename = "#{slug}f.pdf"
        base = require_base_url!
        pdf_url = if pdf_link
          raw_href = pdf_link["href"].to_s
          raw_href.start_with?("http") ? raw_href : URI.join(base, raw_href).to_s
        else
          "#{base}/#{session}/bills/#{chamber}/#{pdf_filename}"
        end

        {
          external_id: ext_id.upcase,
          matter_id: self.class.matter_id_for(ext_id),
          title: title,
          introduction_date: "#{/^[0-9]{4}/.match?(session.to_s) ? session.to_s[0..3] : Time.current.year}-01-14",
          bill_number: format_bill_number(ext_id),
          matter_type: "Bill",
          pdf_url: pdf_url,
          pdf_filename: pdf_filename
        }
      end

      def format_bill_number(external_id)
        if external_id =~ /\A([A-Za-z]+)0*(\d+)\z/
          "#{Regexp.last_match(1)} #{Regexp.last_match(2)}"
        else
          external_id
        end
      end

      def discover_congress_bills(conn, sway_locale, start_time: nil, budget_seconds: nil, run_bill: nil)
        if run_bill
          ext_id = if run_bill.respond_to?(:bill_external_id)
            run_bill.bill_external_id
          elsif run_bill.respond_to?(:external_id)
            run_bill.external_id
          else
            run_bill
          end.to_s
          match = ext_id.match(/\A(\d+)-([a-zA-Z]+)-(\d+)\z/)
          return [] unless match

          congress = Regexp.last_match(1).to_s
          type = Regexp.last_match(2).to_s.downcase
          number = Regexp.last_match(3).to_s

          detail = fetch_congress_bill_detail(conn, congress, type, number)
          meta = normalize_congress_bill_data(detail, congress: congress, type: type, number: number)
          meta ? [meta] : []
        else
          congress_num = current_congress(sway_locale)
          response = conn.get("bill/#{congress_num}", api_params.merge(limit: 250))
          unless response.status.between?(200, 299)
            raise StageError, "fetch_bills: Congress.gov HTTP #{response.status}"
          end

          data = JSON.parse(response.body)
          bills = data["bills"] || []
          metadatas = []

          bills.each do |b|
            break if budget_exceeded?(start_time, budget_seconds)
            next unless b["congress"] && b["type"] && b["number"]

            detail = fetch_congress_bill_detail(conn, b["congress"].to_s, b["type"].to_s.downcase, b["number"].to_s)
            meta = normalize_congress_bill_data(b.merge(detail))
            metadatas << meta if meta
          end
          metadatas
        end
      end

      def fetch_congress_bill_detail(conn, congress, type, number)
        response = conn.get("bill/#{congress}/#{type}/#{number}", api_params)
        unless response.status.between?(200, 299)
          raise BillProcessingError, "fetch_bills: Congress.gov HTTP #{response.status}"
        end
        data = JSON.parse(response.body)
        data["bill"] || data
      end

      def current_congress(sway_locale)
        locale = sway_locale || raise(BillProcessingError, "fetch_bills: Congress locale is missing")
        ((TermWindow.cycle_start_year(locale, Date.current) - 1789) / 2) + 1
      end

      def api_params
        params = {format: "json"}
        secret_name = @config[:api_key_secret]
        if secret_name.present?
          key = EnvSecret.read(secret_name.to_s)
          params[:api_key] = key if key.present?
        end
        params
      end

      def normalize_congress_bill_data(b, congress: nil, type: nil, number: nil)
        congress ||= b["congress"]&.to_s
        type ||= b["type"]&.to_s&.downcase
        number ||= b["number"]&.to_s
        return nil if congress.nil? || type.nil? || number.nil?

        external_id = "#{congress}-#{type}-#{number}"
        sponsor_id = b.dig("sponsors", 0, "bioguideId").to_s.presence
        unless sponsor_id
          raise BillProcessingError, "fetch_bills: Congress bill #{external_id} has no published sponsor identifier"
        end
        chamber = b["originChamber"].to_s.downcase.presence
        unless %w[house senate].include?(chamber)
          raise BillProcessingError, "fetch_bills: Congress bill #{external_id} has no recognized origin chamber"
        end
        title = b["title"].to_s.presence || "Congress Bill #{external_id}"
        intro_date = b["introducedDate"] || b.dig("latestAction", "actionDate")

        pdf_filename = "#{external_id}.pdf"
        pdf_url = self.class.introduced_pdf_url(congress, type, number)

        {
          external_id: external_id,
          matter_id: self.class.matter_id_for(external_id),
          title: title,
          introduction_date: intro_date,
          bill_number: "#{type.upcase} #{number}",
          matter_type: "Bill",
          legislator_external_id: sponsor_id,
          chamber: chamber,
          pdf_url: pdf_url,
          pdf_filename: pdf_filename
        }
      end

      def load_metadata(meta_file, bill, locale_name)
        if meta_file.exist?
          begin
            parsed = JSON.parse(meta_file.read, symbolize_names: true)
            parsed.is_a?(Hash) ? parsed : nil
          rescue JSON::ParserError
            nil
          end
        else
          matter_id = Legislation::BillMetadata.matter_id(bill.external_id, sway_locale: locale_name) ||
            self.class.matter_id_for(bill.external_id)
          meta = {
            external_id: bill.external_id,
            matter_id: matter_id,
            title: bill.title.to_s,
            introduction_date: bill.introduced_date_time_utc&.iso8601,
            bill_number: bill.external_id,
            matter_type: "Bill",
            legislator_external_id: bill.legislator&.external_id,
            chamber: bill.chamber,
            pdf_url: nil,
            pdf_filename: "#{bill.external_id.downcase}.pdf"
          }
          if (m = bill.external_id.match(/\A(\d+)-([a-zA-Z]+)-(\d+)\z/))
            meta[:pdf_url] = self.class.introduced_pdf_url(m[1].to_s, m[2].to_s, m[3].to_s)
          end
          meta
        end
      end

      def extract_field(record, path_expr)
        return nil if record.nil? || path_expr.blank?

        clean = path_expr.to_s.sub(/\A\$\.?/, "")
        tokens = clean.scan(/[^.\[\]]+|\[\d+\]/).map do |tok|
          if tok =~ /\A\[(\d+)\]\z/
            Regexp.last_match(1).to_i
          else
            tok
          end
        end

        val = record
        tokens.each do |tok|
          if tok.is_a?(Integer)
            return nil unless val.is_a?(Array)
            val = val[tok]
          elsif val.is_a?(Hash)
            val = val[tok] || val[tok.to_sym]
          else
            return nil
          end
        end
        val
      end

      def interpolate_endpoint(template, sway_locale, run_bill = nil)
        path = template.to_s.dup
        ext_id = (run_bill.respond_to?(:external_id) ? run_bill.external_id : run_bill).to_s.strip
        year = (@config[:year] || Date.current.year).to_s
        session = (@config[:session] || @config[:current_session] || year).to_s
        chamber = (@config[:chamber] || "both").to_s
        locale_name = sway_locale&.name.to_s
        locale_slug = (sway_locale.respond_to?(:slug) ? sway_locale.slug : nil).to_s.presence || locale_name
        jurisdiction = (sway_locale&.region_code || locale_name).to_s

        replacements = {
          ":external_id" => ext_id,
          ":year" => year,
          ":session" => session,
          ":chamber" => chamber,
          ":locale" => locale_slug,
          ":jurisdiction" => jurisdiction
        }
        @config.each do |k, v|
          replacements[":#{k}"] = v.to_s if v.is_a?(String) || v.is_a?(Numeric)
        end

        replacements.each do |token, val|
          path.gsub!(token, val)
        end
        path
      end

      def extract_raw_bill_items(parsed)
        return [] if parsed.blank?

        if parsed.is_a?(Array)
          parsed
        elsif parsed.is_a?(Hash)
          list = parsed["bills"] || parsed[:bills] ||
            parsed["results"] || parsed[:results] ||
            parsed["data"] || parsed[:data] ||
            parsed["items"] || parsed[:items]
          if list.is_a?(Array)
            list
          elsif single_bill_item?(parsed)
            [parsed]
          else
            []
          end
        else
          []
        end
      end

      def single_bill_item?(hash)
        return false unless hash.is_a?(Hash)

        (hash["external_id"] || hash[:external_id] ||
         hash["number"] || hash[:number] ||
         hash["bill_number"] || hash[:bill_number] ||
         hash["title"] || hash[:title] ||
         extract_field(hash, @metadata_mapping[:external_id])).present?
      end

      def process_bill_items(raw_items, sway_locale, run_bill = nil)
        results = []
        raw_items.each do |item|
          next unless item.is_a?(Hash)

          ext_id = extract_field(item, @metadata_mapping[:external_id] || "number") ||
            item["external_id"] || item[:external_id] ||
            item["number"] || item[:number]
          next if ext_id.blank?

          if run_bill
            target_id = run_bill.respond_to?(:external_id) ? run_bill.external_id : run_bill.to_s
            next unless ext_id.to_s.casecmp?(target_id.to_s)
          end

          title = extract_field(item, @metadata_mapping[:title] || "title") || item["title"] || item[:title] || ""
          chamber = extract_field(item, @metadata_mapping[:chamber] || "chamber") || item["chamber"] || item[:chamber]
          intro_date = extract_field(item, @metadata_mapping[:introduction_date] || "introduction_date") ||
            item["introduction_date"] || item[:introduction_date]
          matter_id = (extract_field(item, @metadata_mapping[:matter_id]) || self.class.matter_id_for(ext_id)).to_i

          results << {
            external_id: ext_id.to_s,
            matter_id: matter_id,
            title: title.to_s,
            introduction_date: intro_date,
            bill_number: ext_id.to_s,
            matter_type: extract_field(item, @metadata_mapping[:matter_type]) || "Bill",
            pdf_url: extract_field(item, @metadata_mapping[:pdf_url]),
            pdf_filename: extract_field(item, @metadata_mapping[:pdf_filename]),
            chamber: chamber&.to_s,
            status: (raw_st = extract_field(item, @metadata_mapping[:status])&.to_s).present? ? map_status(raw_st) : nil,
            link: extract_field(item, @metadata_mapping[:link])&.to_s
          }
        end
        results
      end

      def extract_next_link(parsed, response)
        if parsed.is_a?(Hash)
          next_url = parsed["next"] || parsed[:next] ||
            parsed.dig("pagination", "next") || parsed.dig(:pagination, :next)
          return next_url.to_s if next_url.present?
        end

        link_header = response.headers["link"] || response.headers["Link"]
        if link_header.present? && link_header =~ /<([^>]+)>;\s*rel="?next"?/i
          return Regexp.last_match(1)
        end

        nil
      end

      def update_query_param(path, key, value)
        uri = URI.parse(path)
        query_params = URI.decode_www_form(uri.query || "")
        query_params.reject! { |(k, _)| k == key.to_s }
        query_params << [key.to_s, value.to_s]
        uri.query = URI.encode_www_form(query_params)
        uri.to_s
      rescue URI::InvalidURIError
        sep = path.include?("?") ? "&" : "?"
        "#{path}#{sep}#{key}=#{value}"
      end

      def require_base_url!
        @base_url.presence || raise(BillProcessingError, "fetch_bills: base_url is required for legislation engine #{@retrieval.to_sym.inspect}")
      end
    end
  end
end

GenericLegislationAdapter = Legislation::Adapters::GenericLegislationAdapter
