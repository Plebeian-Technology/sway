# frozen_string_literal: true

module Scraper
    module Congress
        module Senate
            Vote = Data.define(:first_name, :last_name, :state_code, :party, :support)
        end
    end
end
