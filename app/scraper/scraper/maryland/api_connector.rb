# frozen_string_literal: true

module Scraper
  module Maryland
    module ApiConnector
      include FaradayConnector

      def url
        "https://mgaleg.maryland.gov"
      end

      def auth
      end
    end
  end
end
