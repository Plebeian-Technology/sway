# frozen_string_literal: true

module Scraper
  LegislatorVote = Data.define(
    :external_id,
    :support,
    :first_name,
    :last_name,
    :party,
    :state_code
  )
end
