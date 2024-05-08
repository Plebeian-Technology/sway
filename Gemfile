# frozen_string_literal: true

source 'https://rubygems.org'

ruby '3.3.0'

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem 'rails', '~> 7.1.3', '>= 7.1.3.2'

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem 'sprockets-rails'

# Use the Puma web server [https://github.com/puma/puma]
gem 'puma', '>= 5.0'

# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
# gem "tailwindcss-rails"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# Camel Case json keys
# https://stackoverflow.com/questions/23794276/rails-render-json-object-with-camelcase
gem 'jbuilder'

# Use Redis adapter to run Action Cable in production
gem 'redis', '>= 4.0.1'

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: %i[windows jruby]

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', require: false

# https://github.com/alexreisner/geocoder?tab=readme-ov-file#testing
gem 'geocoder'

# https://rgeo.info/
# https://github.com/rgeo/rgeo
gem 'rgeo'

# https://github.com/rgeo/rgeo-geojson
gem 'rgeo-geojson'

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

gem 'dartsass-rails', '~> 0.5.0'
gem 'sassc-rails'

gem 'bootstrap', '~> 5.3.2'

# https://github.com/BrandonShar/inertia-rails-template/blob/main/Gemfile
gem 'vite_rails'

# https://github.com/inertiajs/inertia-rails?tab=readme-ov-file
gem 'inertia_rails'

gem 'httparty'

# https://github.com/cedarcode/webauthn-ruby
gem 'webauthn'

# phone/sms verification
# https://www.twilio.com/docs/verify/sms
gem 'twilio-ruby'

# group :production do
#   gem 'pg', '~> 1.5', '>= 1.5.6'
# end

# Use sqlite3 as the database for Active Record
gem 'sqlite3', '~> 1.4'

# Ruby type hints
# https://sorbet.org/docs/adopting
gem 'sorbet-runtime'

group :development, :test do

    # Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
  gem 'importmap-rails'

  # Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
  gem 'turbo-rails'

  # Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
  gem 'stimulus-rails'

  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem 'debug', platforms: %i[mri windows]

  gem 'pry'

  gem 'better_errors'

  # https://github.com/rspec/rspec-rails
  # Run against this stable release
  gem 'rspec-rails', '~> 6'

  # https://github.com/thoughtbot/factory_bot_rails
  gem 'factory_bot_rails'

  # https://github.com/samuelgiles/rspec-sorbet
  # https://stackoverflow.com/questions/74842832/how-to-configure-sorbet-with-rspec
  gem 'rspec-sorbet'

  # Generate types from gems
  # https://github.com/Shopify/tapioca
  gem 'tapioca', require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem 'web-console'

  # https://github.com/kirillplatonov/hotwire-livereload
  # https://dev.to/thomasvanholder/how-to-set-up-rails-hotwire-live-reload-38i9
  gem 'hotwire-livereload', '~> 1.3'

  # https://github.com/ctran/annotate_models
  # https://stackoverflow.com/questions/1289557/how-do-you-discover-model-attributes-in-rails
  gem 'annotate'

  # https://github.com/bkeepers/dotenv
  gem 'dotenv', groups: %i[development test]

  gem 'rubocop'

  # Ruby type hints
  # https://sorbet.org/docs/adopting
  gem 'sorbet'

  # https://github.com/faker-ruby/faker
  gem 'faker'

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  # gem "rack-mini-profiler"

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem 'capybara'
  gem 'selenium-webdriver'

  gem 'rails-controller-testing'
end
