# frozen_string_literal: true

require "digest"
require "faraday"
require "json"

# @lat: [[legislation-pipeline#Upstream jurisdiction adapters]]
module Legislation
  module Adapters
    class GenericRosterAdapter
      attr_reader :config, :engine, :retrieval, :parsing, :base_url, :endpoints, :metadata_mapping, :api_key_secret, :client, :jurisdiction, :connection, :evidence_publisher, :evidence_jurisdiction, :evidence_source_url, :official_service

      def initialize(config_or_locale = {}, connection: nil, **kwargs)
        base_config = extract_config(config_or_locale)
        @config = kwargs.any? ? base_config.merge(kwargs) : base_config
        raw_engine = @config[:engine].presence
        raw_retrieval = @config[:retrieval].presence || @config[:retrieval_strategy].presence
        raw_parsing = @config[:parsing].presence || @config[:parser_format].presence

        @engine = (raw_engine || raw_retrieval || "generic_rest").to_s
        @retrieval = (raw_retrieval || @engine).to_sym
        @parsing = (raw_parsing || @engine).to_sym
        @base_url = @config[:base_url]
        @endpoints = (@config[:endpoints] || {}).deep_symbolize_keys
        @metadata_mapping = (@config[:metadata_mapping] || {}).deep_symbolize_keys
        @api_key_secret = @config[:api_key_secret]
        @client = @config[:client].presence || @config["client"].presence
        @jurisdiction = @config[:jurisdiction]
        @connection = connection

        @evidence_publisher = @config[:evidence_publisher].presence ||
          @config["evidence_publisher"].presence ||
          @config.dig(:roster_rules, :evidence_publisher).presence ||
          @config.dig("roster_rules", "evidence_publisher").presence
        @evidence_jurisdiction = @config[:evidence_jurisdiction].presence ||
          @config["evidence_jurisdiction"].presence ||
          @config.dig(:roster_rules, :evidence_jurisdiction).presence ||
          @config.dig("roster_rules", "evidence_jurisdiction").presence
        @evidence_source_url = @config[:evidence_source_url].presence ||
          @config["evidence_source_url"].presence ||
          @config.dig(:roster_rules, :evidence_source_url).presence ||
          @config.dig("roster_rules", "evidence_source_url").presence
        @official_service = @config[:official_service]
      end

      def fetch_roster(sway_locale:, connection: nil)
        return [] if @retrieval == :unavailable || @engine == "unavailable" || @retrieval == :curated || @engine == "curated"

        conn = connection || @connection || default_connection

        payload = retrieve_roster_payload(sway_locale, conn)
        return [] if payload.blank?

        parse_roster_payload(payload, sway_locale)
      end

      def fetch_official_service(sway_locale:, connection: nil)
        OfficialEvidence::Readers::ServiceReader.new(
          profile: official_service,
          sway_locale: sway_locale,
          connection: connection || @connection
        ).call
      end

      def legistar_client(sway_locale = nil)
        target_locale = sway_locale || @sway_locale
        roster_rules = target_locale&.jurisdiction_rules&.roster_rules
        leg_rules = target_locale&.jurisdiction_rules&.legislation_rules

        client_name = (roster_rules&.[](:client) || roster_rules&.[]("client")).presence ||
          (leg_rules&.[](:client) || leg_rules&.[]("client")).presence ||
          @client.presence ||
          @config[:client].presence ||
          @config["client"].presence ||
          @config[:jurisdiction].presence ||
          @config.dig(:params, :client).presence ||
          (target_locale.city if target_locale.respond_to?(:city)).presence

        raise ArgumentError, "No client configured for Legistar roster adapter" if client_name.blank?

        @legistar_clients ||= {}
        @legistar_clients[client_name.to_s] ||= Legistar::Client.new(
          client: client_name.to_s,
          connection: @connection || default_connection
        )
      end

      # @lat: [[legislation-pipeline#Upstream jurisdiction adapters]]
      def build_official_evidence(
        payload,
        retrieved_at: Time.current,
        fact_type: "roster",
        fact_presence: "present",
        date_precision: "none", **extra
      )
        supported_extra = %i[publisher jurisdiction source_url external_record_id sway_locale_id parsed_values date_semantics]
        unknown_extra = extra.keys - supported_extra
        raise ArgumentError, "Unsupported official evidence attributes: #{unknown_extra.join(", ")}" if unknown_extra.any?

        digest = Digest::SHA256.hexdigest(payload.to_s)
        attrs = {
          publisher: evidence_publisher,
          jurisdiction: evidence_jurisdiction,
          source_url: evidence_source_url,
          retrieved_at: retrieved_at,
          payload: payload.to_s,
          payload_hash: digest,
          fact_type: fact_type,
          fact_presence: fact_presence,
          date_precision: date_precision,
          parsed_values: {},
          date_semantics: {}
        }.merge(extra)

        OfficialEvidence.new(attrs)
      end

      private

      def extract_config(input)
        if input.is_a?(Hash)
          hash = input.deep_symbolize_keys
          if hash[:roster_rules].is_a?(Hash)
            return hash[:roster_rules].merge(hash.except(:roster_rules))
          end
          return hash
        end

        rules = if input.is_a?(SwayLocale)
          @sway_locale = input
          input.jurisdiction_rules
        elsif input.is_a?(SwayLocale::JurisdictionRules)
          input
        elsif input.respond_to?(:jurisdiction_rules)
          input.jurisdiction_rules
        elsif input.respond_to?(:roster_rules)
          input
        end

        if rules&.respond_to?(:roster_rules)
          r_rules = rules&.roster_rules
          if r_rules.is_a?(Hash) && r_rules.any?
            cfg = r_rules.deep_symbolize_keys
            if cfg[:retrieval].blank? && rules.respond_to?(:roster_retrieval)
              ret = rules.roster_retrieval
              cfg[:retrieval] = ret.to_sym if ret.present?
            elsif cfg[:retrieval].blank? && rules.respond_to?(:retrieval_for)
              ret = rules.retrieval_for(:roster)
              cfg[:retrieval] = ret.to_sym if ret.present?
            end
            if cfg[:parsing].blank? && rules.respond_to?(:roster_parsing)
              pr = rules.roster_parsing
              cfg[:parsing] = pr.to_sym if pr.present?
            elsif cfg[:parsing].blank? && rules.respond_to?(:parsing_for)
              pr = rules.parsing_for(:roster)
              cfg[:parsing] = pr.to_sym if pr.present?
            end
            if cfg[:client].blank? && rules.respond_to?(:legislation_rules)
              leg_client = rules.legislation_rules&.dig(:client) || rules.legislation_rules&.dig("client")
              cfg[:client] = leg_client if leg_client.present?
            end
            if cfg[:evidence_publisher].blank? && rules.respond_to?(:evidence_publisher)
              pub = rules.evidence_publisher
              cfg[:evidence_publisher] = pub if pub.present?
            end
            if cfg[:evidence_jurisdiction].blank? && rules.respond_to?(:evidence_jurisdiction)
              jur = rules.evidence_jurisdiction
              cfg[:evidence_jurisdiction] = jur if jur.present?
            end
            if cfg[:evidence_source_url].blank? && rules.respond_to?(:evidence_source_url)
              src = rules.evidence_source_url
              cfg[:evidence_source_url] = src if src.present?
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

      def retrieve_roster_payload(sway_locale, conn)
        case @retrieval
        when :congress_dot_gov, :congress, :congress_api
          retrieve_congress_payload(conn)
        when :open_states, :open_states_api
          retrieve_open_states_payload(conn)
        when :generic_rest, :generic_json, :generic_graphql
          retrieve_generic_rest_payload(conn)
        when :legistar
          retrieve_legistar_payload(sway_locale)
        when :curated, :unavailable
          []
        else
          raise ArgumentError, "Unsupported roster retrieval: #{@retrieval.inspect}"
        end
      end

      def parse_roster_payload(payload, sway_locale)
        case @parsing
        when :congress_dot_gov, :congress, :congress_api
          parse_congress_members(payload)
        when :open_states, :open_states_api
          parse_open_states_members(payload)
        when :generic_rest, :generic_json, :generic_graphql
          parse_generic_items(payload)
        when :legistar
          parse_legistar_persons(payload)
        when :curated, :unavailable
          []
        else
          if @metadata_mapping.present? || payload.is_a?(Array)
            parse_generic_items(payload)
          else
            raise ArgumentError, "Unsupported roster parser: #{@parsing.inspect}"
          end
        end
      end

      def retrieve_congress_payload(conn)
        base = (@base_url.presence || "").to_s.chomp("/")
        endpoint = if @endpoints[:members].present?
          @endpoints[:members]
        elsif base.present?
          base.end_with?("/member") ? base : "#{base}/member"
        else
          "/member"
        end

        api_key = EnvSecret.congress_gov_api_key!
        all_members = []
        offset = 0
        limit = 250

        loop do
          params = {
            api_key: api_key,
            format: "json",
            currentMember: "true",
            limit: limit,
            offset: offset
          }

          response =
            begin
              conn.get(endpoint, params)
            rescue Faraday::Error => e
              raise "API returned error: #{e.message}"
            end

          unless response.status.between?(200, 299)
            raise "API returned #{response.status}"
          end

          data =
            begin
              JSON.parse(response.body)
            rescue
              {}
            end

          page_members = data.is_a?(Array) ? data : (data["members"] || data[:members] || [])
          all_members.concat(page_members) if page_members.is_a?(Array)

          break if page_members.size < limit

          offset += limit
        end

        all_members
      end

      def parse_congress_members(parsed)
        return [] if parsed.blank?

        members = parsed.is_a?(Array) ? parsed : (parsed["members"] || parsed[:members] || [])
        return [] unless members.is_a?(Array)

        members.filter_map do |m|
          next unless m.is_a?(Hash)

          ext_id = m["bioguideId"] || m[:bioguideId]
          name = m["name"] || m[:name]
          next if ext_id.blank? && name.blank?

          first_name = m["firstName"] || m[:firstName]
          last_name = m["lastName"] || m[:lastName]

          if first_name.blank? && last_name.blank? && name.present? && name.include?(",")
            parts = name.split(",", 2)
            last_name = parts[0]&.strip
            first_name = parts[1]&.strip
          end

          party = m["partyName"] || m[:partyName] || m["party"] || m[:party]
          state = m["state"] || m[:state]

          raw_district = m.key?("district") ? m["district"] : m[:district]
          district = raw_district&.to_s

          depiction = m["depiction"] || m[:depiction]
          photo_url =
            if depiction.is_a?(Hash)
              (depiction["imageUrl"] || depiction[:imageUrl])&.to_s
            elsif depiction.is_a?(String)
              depiction
            end

          entry = {
            external_id: ext_id.to_s,
            full_name: name.to_s,
            first_name: first_name&.to_s,
            last_name: last_name&.to_s,
            party: party&.to_s,
            state: state&.to_s,
            photo_url: photo_url&.to_s,
            active: true,
            raw_data: m
          }
          entry[:district] = district if district.present?
          entry[:bioguideId] = ext_id.to_s if ext_id

          merged = m.merge(entry)
          merged["district"] = raw_district if !raw_district.nil? && m.key?("district")
          merged
        end
      end

      def retrieve_open_states_payload(conn)
        endpoint = @endpoints[:people] || "/people"
        api_key = EnvSecret.open_states_api_key!
        headers = {"X-API-KEY" => api_key}

        all_results = []
        page = 1
        max_page = 1

        loop do
          params = {per_page: 50, page: page} #: Hash[Symbol, String | Integer]
          params[:jurisdiction] = @jurisdiction.to_s if @jurisdiction.present?

          response =
            begin
              conn.get(endpoint, params, headers)
            rescue Faraday::Error => e
              raise "API returned error: #{e.message}"
            end

          unless response.status.between?(200, 299)
            raise "API returned #{response.status}"
          end

          data =
            begin
              JSON.parse(response.body)
            rescue
              {}
            end

          results = data.is_a?(Array) ? data : (data["results"] || data[:results] || [])
          all_results.concat(results) if results.is_a?(Array)

          pagination = data.is_a?(Hash) ? (data["pagination"] || data[:pagination]) : nil
          if pagination.is_a?(Hash)
            max_page = (pagination["max_page"] || pagination[:max_page] || 1).to_i
          end

          break if page >= max_page

          page += 1
        end

        all_results
      end

      def parse_open_states_people(parsed)
        return [] if parsed.blank?

        people = parsed.is_a?(Array) ? parsed : (parsed["results"] || parsed[:results] || [])
        return [] unless people.is_a?(Array)

        people.filter_map do |person|
          next unless person.is_a?(Hash)

          ext_id = person["id"] || person[:id]
          name = person["name"] || person[:name]
          next if ext_id.blank? && name.blank?

          given_name = person["given_name"] || person[:given_name]
          family_name = person["family_name"] || person[:family_name]
          party = person["party"] || person[:party]
          current_role = person["current_role"] || person[:current_role]
          current_role = {} unless current_role.is_a?(Hash)
          district = (current_role["district"] || current_role[:district])&.to_s
          title = current_role["title"] || current_role[:title]
          chamber = current_role["org_classification"] || current_role[:org_classification]
          photo_url = person["image"] || person[:image]

          entry = {
            external_id: ext_id.to_s,
            full_name: name.to_s,
            first_name: given_name&.to_s,
            last_name: family_name&.to_s,
            party: party&.to_s,
            district: district,
            title: title&.to_s,
            chamber: chamber&.to_s,
            photo_url: photo_url&.to_s,
            active: true,
            raw_data: person
          }
          entry[:id] = ext_id.to_s if ext_id
          person.merge(entry)
        end
      end
      alias_method :parse_open_states_members, :parse_open_states_people
      public :parse_open_states_people, :parse_open_states_members, :parse_congress_members

      def retrieve_generic_rest_payload(conn)
        endpoint = @endpoints[:members] || "/legislators"
        response =
          begin
            conn.get(endpoint)
          rescue Faraday::Error => e
            raise "API returned error: #{e.message}"
          end

        unless response.status.between?(200, 299)
          raise "API returned #{response.status}"
        end

        begin
          JSON.parse(response.body)
        rescue
          []
        end
      end

      def parse_generic_items(parsed)
        return [] if parsed.blank?

        items =
          if parsed.is_a?(Array)
            parsed
          elsif parsed.is_a?(Hash)
            list = parsed["legislators"] || parsed[:legislators] ||
              parsed["results"] || parsed[:results] ||
              parsed["members"] || parsed[:members] ||
              parsed["people"] || parsed[:people]
            if list.is_a?(Array)
              list
            elsif single_roster_item?(parsed)
              [parsed]
            else
              []
            end
          else
            []
          end

        items.filter_map do |item|
          next unless item.is_a?(Hash)

          ext_id = extract_field(item, @metadata_mapping[:external_id]) || item["external_id"] || item[:external_id] || item["id"] || item[:id]
          name = extract_field(item, @metadata_mapping[:full_name]) || item["full_name"] || item[:full_name] || item["name"] || item[:name]
          next if ext_id.blank? && name.blank?

          party = extract_field(item, @metadata_mapping[:party]) || item["party"] || item[:party]
          district = extract_field(item, @metadata_mapping[:district]) || item["district"] || item[:district]
          chamber = extract_field(item, @metadata_mapping[:chamber]) || item["chamber"] || item[:chamber]
          photo_url = extract_field(item, @metadata_mapping[:photo_url]) || item["photo_url"] || item[:photo_url]

          {
            external_id: ext_id.to_s,
            full_name: name.to_s,
            party: party&.to_s,
            district: district&.to_s,
            chamber: chamber&.to_s,
            photo_url: photo_url&.to_s,
            active: true,
            raw_data: item
          }
        end
      end

      def retrieve_legistar_payload(sway_locale)
        client = legistar_client(sway_locale)
        endpoint = @endpoints[:members] || "Persons"
        client.get(endpoint)
      rescue Legistar::Client::HttpError => e
        raise "API returned #{e.status}"
      rescue Legistar::Client::Error => e
        raise "API returned error: #{e.message}"
      end

      def parse_legistar_persons(parsed)
        return [] if parsed.blank?

        persons = parsed.is_a?(Array) ? parsed : [parsed]
        persons.filter_map do |person|
          next unless person.is_a?(Hash)

          ext_id = person["PersonId"] || person[:PersonId]
          name = person["PersonFullName"] || person[:PersonFullName] || person["PersonName"] || person[:PersonName]
          next if ext_id.blank? && name.blank?

          first_name = person["PersonFirstName"] || person[:PersonFirstName]
          last_name = person["PersonLastName"] || person[:PersonLastName]
          active = person["PersonActive"] == 1 || person["PersonActive"] == true

          {
            external_id: ext_id.to_s,
            full_name: name.to_s,
            first_name: first_name&.to_s,
            last_name: last_name&.to_s,
            active: active,
            raw_data: person
          }
        end
      end

      def single_roster_item?(hash)
        return false unless hash.is_a?(Hash)

        ext_id = extract_field(hash, @metadata_mapping[:external_id]) ||
          hash["external_id"] || hash[:external_id] ||
          hash["id"] || hash[:id] ||
          hash["bioguideId"] || hash[:bioguideId]
        name = extract_field(hash, @metadata_mapping[:full_name]) ||
          hash["full_name"] || hash[:full_name] ||
          hash["name"] || hash[:name]

        ext_id.present? || name.present?
      end

      def extract_field(record, path_expr)
        return nil if record.nil? || path_expr.blank?
        clean = path_expr.to_s.sub(/\A\$\.?/, "")
        parts = clean.split(".")
        val = record
        parts.each do |part|
          if part =~ /\A(.+)\[(\d+)\]\z/
            match = Regexp.last_match
            next unless match

            key = match[1].to_s
            idx = match[2].to_i
            next if key.empty?

            container = val.is_a?(Hash) ? (val[key] || val[key.to_sym]) : nil
            val = container.is_a?(Array) ? container[idx] : nil
          elsif val.is_a?(Hash)
            val = val[part] || val[part.to_sym]
          else
            return nil
          end
        end
        val
      end
    end
  end
end

GenericRosterAdapter = Legislation::Adapters::GenericRosterAdapter
