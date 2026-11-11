# frozen_string_literal: true

module Scraper
  module OpenStates
    class LegislatorVotes
      include FaradayConnector

      # @lat: [[jurisdiction-rules#Jurisdiction declarations#Published legislator votes#The vote fetchers are one interface chosen at run time]]
      def initialize(bill:, roll_call_number:, roll_call_chamber:)
        @region_code = bill.sway_locale.region_code
        @bill_created_at_year = bill.introduced_date_time_utc.year
        @external_bill_id = bill.external_id
      end

      def content_type
        "application/json"
      end

      def chamber_name
        raise NotImplementedError, "Subclasses must define chamber_name"
      end

      # @lat: [[open-states-vote-number-unwired#Why the OpenStates House/Senate scrapers' vote_number raises]]
      def vote_number
        raise NotImplementedError,
          "No OpenStates #{chamber_name} scraper exists for this state. Maryland is " \
            "the only state supported, through Scraper::Maryland::LegislatorVotes."
      end

      def do_request
        vote_number

        get(endpoint)
      end

      def do_process
        return [] unless result

        (result[:votes] || [])
          .filter_map do |v_|
            v = v_.deep_symbolize_keys
            support =
              case v[:option]&.downcase&.strip
              when "no"
                "AGAINST"
              when "yes"
                "FOR"
              end
            next unless support

            voter = (v[:voter] || {}).deep_symbolize_keys
            name_parts = voter[:name].to_s.split(" ", 2)

            Scraper::LegislatorVote.new(
              external_id: voter[:id].to_s,
              support: support,
              first_name: name_parts[0].to_s,
              last_name: name_parts[1].to_s,
              party: voter[:party].to_s,
              state_code: @region_code.to_s
            )
          end
      end

      private

      def result
        SwayLogging.info(
          "Scraper::OpenStates::#{chamber_name}.result - Request URL - #{endpoint}"
        )
        @result ||= JSON.parse(request.value!).dig(:votes, 0)
      end

      def endpoint
        "/bills/#{@region_code}/#{@bill_created_at_year}/#{@external_bill_id}"
      end
    end
  end
end
