# typed: true
# frozen_string_literal: true

# https://medium.com/@zozulyak.nick/ruby-class-pattern-to-work-with-api-requests-with-built-in-async-approach-bf0713a7dc96

require "open-uri"

module Scraper
  module Maryland
    class LegislatorVotes
      include ApiConnector
      extend T::Sig

      def initialize(bill, roll_call_number, roll_call_chamber)
        @bill = bill # ex. hr815
        @sway_locale = bill.sway_locale
        @roll_call_number = roll_call_number
        @roll_call_chamber = roll_call_chamber
      end

      def content_type
        "application/pdf"
      end

      # r = Faraday.get('https://mgaleg.maryland.gov/2025RS/votes/house/0549.pdf').body
      def do_request
        # get(endpoint)
        T.unsafe(OpenURI).open_uri("#{url}#{endpoint}")
      end

      sig { returns(T::Array[Scraper::Maryland::Vote]) }
      def do_process
        return [] unless result

        # io = OpenURI.open_uri('https://mgaleg.maryland.gov/2025RS/votes/house/0549.pdf')
        reader = PDF::Reader.new(result)

        page = reader.pages.first
        if page.nil?
          return []
        end

        legislators = Legislator.joins(:district).where(
          title: (@roll_call_chamber == "senate") ? "Senator" : "Delegate",
          district: {
            sway_locale: @sway_locale
          }
        )

        last_names = page.text.split("\n").map { |line| line.split("  ").compact_blank }.flatten.map { |n| n.strip.downcase }

        key = LegislatorVote::Support::FOR

        last_names.map do |last_name|
          if last_name.downcase.include?("voting yea")
            key = LegislatorVote::Support::FOR
            next
          elsif last_name.downcase.include?("voting nay")
            key = LegislatorVote::Support::AGAINST
            next
          elsif last_name.downcase.include?("not voting") || last_name.downcase.include?("excused")
            key = LegislatorVote::Support::ABSTAIN
            next
          end

          l = legislators.find do |legislator|
            if last_name.downcase == "speaker"
              # Maryland house speaker
              # https://en.wikipedia.org/wiki/List_of_speakers_of_the_Maryland_House_of_Delegates
              legislator.last_name.casecmp?("jones") && legislator.first_name.casecmp?("adrienne")
            elsif last_name.downcase.include?("president")
              legislator.last_name.casecmp?("ferguson") && legislator.first_name.casecmp?("bill")
            elsif last_name.include?(", ")
              last, first = last_name.split(", ")
              legislator.last_name.casecmp?(last) && legislator.first_name.downcase.start_with?(first.delete(".").downcase)
            else
              legislator.last_name.casecmp?(last_name)
            end
          end || last_name

          if l.nil? || l.is_a?(String)
            nil
          else
            Vote.new(l.external_id, key)
          end
        end.compact
      end

      private

      def result
        @result ||= request.value!
      end

      def endpoint
        "/#{@bill.introduced_date_time_utc.year}RS/votes/#{@roll_call_chamber}/#{roll}.pdf"
      end

      def roll
        @roll_call_number.to_s.rjust(3, "0") # 001, 002, 010, 034, 100, etc.
      end
    end
  end
end
