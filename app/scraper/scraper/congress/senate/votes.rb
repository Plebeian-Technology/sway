# typed: true
# frozen_string_literal: true

# https://medium.com/@zozulyak.nick/ruby-class-pattern-to-work-with-api-requests-with-built-in-async-approach-bf0713a7dc96

module Scraper
  module Congress
    module Senate
      # https://github.com/LibraryOfCongress/api.congress.gov/issues/64#issuecomment-1403894201
      # https://www.senate.gov/legislative/LIS/roll_call_lists/vote_menu_117_2.xml
      class Votes
        include ApiConnector

        def initialize(congress)
          @congress = congress # 119
          @session = Time.zone.now.year.even? ? 2 : 1
        end

        def content_type
          "application/json"
        end

        def do_request
          get("legislative/LIS/roll_call_lists/vote_menu_#{@congress}_#{@session}.xml")
        end

        def do_process
          result&.dig("vote_summary", "votes", "vote") || []
        end

        private

        def result
          Hash.from_xml(request.value!)
        end
      end
    end
  end
end
