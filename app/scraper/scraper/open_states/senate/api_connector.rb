# frozen_string_literal: true

module Scraper
  module OpenStates
    module Senate
      module ApiConnector
        def url
          "https://v3.openstates.org"
        end

        # @lat: [[jurisdiction-rules#Jurisdiction declarations#Published legislator votes#The vote fetchers are one interface chosen at run time]]
        def auth
          EnvSecret.read("OPEN_STATES_API_KEY")
        end
      end
    end
  end
end
