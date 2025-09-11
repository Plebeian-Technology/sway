# typed: true
# frozen_string_literal: true

# https://medium.com/@zozulyak.nick/ruby-class-pattern-to-work-with-api-requests-with-built-in-async-approach-bf0713a7dc96

module Scraper
  module OpenStates
    module House
      module ApiConnector
        include FaradayConnector

        def url
          # "https://v3.openstates.org"
          "https://mgaleg.maryland.gov"
        end

        def auth
          # ENV["OPEN_STATES_API_KEY"]
        end
      end
    end
  end
end
