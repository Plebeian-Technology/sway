# typed: true
# frozen_string_literal: true

# https://medium.com/@zozulyak.nick/ruby-class-pattern-to-work-with-api-requests-with-built-in-async-approach-bf0713a7dc96

module Scraper
  module Congress
  module House
    Vote = Data.define(:external_id, :support)
  end
  end
end
