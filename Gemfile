# frozen_string_literal: true

source "https://rubygems.org"

ruby ">= 4.0.9", "< 4.1.0"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
# gem "rails", "~> 8"
gem "rails", "~> 8"

gem "state_machines-activerecord"

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma"

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

# @lat: [[auxiliary-databases#Why Action Cable runs on Solid Cable, not Redis]]
gem "solid_cable"

# @lat: [[auxiliary-databases#The Solid Cache database replaces two different broken caches]]
gem "solid_cache"

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

# https://github.com/skryukov/rails_vite
gem "rails_vite"

# https://github.com/inertiajs/inertia-rails?tab=readme-ov-file
gem "inertia_rails"

# @lat: [[system-shape#One process, two languages#Why a payload goes through a resource rather than the record]]
gem "alba"
gem "alba-inertia"

# https://github.com/lostisland/faraday
# https://medium.com/@zozulyak.nick/ruby-class-pattern-to-work-with-api-requests-with-built-in-async-approach-bf0713a7dc96
gem "concurrent-ruby"

# https://github.com/lostisland/faraday
gem "down"
gem "rubyzip", "~> 3.6", require: "zip"
gem "faraday"
# https://github.com/lostisland/faraday-retry — bounded retry middleware for
# Sway::FaradayStack (Phase 52 D-36): Legistar + llama.cpp connections.
gem "faraday-retry"

# https://github.com/mauricio/faraday_curl
# gem 'faraday_curl'

# https://github.com/cedarcode/webauthn-ruby
gem "webauthn"

# phone/sms verification
# https://www.twilio.com/docs/verify/sms
gem "twilio-ruby"

# https://www.twilio.com/docs/sendgrid/for-developers/sending-email/quickstart-ruby
# https://github.com/sendgrid/sendgrid-ruby
# gem "sendgrid-ruby"

# Use resend for email
# https://rubygems.org/gems/resend
# https://resend.com
gem "resend", ">= 1.14"

# Use sqlite3 as the database for Active Record
# https://github.com/sparklemotion/sqlite3-ruby/pull/402/files
gem "sqlite3", force_ruby_platform: true

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

# Parse fetched xml data for US Congress votes
gem "rexml"

gem "stackprof"

gem "solid_queue"

gem "googleauth"
# apnotic: APNs HTTP/2 dispatch for iOS push notifications.
gem "apnotic"

# https://github.com/yob/pdf-reader
# read vote tally PDFs from MD state legislator
gem "pdf-reader"

gem "ruby-progressbar"

# Phase 52 D-16: shared JSON Schema (Draft 2020-12) validator for bill summary
# payloads (paste_summary + llama.cpp). Single BILL_SUMMARY_SCHEMA constant.
gem "json_schemer"

# Phase 52: OpenAI-compatible HTTP client targeting llama.cpp /v1/chat/completions.
# llama.cpp speaks OpenAI's API surface, so ruby-openai works as the client lib.
gem "ruby-openai"

# Phase 54 SPEC R2 (54-RESEARCH §1, §2): official Anthropic-owned Ruby SDK
# (anthropics/anthropic-sdk-ruby on GitHub). NOT the pre-handoff community
# gem ruby-anthropic; NOT the pre-handoff `anthropic` <= 0.4.x community
# release. Used by Llm::ClaudeAdapter for production bill summaries.
# Pinned to ~> 1.43 so resolution stays on the post-handoff Anthropic-owned
# major version (1.x) — resolving to 0.4.x is a P0 lockfile bug.
gem "anthropic"

# Phase 52: was transitive (rspec-expectations dep); promote to direct so the
# Phase 52 diff helpers can `require "diff/lcs"` without a contract surprise.
gem "diff-lcs", "~> 1.6"

# https://github.com/rswag/rswag — D-31: serves swagger/v1/swagger.yaml
# at /api-docs in non-production environments. Generation lives under
# rswag-specs (development/test only).
gem "rswag-api", "~> 2.17"

# With data-migrate you can generate your migrations for data as you would schema in your regular work flow.
#
# For setting tasks that don't require any intermediate AR activity, like dev and test, you stick with db:migrate. For production and QA, you change their scripts to db:migrate:with_data. Of course you want to test your migration, so you have the choice of db:migrate:with_data or data:migrate to just capture that data change.
#
# Data migrations are stored in db/data. They act like schema migrations, except they should be reserved for data migrations. For instance, if you realize you need to titleize all yours titles, this is the place to do it. Running any of the provided rake tasks also creates a data schema table to mirror the usual schema migrations table to track all migrations.
# https://github.com/ilyakatz/data-migrate
gem "data_migrate", "~> 11.3"

# Phase 59 D-04: GitHub REST API client for opening combined PRs from
# RefreshLegislatorsCacheJob. Octokit is the canonical GitHub-org SDK
# (github.com/octokit/octokit.rb, 14+ years, npm-equivalent for Ruby).
# Provenance verified: octokit org on GitHub, rubygems.org millions of downloads.
# Already used via bundler/inline in .kamal/hooks/pre-deploy.sample.
gem "octokit", "~> 10.0"

# Phase 68 D-24: the third settings door, replacing scattered ENV reads with
# one declared class per group. Version 2.8.1 installed and run against
# Ruby 4.0.9, this project's version, before the decision. MIT licence, one
# runtime dependency (ruby-next-core), 33,854,084 downloads on rubygems.org,
# confirmed 2026-08-16. Source: github.com/palkan/anyway_config. Ungrouped
# because the running application reads settings in every environment.
gem "anyway_config", "~> 2.8"

group :production do
  # https://github.com/modosc/cloudflare-rails
  # To determine ip addresses in order to rate limit correctly
  gem "cloudflare-rails"
  gem "newrelic_rpm"
end

# @lat: [[error-reporting-in-tests#Why the reporting gems are not production-only]]
gem "sentry-rails"
gem "sentry-ruby"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[mri windows]

  gem "pry"

  # https://github.com/bkeepers/dotenv
  gem "dotenv"

  # https://github.com/rspec/rspec-rails
  # Run against this stable release
  gem "rspec-rails", "~> 8"

  # https://github.com/thoughtbot/factory_bot_rails
  gem "factory_bot_rails"

  # https://github.com/bblimke/webmock
  # HTTP request stubbing for LegislationClient specs
  gem "webmock"

  # https://github.com/vcr/vcr
  # Record-and-replay HTTP cassettes for service specs that hit real HTTP boundaries
  # (legislation-service FastAPI, Legistar API). See spec/support/vcr.rb for config.
  gem "vcr"

  # https://github.com/rswag/rswag — D-31: OpenAPI generation from request specs.
  # Sanctioned exception to prefer-builtin-rails-over-gems memory rule
  # (Rails 8.1 has no built-in OpenAPI generator). See plan 32-03 NOTE.
  gem "rswag-specs"

  # https://github.com/faker-ruby/faker
  gem "faker"

  # https://github.com/grosser/parallel_tests — Phase 64: shards rspec into
  # per-lane worker groups. 5.x changelog read: only breaking change is 5.0.0
  # dropping Ruby 3.0/3.1 (this project is on 4.0.9), and 5.7.0 stopped
  # parallel:prepare dumping the schema, which sway:test:prepare_shards
  # (lib/tasks/sway_test_shards.rake) never called anyway.
  gem "parallel_tests", "~> 5.7"

  # Rubocop
  gem "standard", ">= 1.54"
  gem "rubocop"
  gem "rubocop-shopify"
  gem "rubocop-thread_safety"
  gem "standard-rails"
  gem "rubocop-performance"
  gem "rubocop-rails"
  gem "rubocop-rspec"
  gem "rubocop-capybara"
  gem "rubocop-factory_bot"
  gem "rubydex", require: false # https://metaredux.com/posts/2026/08/05/rubocop-1-89.html
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # https://github.com/ctran/annotate_models
  # https://stackoverflow.com/questions/1289557/how-do-you-discover-model-attributes-in-rails
  # Use annotaterb instead of annotate - https://github.com/drwl/annotaterb
  gem "annotaterb"

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  # gem "rack-mini-profiler"

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"

  gem "prettier_print"
  gem "rbs", require: false
  gem "rbs_rails", require: false
  gem "steep", require: false
  gem "syntax_tree"
  gem "syntax_tree-haml"
  gem "syntax_tree-rbs"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  # Gated in CI by .github/workflows/brakeman.yml.
  gem "brakeman", require: false
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"

  gem "simplecov", require: false, group: :test
end
