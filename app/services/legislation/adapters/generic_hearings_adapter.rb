# frozen_string_literal: true

require "faraday"
require "json"
require "nokogiri"

# @lat: [[legislation-pipeline#Upstream jurisdiction adapters]]
module Legislation
  module Adapters
    class GenericHearingsAdapter
      MATTER_ID_MAX = (2**31) - 1

      attr_reader :config, :engine, :retrieval, :parsing, :base_url, :endpoints, :connection, :attachment_connection, :service

      def initialize(config_or_locale = {}, connection: nil, attachment_connection: nil, service: nil)
        @config = extract_config(config_or_locale)
        @engine = (@config[:engine] || @config[:retrieval] || @config[:retrieval_strategy] || :generic_html).to_sym
        @retrieval = (@config[:retrieval] || @config[:retrieval_strategy] || @engine).to_sym
        @parsing = (@config[:parsing] || @config[:parser_format] || @engine).to_sym
        @base_url = @config[:base_url]
        @endpoints = (@config[:endpoints] || {}).deep_symbolize_keys
        @connection = connection
        @attachment_connection = attachment_connection
        @service = service
      end

      def discover_hearings(bill:, sway_locale:, faraday_conn: nil, service: nil)
        return [] if @retrieval == :unavailable || @engine == :unavailable

        conn = faraday_conn || @connection || (service.respond_to?(:conn, true) ? service.send(:conn) : nil) || default_connection

        hearings =
          case @retrieval
          when :generic_html
            discover_html_hearings(bill, sway_locale, conn)
          when :generic_rest
            discover_rest_hearings(bill, sway_locale, conn)
          when :legistar
            if service&.respond_to?(:discover_legistar_hearings, true)
              return service.send(:discover_legistar_hearings, bill, sway_locale)
            end

            discover_legistar_hearings(bill, sway_locale, conn)
          else
            raise BillProcessingError, "fetch_hearings: unsupported engine #{(@config[:engine] || @retrieval).inspect}"
          end

        write_hearings_artifact(bill, sway_locale, hearings)
        update_bill_provisioning(bill)
        hearings
      rescue Legistar::Client::Error, Faraday::Error => e
        raise BillProcessingError, "fetch_hearings: #{e.class.name}: #{e.message.to_s[0, 500]}"
      end

      # @lat: [[legislation-pipeline#Upstream jurisdiction adapters]]
      def discover_legistar_hearings(bill, sway_locale, _conn = nil)
        matter_id = (bill.send(:matter_id) if bill.respond_to?(:matter_id)).presence ||
          (bill.metadata["MatterId"] if bill.respond_to?(:metadata) && bill.metadata.is_a?(Hash)).presence ||
          (bill.metadata["matter_id"] if bill.respond_to?(:metadata) && bill.metadata.is_a?(Hash)).presence ||
          lookup_matter_id_from_metadata(bill, sway_locale)

        matter_id_int = coerce_matter_id!(matter_id)
        client = legistar_client(sway_locale)

        event_ids =
          begin
            histories = client.matter_histories(matter_id_int)
            if histories.is_a?(Array)
              histories
                .filter_map { |h| h["MatterHistoryEventId"] if h.is_a?(::Hash) }
                .filter_map { |raw_event_id| coerce_attachment_id(raw_event_id) }
                .uniq
            else
              []
            end
          rescue Legistar::Client::HttpError => e
            raise BillProcessingError, "fetch_hearings: HTTP #{e.status} for bill ##{bill.id}"
          rescue Legistar::Client::ParseError
            []
          rescue Legistar::Client::Error, Faraday::Error => e
            raise BillProcessingError, "fetch_hearings: #{e.class.name}: #{e.message.to_s[0, 500]}"
          end

        verify_matter_exists!(bill, matter_id_int) if event_ids.empty?

        event_ids.filter_map do |event_id|
          event = begin
            raw = client.get("Events/#{event_id}")
            raw.is_a?(::Hash) ? raw : nil
          rescue Legistar::Client::HttpError
            nil
          rescue Legistar::Client::ParseError
            nil
          rescue Legistar::Client::Error, Faraday::Error => e
            raise BillProcessingError, "fetch_hearings: #{e.class.name}: #{e.message.to_s[0, 500]}"
          end

          next if event.nil?

          event_items(event_id)
          event_to_hearing_hash(event)
        end
      rescue Legistar::Client::Error, Faraday::Error => e
        raise BillProcessingError, "fetch_hearings: #{e.class.name}: #{e.message.to_s[0, 500]}"
      end

      def legistar_client(sway_locale = nil)
        target_locale = sway_locale ||
          (@service.respond_to?(:sway_locale, true) ? @service.send(:sway_locale) : nil) ||
          @sway_locale ||
          @service&.instance_variable_get(:@bill)&.sway_locale
        j_rules = target_locale&.jurisdiction_rules || @jurisdiction_rules
        hearings_rules = j_rules&.hearings_rules
        legislation_rules = j_rules&.legislation_rules

        client_name = (hearings_rules&.[](:client) || hearings_rules&.[]("client")).presence ||
          (hearings_rules&.[](:jurisdiction) || hearings_rules&.[]("jurisdiction")).presence ||
          (legislation_rules&.[](:client) || legislation_rules&.[]("client")).presence ||
          (legislation_rules&.[](:jurisdiction) || legislation_rules&.[]("jurisdiction")).presence ||
          @config[:client].presence ||
          @config["client"].presence ||
          @config[:jurisdiction].presence ||
          @config["jurisdiction"].presence ||
          @config.dig(:params, :client).presence ||
          @config.dig(:params, "client").presence ||
          @config.dig(:params, :jurisdiction).presence ||
          @config.dig(:params, "jurisdiction").presence

        raise ArgumentError, "No client configured for Legistar hearings adapter" if client_name.blank?

        @legistar_clients ||= {}
        client_instance = @legistar_clients[client_name.to_s] ||= Legistar::Client.new(
          client: client_name.to_s,
          connection: @connection || default_connection
        )
        @legistar_client = client_instance
      end

      def matter_attachments(matter_id)
        return [] unless @retrieval == :legistar

        attachments = legistar_client.matter_attachments(matter_id)
        attachments.is_a?(Array) ? attachments : []
      rescue Legistar::Client::HttpError, Legistar::Client::ParseError, Legistar::Client::Error, Faraday::Error
        []
      end

      def matter_histories(matter_id)
        return [] unless @retrieval == :legistar

        histories = legistar_client.matter_histories(matter_id)
        histories.is_a?(Array) ? histories : []
      rescue Legistar::Client::HttpError, Legistar::Client::ParseError, Legistar::Client::Error, Faraday::Error
        []
      end

      def matter_exists?(matter_id)
        return false unless @retrieval == :legistar

        legistar_client.get("Matters/#{matter_id}")
        true
      rescue Legistar::Client::HttpError => e
        return false if e.status == 404

        raise BillProcessingError,
          "fetch_hearings: HTTP #{e.status} probing Matters/#{matter_id} — cannot tell an " \
          "empty hearings collection apart from a stale matter_id, so nothing was recorded"
      rescue Legistar::Client::ParseError, Legistar::Client::Error, Faraday::Error => e
        raise BillProcessingError,
          "fetch_hearings: #{e.class.name}: #{e.message.to_s[0, 300]} probing Matters/#{matter_id} — " \
          "cannot tell an empty hearings collection apart from a stale matter_id, so nothing was recorded"
      end

      def hearing_event(event_id)
        return nil unless @retrieval == :legistar

        event = legistar_client.get("Events/#{event_id}")
        event.is_a?(::Hash) ? event : nil
      rescue Legistar::Client::HttpError, Legistar::Client::ParseError, Legistar::Client::Error, Faraday::Error
        nil
      end

      def event_items(event_id)
        return [] unless @retrieval == :legistar

        items = legistar_client.get_raw("Events/#{event_id}/EventItems", "Attachments" => 1)
        items.is_a?(Array) ? items : []
      rescue Legistar::Client::HttpError, Legistar::Client::ParseError, Legistar::Client::Error, Faraday::Error
        []
      end

      # @lat: [[download-bounds#Download bounds]]
      def attachment_fetch
        @attachment_fetch ||= Legistar::AttachmentFetch.new(connection: @attachment_connection || default_attachment_connection)
      end

      private

      def extract_config(input)
        return input.deep_symbolize_keys if input.is_a?(Hash)

        rules = if input.is_a?(SwayLocale)
          @sway_locale = input
          input.jurisdiction_rules
        elsif input.is_a?(SwayLocale::JurisdictionRules)
          input
        elsif input.respond_to?(:jurisdiction_rules)
          input.jurisdiction_rules
        elsif input.respond_to?(:hearings_rules)
          input
        end

        @jurisdiction_rules = rules

        if rules&.respond_to?(:hearings_rules)
          h_rules = rules&.hearings_rules
          if h_rules.is_a?(Hash) && h_rules.any?
            cfg = h_rules.deep_symbolize_keys
            if cfg[:retrieval].blank? && rules.respond_to?(:retrieval_for)
              ret = rules.retrieval_for(:hearings)
              cfg[:retrieval] = ret.to_sym if ret.present?
            end
            if cfg[:parsing].blank? && rules.respond_to?(:parsing_for)
              pr = rules.parsing_for(:hearings)
              cfg[:parsing] = pr.to_sym if pr.present?
            end
            return cfg
          end
        end

        {}
      end

      def default_connection
        Faraday.new(url: @base_url) do |f|
          f.adapter Faraday.default_adapter
        end
      end

      # @lat: [[download-bounds#Download bounds]]
      def default_attachment_connection
        if @retrieval == :legistar
          Sway::FaradayStack.legistar_attachment
        else
          @connection || default_connection
        end
      end

      def discover_html_hearings(bill, sway_locale, conn)
        return [] if @base_url.blank?

        ext_id = bill.external_id.to_s.strip
        template = @endpoints[:details] || "/details/:external_id"
        path = template.gsub(":external_id", ext_id.downcase)

        response =
          begin
            conn.get(path)
          rescue Faraday::Error => e
            raise BillProcessingError, "fetch_hearings: network error: #{e.message.to_s[0, 500]}"
          end

        unless response.status.between?(200, 299)
          raise BillProcessingError, "fetch_hearings: HTTP #{response.status} for #{ext_id}"
        end

        parse_hearings_payload(response.body)
      end

      def parse_html_entries(doc)
        entries = doc.css(".hearing-entry")
        if entries.any?
          return entries.map.with_index do |entry, idx|
            committee = entry.at_css(".committee")&.text&.strip
            date = entry.at_css(".date")&.text&.strip
            time = entry.at_css(".time")&.text&.strip
            location = entry.at_css(".location")&.text&.strip

            {
              "EventId" => idx + 1,
              "EventDate" => date,
              "EventTime" => time,
              "EventLocation" => location,
              "EventBodyName" => committee
            }
          end
        end

        hearings = []
        doc.css("table#billIndex tbody tr, tr").each do |row|
          text = row.text
          next unless text.include?("PM") || text.include?("AM")

          row.css("td").each do |cell|
            content = cell.text.strip
            next unless content.match?(/\d{1,2}\/\d{1,2}\/\d{4}\s*-\s*\d{1,2}:\d{2}\s*(?:AM|PM)/i)

            parts = content.split("\n").map(&:strip).reject(&:empty?)
            comm = parts.first
            dt_part = parts[1] || parts.first
            dt_match = dt_part.match(/(?<date>\d{1,2}\/\d{1,2}\/\d{4})\s*-\s*(?<time>\d{1,2}:\d{2}\s*(?:AM|PM))/i)

            hearings << {
              "EventId" => hearings.size + 1,
              "EventDate" => dt_match ? dt_match[:date] : nil,
              "EventTime" => dt_match ? dt_match[:time] : nil,
              "EventLocation" => nil,
              "EventBodyName" => comm
            }
          end
        end
        hearings
      end

      def discover_rest_hearings(bill, sway_locale, conn)
        ext_id = bill.external_id.to_s.strip
        template = @endpoints[:hearings] || "/hearings/:external_id"
        path = template.gsub(":external_id", ext_id)

        response =
          begin
            conn.get(path)
          rescue Faraday::Error => e
            raise BillProcessingError, "fetch_hearings: network error: #{e.message.to_s[0, 500]}"
          end

        unless response.status.between?(200, 299)
          raise BillProcessingError, "fetch_hearings: HTTP #{response.status} for #{ext_id}"
        end

        parse_hearings_payload(response.body)
      end

      def parse_hearings_payload(body)
        case @parsing
        when :generic_html
          doc = Nokogiri::HTML(body)
          parse_html_entries(doc)
        when :generic_rest, :legistar
          parse_rest_entries(body)
        else
          if body.to_s.strip.start_with?("<")
            doc = Nokogiri::HTML(body)
            parse_html_entries(doc)
          else
            parse_rest_entries(body)
          end
        end
      end

      def parse_rest_entries(body_or_parsed)
        parsed = if body_or_parsed.is_a?(String)
          begin
            JSON.parse(body_or_parsed)
          rescue
            {}
          end
        elsif body_or_parsed.is_a?(Hash) || body_or_parsed.is_a?(Array)
          body_or_parsed
        else
          {}
        end

        return [] if parsed.blank?

        items =
          if parsed.is_a?(Array)
            parsed
          elsif parsed.is_a?(Hash)
            list = parsed["hearings"] || parsed[:hearings] ||
              parsed["results"] || parsed[:results] ||
              parsed["events"] || parsed[:events]
            if list.is_a?(Array)
              list
            elsif single_hearing_item?(parsed)
              [parsed]
            else
              []
            end
          else
            []
          end

        items.filter_map do |item|
          next unless item.is_a?(Hash)

          event = {
            "EventId" => item["EventId"] || item[:EventId] || item["id"] || item[:id],
            "EventDate" => (item["EventDate"] || item[:EventDate] || item["date"] || item[:date])&.to_s,
            "EventTime" => (item["EventTime"] || item[:EventTime] || item["time"] || item[:time])&.to_s,
            "EventLocation" => (item["EventLocation"] || item[:EventLocation] || item["room"] || item["location"] || item[:room] || item[:location])&.to_s,
            "EventBodyName" => (item["EventBodyName"] || item[:EventBodyName] || item["committee"] || item[:committee])&.to_s
          }

          event if event.values.any?(&:present?)
        end
      end

      def single_hearing_item?(hash)
        return false unless hash.is_a?(Hash)

        (hash["id"] || hash[:id] || hash["EventId"] || hash[:EventId] ||
         hash["date"] || hash[:date] || hash["EventDate"] || hash[:EventDate] ||
         hash["time"] || hash[:time] || hash["EventTime"] || hash[:EventTime] ||
         hash["room"] || hash[:room] || hash["location"] || hash[:location] ||
         hash["EventLocation"] || hash[:EventLocation] ||
         hash["committee"] || hash[:committee] || hash["EventBodyName"] || hash[:EventBodyName]).present?
      end

      def write_hearings_artifact(bill, sway_locale, hearings)
        artifact_path = Legislation::Paths.hearings_file(bill.external_id, sway_locale: sway_locale.name)
        payload = {
          "events" => hearings,
          "attachments" => [],
          "attachment_discovery" => {"found" => 0, "kept" => 0, "recorded" => 0, "truncated" => false}
        }
        Legislation::ArtifactWriter.write(
          artifact_path,
          JSON.pretty_generate(payload),
          stage: "fetch_hearings",
          atomic: false
        )
      end

      def coerce_matter_id!(value)
        case value
        when ::Integer
          raise BillProcessingError, "fetch_hearings: matter_id must be > 0 (got #{value})" if value <= 0
          raise BillProcessingError, "fetch_hearings: matter_id out of range (got #{value})" if value > MATTER_ID_MAX

          value
        when ::String
          raise BillProcessingError, "fetch_hearings: matter_id must be 1-10 digits (got #{value.inspect})" unless value.match?(/\A\d{1,10}\z/)

          coerced = Integer(value, 10)
          raise BillProcessingError, "fetch_hearings: matter_id must be > 0 (got #{value})" if coerced <= 0
          raise BillProcessingError, "fetch_hearings: matter_id out of range (got #{coerced})" if coerced > MATTER_ID_MAX

          coerced
        else
          raise BillProcessingError, "fetch_hearings: matter_id must be Integer-coercible (got #{value.class.name})"
        end
      end

      def coerce_attachment_id(value)
        case value
        when ::Integer
          value if value.positive? && value <= MATTER_ID_MAX
        when ::String
          return nil unless value.match?(/\A\d{1,10}\z/)

          coerced = Integer(value, 10)
          coerced if coerced.positive? && coerced <= MATTER_ID_MAX
        end
      end

      def legistar_string(value)
        value if value.is_a?(::String)
      end

      def event_to_hearing_hash(event)
        {
          "EventId" => coerce_attachment_id(event["EventId"]),
          "EventDate" => legistar_string(event["EventDate"]),
          "EventTime" => legistar_string(event["EventTime"]),
          "EventLocation" => legistar_string(event["EventLocation"]),
          "EventBodyName" => legistar_string(event["EventBodyName"])
        }
      end

      def verify_matter_exists!(bill, matter_id_int)
        return if matter_exists?(matter_id_int)

        raise BillProcessingError,
          "fetch_hearings: matter_id #{matter_id_int} does not exist upstream " \
          "(Matters/#{matter_id_int} -> 404) for bill ##{bill.id} — the empty Histories " \
          "collection is a stale metadata.json id, not an absence of hearings; recorded nothing"
      end

      def lookup_matter_id_from_metadata(bill, sway_locale = nil)
        locale_name = sway_locale&.name || bill.sway_locale&.name
        metadata_path = Legislation::Paths.bill_metadata_file(bill.external_id, sway_locale: locale_name)
        unless metadata_path.exist?
          raise BillProcessingError,
            "fetch_hearings: no metadata.json at #{metadata_path}. " \
            "The fetch-bills stage writes that file — include it in the run for this bill."
        end

        matter_id = Legislation::BillMetadata.matter_id(bill.external_id, sway_locale: locale_name)
        if matter_id.nil?
          raise BillProcessingError,
            "fetch_hearings: matter_id missing or not Integer-coercible in metadata.json"
        end

        matter_id #: (Integer | String)
      end

      def update_bill_provisioning(bill)
        return unless bill.respond_to?(:bill_llm_provisioning)

        provisioning = bill.bill_llm_provisioning || (bill.build_bill_llm_provisioning if bill.respond_to?(:build_bill_llm_provisioning))
        return unless provisioning

        provisioning.testimony_fetched_at = Time.zone.now
        provisioning.save! if provisioning.respond_to?(:save!)
      end
    end
  end
end

GenericHearingsAdapter = Legislation::Adapters::GenericHearingsAdapter
