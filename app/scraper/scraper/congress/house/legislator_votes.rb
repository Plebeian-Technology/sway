# typed: true
# frozen_string_literal: true

# https://medium.com/@zozulyak.nick/ruby-class-pattern-to-work-with-api-requests-with-built-in-async-approach-bf0713a7dc96

module Scraper
  module Congress
  module House
    class LegislatorVotes
      include ApiConnector

      def initialize(bill_external_id, roll_call_number)
        @bill_external_id = bill_external_id # ex. hr815
        @roll_call_number = roll_call_number
      end

      def content_type
        'text/xml'
      end

      # r = Faraday.get('https://clerk.house.gov/evs/2024/roll025.xml').body
      def do_request
        get("evs/#{Time.new.year}/roll#{roll}.xml")
      end

      def do_process
        return [] unless result

        Nokogiri.XML(result).search('recorded-vote').map do |vote|
          Vote.new(vote.at('legislator')['name-id'], vote.at('vote').text)
        end
      end

      private

      def result
        @result ||= request.value!
      end

      def roll
        @roll_call_number.to_s.rjust(3, '0') # 001, 002, 010, 034, 100, etc.
      end
    end
  end
  end
end
