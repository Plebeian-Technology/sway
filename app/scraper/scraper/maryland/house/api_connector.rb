# typed: true
# frozen_string_literal: true

# https://medium.com/@zozulyak.nick/ruby-class-pattern-to-work-with-api-requests-with-built-in-async-approach-bf0713a7dc96

module Scraper
  module Maryland
    module House
      module ApiConnector
        include FaradayConnector

        def url
          "https://mgaleg.maryland.gov/2025RS/votes/house"
        end

        def auth
          # none
        end
      end
    end
  end
end
