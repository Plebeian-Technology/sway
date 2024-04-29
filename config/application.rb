# typed: true

require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module SwayRails
  extend T::Sig

  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = 'UTC'
    # config.eager_load_paths << Rails.root.join("extras")

    config.force_ssl = true
  end

  STATE_NAMES_CODES = {
    Alabama: 'AL',
    Alaska: 'AK',
    "American Samoa": 'AS',
    Arizona: 'AZ',
    Arkansas: 'AR',
    California: 'CA',
    Colorado: 'CO',
    Connecticut: 'CT',
    Delaware: 'DE',
    "District Of Columbia": 'DC',
    "Federated States Of Micronesia": 'FM',
    Florida: 'FL',
    Georgia: 'GA',
    Guam: 'GU',
    Hawaii: 'HI',
    Idaho: 'ID',
    Illinois: 'IL',
    Indiana: 'IN',
    Iowa: 'IA',
    Kansas: 'KS',
    Kentucky: 'KY',
    Louisiana: 'LA',
    Maine: 'ME',
    "Marshall Islands": 'MH',
    Maryland: 'MD',
    Massachusetts: 'MA',
    Michigan: 'MI',
    Minnesota: 'MN',
    Mississippi: 'MS',
    Missouri: 'MO',
    Montana: 'MT',
    Nebraska: 'NE',
    Nevada: 'NV',
    "New Hampshire": 'NH',
    "New Jersey": 'NJ',
    "New Mexico": 'NM',
    "New York": 'NY',
    "North Carolina": 'NC',
    "North Dakota": 'ND',
    "Northern Mariana Islands": 'MP',
    Ohio: 'OH',
    Oklahoma: 'OK',
    Oregon: 'OR',
    Palau: 'PW',
    Pennsylvania: 'PA',
    "Puerto Rico": 'PR',
    "Rhode Island": 'RI',
    "South Carolina": 'SC',
    "South Dakota": 'SD',
    Tennessee: 'TN',
    Texas: 'TX',
    Utah: 'UT',
    Vermont: 'VT',
    "Virgin Islands": 'VI',
    Virginia: 'VA',
    Washington: 'WA',
    "West Virginia": 'WV',
    Wisconsin: 'WI',
    Wyoming: 'WY'
  }
end
