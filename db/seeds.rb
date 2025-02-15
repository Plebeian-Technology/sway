# typed: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

require_relative "seeds/models/sway_locale"
require_relative "seeds/models/legislator"
require_relative "seeds/models/bill"

Rails.logger.debug("\n########################################################################################\n")

# if Rails.env.development? && File.exist?("storage/seeds/data/development.sql")
#   Rails.logger.debug("\nseeds.rb -> Seeding from SQL file located at: storage/seeds/data/development.sql\n")
#   Rails.logger.debug("\n########################################################################################\n")

#   `sqlite3 storage/development.sqlite3 < storage/seeds/data/development.sql`
# else
Rails.logger.debug("\nseeds.rb -> Seeding SwayLocales and from SeedLegislator and SeedBill\n")
Rails.logger.debug("\n########################################################################################\n")
locales = SeedSwayLocale.run

SeedLegislator.run(locales)

SeedBill.run(locales)
# end
