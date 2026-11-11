# frozen_string_literal: true

module Scraper
  module OpenStates
    module House
      class LegislatorVotes < Scraper::OpenStates::LegislatorVotes
        include ApiConnector

        def chamber_name
          "House"
        end
      end
    end
  end
end
