# frozen_string_literal: true

source "https://rubygems.org"

ruby "3.4.1"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
# gem "rails", "~> 8"
gem "rails", "~> 8"

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5"

# # Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
# gem 'importmap-rails'

# # Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
# gem 'turbo-rails'

# # Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
# gem 'stimulus-rails'

# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
# gem "tailwindcss-rails"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# Camel Case json keys
# https://stackoverflow.com/questions/23794276/rails-render-json-object-with-camelcase
gem "jbuilder"

# Use Redis adapter to run Action Cable in production
# gem 'redis', '>= 4.0.1'

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[windows jruby]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# https://github.com/alexreisner/geocoder?tab=readme-ov-file#testing
gem "geocoder"

# https://rgeo.info/
# https://github.com/rgeo/rgeo
gem "rgeo"

# https://github.com/rgeo/rgeo-geojson
gem "rgeo-geojson"

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

# https://github.com/BrandonShar/inertia-rails-template/blob/main/Gemfile
gem "vite_rails"

# https://github.com/inertiajs/inertia-rails?tab=readme-ov-file
gem "inertia_rails"

# https://github.com/lostisland/faraday
# https://medium.com/@zozulyak.nick/ruby-class-pattern-to-work-with-api-requests-with-built-in-async-approach-bf0713a7dc96
gem "concurrent-ruby"

# https://github.com/lostisland/faraday
gem "faraday"

# https://github.com/mauricio/faraday_curl
# gem 'faraday_curl'

# https://github.com/cedarcode/webauthn-ruby
gem "webauthn"

# phone/sms verification
# https://www.twilio.com/docs/verify/sms
gem "twilio-ruby"

# Use sqlite3 as the database for Active Record
# https://github.com/sparklemotion/sqlite3-ruby/pull/402/files
gem "sqlite3", "~> 2", force_ruby_platform: true

# Ruby type hints
# https://sorbet.org/docs/adopting
gem "sorbet-runtime"

# gcp storage for get/put org icons, etc.
gem "google-cloud-storage"

# shorten invite urls
# https://github.com/jpmcgrath/shortener
gem "shortener"
# Develop? https://github.com/jpmcgrath/shortener/pull/165
# gem 'shortener', :git => "https://github.com/jpmcgrath/shortener.git", :branch => "develop"

# https://github.com/pushpad/web-push
# https://medium.com/@dejanvu.developer/implementing-web-push-notifications-in-a-ruby-on-rails-application-dcd829e02df0
gem "web-push"

# Logs in a single line
# https://github.com/roidrage/lograge
gem "lograge"

gem "stackprof"
gem "sentry-ruby"
gem "sentry-rails"
gem "newrelic_rpm"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[mri windows]

  gem "pry"

  # https://github.com/bkeepers/dotenv
  gem "dotenv"

  # https://github.com/rspec/rspec-rails
  # Run against this stable release
  gem "rspec-rails", "~> 7"

  # https://github.com/thoughtbot/factory_bot_rails
  gem "factory_bot_rails"

  # https://github.com/samuelgiles/rspec-sorbet
  # https://stackoverflow.com/questions/74842832/how-to-configure-sorbet-with-rspec
  gem "rspec-sorbet"

  # Generate types from gems
  # https://github.com/Shopify/tapioca
  gem "tapioca", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # https://github.com/ctran/annotate_models
  # https://stackoverflow.com/questions/1289557/how-do-you-discover-model-attributes-in-rails
  # Use annotaterb instead of annotate - https://github.com/drwl/annotaterb
  gem "annotaterb"

  # Ruby type hints
  # https://sorbet.org/docs/adopting
  gem "sorbet"

  # https://github.com/faker-ruby/faker
  gem "faker"

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  # gem "rack-mini-profiler"

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"

  # https://github.com/BetterErrors/better_errors
  gem "better_errors"
  gem "binding_of_caller"

  eval_gemfile "gemfiles/rubocop.gemfile"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"

  gem "rails-controller-testing"
end
