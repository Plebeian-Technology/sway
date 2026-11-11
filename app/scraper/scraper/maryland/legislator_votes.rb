# frozen_string_literal: true

require "open-uri"

module Scraper
  module Maryland
    class LegislatorVotes
      include ApiConnector

      def initialize(bill:, roll_call_number:, roll_call_chamber:)
        @bill = bill
        @sway_locale = bill.sway_locale
        @roll_call_number = roll_call_number
        @roll_call_chamber = roll_call_chamber
      end

      def content_type
        "application/pdf"
      end

      # @lat: [[maryland-legislator-votes-scraper-spec-design#The mutation regression]]
      def do_request(year_offset: 0)
        introduced = @bill.introduced_date_time_utc
        return nil if introduced.nil?

        OpenURI.open_uri("#{url}#{endpoint(year_offset)}")
      rescue OpenURI::HTTPError => e
        SwayLogging.warn("Failed to open URI: #{e.message}")
        raise e unless e.message.include?("404")
        unless introduced && introduced.year - year_offset > Time.current.year - 4
          raise e
        end

        do_request(year_offset: year_offset + 1)
      end

      def do_process
        return [] unless result

        reader = PDF::Reader.new(result)

        page = reader.pages.first #: PDF::Reader::Page?
        return [] if page.nil?

        # @lat: [[current-legislator-term#Which term a legislator is serving now#The vote-entry roster is everyone who ever held the seat#Matching a name resolves against the roster of the vote's own day]]
        wanted_title = (@roll_call_chamber == "senate") ? "Senator" : "Delegate"
        legislators =
          LegislatorRoster
            .new(sway_locale: @sway_locale, on: voted_on || Date.current)
            .terms
            .select { |term| term.title == wanted_title }
            .map(&:legislator)

        last_names =
          page
            .text
            .split("\n")
            .map { |line| line.split("  ").compact_blank }
            .flatten
            .map { |n| n.strip.downcase }

        key = ::LegislatorVote::Support::FOR

        last_names
          .filter_map do |last_name|
            if last_name.downcase.include?("voting yea")
              key = ::LegislatorVote::Support::FOR
              next
            elsif last_name.downcase.include?("voting nay")
              key = ::LegislatorVote::Support::AGAINST
              next
            elsif last_name.downcase.include?("not voting") ||
                last_name.downcase.include?("excused")
              key = ::LegislatorVote::Support::ABSTAIN
              next
            end

            next if key == ::LegislatorVote::Support::ABSTAIN

            l =
              legislators.find do |legislator|
                if last_name.downcase == "speaker"
                  legislator.last_name.casecmp?("jones") &&
                    legislator.first_name.casecmp?("adrienne")
                elsif last_name.downcase.include?("president")
                  legislator.last_name.casecmp?("ferguson") &&
                    legislator.first_name.casecmp?("bill")
                elsif last_name.include?(", ")
                  last, first = last_name.split(", ")
                  first && legislator.last_name.casecmp?(last) &&
                    legislator.first_name.downcase.start_with?(
                      first.delete(".").downcase
                    )
                else
                  legislator.last_name.casecmp?(last_name)
                end
              end || last_name

            if l.blank? || l.is_a?(String)
              nil
            else
              Scraper::LegislatorVote.new(
                external_id: l.external_id.to_s,
                support: key,
                first_name: l.first_name.to_s,
                last_name: l.last_name.to_s,
                party: l.party.to_s,
                state_code: @sway_locale.region_code.to_s
              )
            end
          end
      end

      private

      def voted_on
        (@roll_call_chamber == "senate") ? @bill.senate_vote_date_time_utc : @bill.house_vote_date_time_utc
      end

      def result
        @result ||= request.value!
      end

      def endpoint(year_offset = 0)
        year = @bill.introduced_date_time_utc.year - year_offset
        "/#{year}RS/votes/#{@roll_call_chamber}/#{roll}.pdf"
      end

      def roll
        @roll_call_number.to_s.rjust(3, "0")
      end
    end
  end
end
