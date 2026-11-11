# frozen_string_literal: true

module Scraper
  module Congress
    # @lat: [[roll-call-identity#Identifying a congressional roll call#Why a wrong roll call raises rather than returns]]
    class RollCallNotOnTheBill < StandardError
    end
  end
end
