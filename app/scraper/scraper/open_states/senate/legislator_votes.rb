# frozen_string_literal: true

module Scraper
  module OpenStates
    module Senate
      class LegislatorVotes < Scraper::OpenStates::LegislatorVotes
        include ApiConnector

        def chamber_name
          "Senate"
        end
      end
    end
  end
end
