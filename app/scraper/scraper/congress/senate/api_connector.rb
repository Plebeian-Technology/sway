# typed: true
# frozen_string_literal: true

# https://medium.com/@zozulyak.nick/ruby-class-pattern-to-work-with-api-requests-with-built-in-async-approach-bf0713a7dc96

module Scraper
  module Congress
    module Senate
      # https://github.com/LibraryOfCongress/api.congress.gov/issues/64#issuecomment-1403894201
      module ApiConnector
        include FaradayConnector

        def url
          "https://www.senate.gov"
        end

        def auth
          # none
        end
      end
    end
  end
end
