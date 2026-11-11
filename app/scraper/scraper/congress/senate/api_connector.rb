# frozen_string_literal: true

module Scraper
  module Congress
    module Senate
      module ApiConnector
        include FaradayConnector

        def url
          "https://www.senate.gov"
        end

        def auth
        end
      end
    end
  end
end
