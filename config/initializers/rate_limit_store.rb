# frozen_string_literal: true

# @lat: [[identity-and-access#Identity and access#The rate limit store swaps in after boot]]
Rails.application.config.after_initialize do
  unless Rails.env.test?
    ApplicationController::RATE_LIMIT_STORE.backend = Rails.cache
  end
end
