# frozen_string_literal: true

require "faraday"
require "json"

# @lat: [[legislation-pipeline#Upstream jurisdiction adapters]]
module Legislation
  module Adapters
    class GenericVoteAdapter
      attr_reader :config, :engine, :retrieval, :parsing, :base_url, :endpoints, :metadata_mapping, :api_key_secret, :client, :jurisdiction, :connection

      def initialize(config_or_locale = {}, connection: nil, **kwargs)
        base_config = extract_config(config_or_locale)
        @config = kwargs.any? ? base_config.merge(kwargs) : base_config
        raw_engine = @config[:engine].presence
        raw_retrieval = @config[:retrieval].presence || @config[:retrieval_strategy].presence
        raw_parsing = @config[:parsing].presence || @config[:parser_format].presence

        @engine = (raw_engine || raw_retrieval || "manual").to_s
        @retrieval = (raw_retrieval || @engine).to_sym
        @parsing = (raw_parsing || @engine).to_sym
        @base_url = @config[:base_url]
        @endpoints = (@config[:endpoints] || {}).deep_symbolize_keys
        @metadata_mapping = (@config[:metadata_mapping] || {}).deep_symbolize_keys
        @api_key_secret = @config[:api_key_secret]
        @client = @config[:client]
        @jurisdiction = @config[:jurisdiction]
        @connection = connection
      end

      def fetch_votes(bill, connection: nil)
        return [] if bill.nil?

        retrieval = determine_retrieval(bill)
        return [] if retrieval == :manual || retrieval == :unavailable

        conn = connection || @connection || default_connection

        case retrieval
        when :congress_dot_gov, :generic_csv, :congress
          fetch_congress_votes(bill)
        when :generic_html
          fetch_html_votes(bill)
        when :open_states
          fetch_open_states_votes(bill)
        when :legistar
          fetch_legistar_votes(bill)
        when :generic_rest, :generic_json
          fetch_generic_votes(bill, conn)
        else
          raise ArgumentError, "Unsupported vote engine: #{(@config[:engine] || @retrieval).inspect}"
        end
      end

      def determine_retrieval(bill = nil)
        if %i[maryland_general_assembly mga generic_html].include?(@retrieval)
          return :generic_html
        end

        if @config[:retrieval].present? || @config[:retrieval_strategy].present? || @config[:engine].present?
          return @retrieval
        end

        if %i[open_states legistar generic_rest generic_json congress_dot_gov generic_csv congress unavailable].include?(@retrieval)
          return @retrieval
        end

        target_locale = bill&.sway_locale || @sway_locale
        rules = if target_locale
          if target_locale.respond_to?(:declared_jurisdiction_rules)
            target_locale.declared_jurisdiction_rules || target_locale.jurisdiction_rules
          elsif target_locale.respond_to?(:jurisdiction_rules)
            target_locale.jurisdiction_rules
          end
        end

        if rules&.respond_to?(:parsing_for) && rules.parsing_for(:vote) == "generic_html"
          return :generic_html
        end

        if rules&.respond_to?(:retrieval_for)
          ret = rules.retrieval_for(:vote)&.to_sym
          return :generic_html if %i[maryland_general_assembly mga generic_html].include?(ret)
          return ret if ret.present?
        end

        if %i[maryland_general_assembly mga generic_html].include?(@retrieval)
          return :generic_html
        end

        @retrieval
      end

      def legistar_client(sway_locale = nil)
        target_locale = sway_locale || @sway_locale
        vote_rules = target_locale&.jurisdiction_rules&.vote_rules
        legislation_rules = target_locale&.jurisdiction_rules&.legislation_rules

        client_name = (vote_rules&.[](:client) || vote_rules&.[]("client")).presence ||
          (legislation_rules&.[](:client) || legislation_rules&.[]("client")).presence ||
          @client.presence ||
          @config[:client].presence ||
          @config["client"].presence ||
          @config[:jurisdiction].presence ||
          @config.dig(:params, :client).presence ||
          (target_locale.city if target_locale.respond_to?(:city)).presence

        raise ArgumentError, "No client configured for Legistar vote adapter" if client_name.blank?

        @legistar_clients ||= {}
        @legistar_clients[client_name.to_s] ||= Legistar::Client.new(
          client: client_name.to_s,
          connection: @connection || default_connection
        )
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
        elsif input.respond_to?(:vote_rules)
          input
        end

        if rules&.respond_to?(:vote_rules)
          v_rules = rules&.vote_rules
          if v_rules.is_a?(Hash) && v_rules.any?
            cfg = v_rules.deep_symbolize_keys
            if cfg[:retrieval].blank? && rules.respond_to?(:retrieval_for)
              ret = rules.retrieval_for(:vote)
              cfg[:retrieval] = ret.to_sym if ret.present?
            end
            if cfg[:parsing].blank? && rules.respond_to?(:parsing_for)
              pr = rules.parsing_for(:vote)
              cfg[:parsing] = pr.to_sym if pr.present?
            end
            if cfg[:client].blank? && rules.respond_to?(:legislation_rules)
              leg_client = rules.legislation_rules&.dig(:client) || rules.legislation_rules&.dig("client")
              cfg[:client] = leg_client if leg_client.present?
            end
            return cfg
          end
        end

        {}
      end

      def default_connection
        return nil if @base_url.blank?
        Faraday.new(url: @base_url) do |f|
          f.adapter Faraday.default_adapter
        end
      end

      def fetch_congress_votes(bill)
        results = []

        senate_rc = bill.vote&.senate_roll_call_vote_number
        senate_year = bill.senate_vote_date_time_utc&.year
        if senate_rc.present? && senate_year.present? && defined?(Scraper::Congress::Senate::LegislatorVotes)
          scraper = Scraper::Congress::Senate::LegislatorVotes.new(year: senate_year, roll_call_number: senate_rc)
          votes = scraper.process
          votes.each do |v|
            results << {
              legislator_external_id: v.external_id,
              vote_value: v.support,
              voted_on: bill.senate_vote_date_time_utc&.to_date,
              chamber: "senate",
              last_name: v.respond_to?(:last_name) ? v.last_name : nil,
              state_code: v.respond_to?(:state_code) ? v.state_code : nil,
              raw_data: v
            }
          end
        end

        house_rc = bill.vote&.house_roll_call_vote_number
        house_year = bill.house_vote_date_time_utc&.year
        if house_rc.present? && house_year.present? && defined?(Scraper::Congress::House::LegislatorVotes)
          scraper = Scraper::Congress::House::LegislatorVotes.new(roll_call_number: house_rc, year: house_year)
          votes = scraper.process
          votes.each do |v|
            results << {
              legislator_external_id: v.external_id,
              vote_value: v.support,
              voted_on: bill.house_vote_date_time_utc&.to_date,
              chamber: "house",
              last_name: v.respond_to?(:last_name) ? v.last_name : nil,
              state_code: v.respond_to?(:state_code) ? v.state_code : nil,
              raw_data: v
            }
          end
        end

        results
      end

      def fetch_open_states_votes(bill)
        results = []

        senate_rc = bill.vote&.senate_roll_call_vote_number
        if senate_rc.present?
          scraper_class = open_states_scraper_for(bill, "senate")
          if scraper_class
            votes = scraper_class.new(bill: bill, roll_call_number: senate_rc, roll_call_chamber: "senate").process
            votes.each do |v|
              results << {
                legislator_external_id: v.external_id,
                vote_value: v.support,
                voted_on: bill.senate_vote_date_time_utc&.to_date,
                chamber: "senate",
                raw_data: v
              }
            end
          end
        end

        house_rc = bill.vote&.house_roll_call_vote_number
        if house_rc.present?
          scraper_class = open_states_scraper_for(bill, "house")
          if scraper_class
            votes = scraper_class.new(bill: bill, roll_call_number: house_rc, roll_call_chamber: "house").process
            votes.each do |v|
              results << {
                legislator_external_id: v.external_id,
                vote_value: v.support,
                voted_on: bill.house_vote_date_time_utc&.to_date,
                chamber: "house",
                raw_data: v
              }
            end
          end
        end

        results
      end

      def fetch_html_votes(bill)
        return [] unless defined?(Scraper::Maryland::LegislatorVotes)

        results = []

        senate_rc = bill.vote&.senate_roll_call_vote_number
        if senate_rc.present?
          votes = Scraper::Maryland::LegislatorVotes.new(
            bill: bill,
            roll_call_number: senate_rc,
            roll_call_chamber: "senate"
          ).process
          votes.each do |v|
            results << {
              legislator_external_id: v.external_id,
              vote_value: v.support,
              voted_on: bill.senate_vote_date_time_utc&.to_date,
              chamber: "senate",
              raw_data: v
            }
          end
        end

        house_rc = bill.vote&.house_roll_call_vote_number
        if house_rc.present?
          votes = Scraper::Maryland::LegislatorVotes.new(
            bill: bill,
            roll_call_number: house_rc,
            roll_call_chamber: "house"
          ).process
          votes.each do |v|
            results << {
              legislator_external_id: v.external_id,
              vote_value: v.support,
              voted_on: bill.house_vote_date_time_utc&.to_date,
              chamber: "house",
              raw_data: v
            }
          end
        end

        results
      end
      alias_method :fetch_maryland_votes, :fetch_html_votes

      def open_states_scraper_for(_bill, chamber)
        if chamber == "senate" && defined?(Scraper::OpenStates::Senate::LegislatorVotes)
          Scraper::OpenStates::Senate::LegislatorVotes
        elsif chamber == "house" && defined?(Scraper::OpenStates::House::LegislatorVotes)
          Scraper::OpenStates::House::LegislatorVotes
        end
      end

      def fetch_legistar_votes(bill)
        []
      end

      def fetch_generic_votes(bill, conn)
        return [] if conn.nil?
        template = @endpoints[:votes] || "/bills/:external_id/votes"
        endpoint = template.gsub(":external_id", bill.external_id.to_s)

        response =
          begin
            conn.get(endpoint)
          rescue Faraday::Error => e
            raise "API returned error: #{e.message}"
          end

        unless response.status.between?(200, 299)
          raise "API returned #{response.status}"
        end

        parse_generic_votes_payload(response.body)
      end

      def parse_generic_votes_payload(body_or_parsed)
        parsed = if body_or_parsed.is_a?(String)
          begin
            JSON.parse(body_or_parsed)
          rescue
            {}
          end
        else
          body_or_parsed
        end

        return [] if parsed.blank?

        items =
          if parsed.is_a?(Array)
            parsed
          elsif parsed.is_a?(Hash)
            list = parsed["votes"] || parsed[:votes] ||
              parsed["results"] || parsed[:results]
            if list.is_a?(Array)
              list
            elsif single_vote_item?(parsed)
              [parsed]
            else
              []
            end
          else
            []
          end

        items.filter_map do |item|
          next unless item.is_a?(Hash)

          ext_id = extract_field(item, @metadata_mapping[:legislator_external_id]) ||
            item["legislator_external_id"] || item[:legislator_external_id] ||
            item["voter_id"] || item[:voter_id]
          val = extract_field(item, @metadata_mapping[:vote_value]) ||
            item["vote_value"] || item[:vote_value] ||
            item["position"] || item[:position]

          next unless ext_id.present? || val.present?

          voted_on_raw = extract_field(item, @metadata_mapping[:voted_on]) || item["voted_on"] || item[:voted_on] || item["date"] || item[:date]
          chamber = extract_field(item, @metadata_mapping[:chamber]) || item["chamber"] || item[:chamber]

          voted_on =
            begin
              Date.parse(voted_on_raw.to_s) if voted_on_raw.present?
            rescue ArgumentError
              nil
            end

          {
            legislator_external_id: ext_id.to_s,
            vote_value: val.to_s,
            voted_on: voted_on,
            chamber: chamber&.to_s,
            raw_data: item
          }
        end
      end

      def single_vote_item?(hash)
        return false unless hash.is_a?(Hash)

        ext_id = extract_field(hash, @metadata_mapping[:legislator_external_id]) ||
          hash["legislator_external_id"] || hash[:legislator_external_id] ||
          hash["voter_id"] || hash[:voter_id]
        val = extract_field(hash, @metadata_mapping[:vote_value]) ||
          hash["vote_value"] || hash[:vote_value] ||
          hash["position"] || hash[:position]

        ext_id.present? || val.present?
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

GenericVoteAdapter = Legislation::Adapters::GenericVoteAdapter
