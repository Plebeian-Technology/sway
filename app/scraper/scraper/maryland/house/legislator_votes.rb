# typed: true
# frozen_string_literal: true

# https://medium.com/@zozulyak.nick/ruby-class-pattern-to-work-with-api-requests-with-built-in-async-approach-bf0713a7dc96

module Scraper
  module Maryland
    module House
      class LegislatorVotes
        include ApiConnector
        extend T::Sig

        def initialize(bill_external_id, roll_call_number, sway_locale)
          @bill_external_id = bill_external_id # ex. hr815
          @roll_call_number = roll_call_number
          @sway_locale = sway_locale
        end

        def content_type
          "application/pdf"
        end

        # r = Faraday.get('https://mgaleg.maryland.gov/2025RS/votes/house/0549.pdf').body
        def do_request
          get("#{roll}.pdf")
        end

        sig { returns(T::Array[Scraper::Maryland::House::Vote]) }
        def do_process
          return [] unless result

          # io = OpenURI.open_uri('https://mgaleg.maryland.gov/2025RS/votes/house/0549.pdf')
          reader = PDF::Reader.new(result)

          page = reader.pages.first
          if page.nil?
            return []
          end

          legislators = Legislator.joins(:district).where(
            title: "Delegate",
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
              next
            elsif last_name.downcase.include?("not voting") || last_name.downcase.include?("excused")
              next
            end

            l = legislators.find do |legislator|
              if last_name == "Speaker"
                # Maryland house speaker
                # https://en.wikipedia.org/wiki/List_of_speakers_of_the_Maryland_House_of_Delegates
                legislator.last_name.casecmp?("jones") && legislator.first_name.casecmp?("adrienne")
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

        def roll
          @roll_call_number.to_s.rjust(3, "0") # 001, 002, 010, 034, 100, etc.
        end
      end
    end
  end
end
