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

locales = SeedSwayLocale.run

SeedLegislator.run(locales)

SeedBill.run(locales)

# Create UserLegislators for new legislators
# locales.each do |locale|
#   # TODO: Fix US Senators
#   next if locale.congress?

#   Legislator.joins(:district).where(district: {sway_locale: locale}).each do |legislator|

#     # Find the legislators that were just created
#     new_legislator = locale.legislators.select { |l| l.active }.find do |l|
#       l.district.name == legislator.district.name && l.first_name == legislator.first_name && l.last_name == legislator.last_name
#     end

#     UserLegislator.where(active: true, legislator:).each do |user_legislator|
#       ul = UserLegislator.new
#       ul.user = user_legislator.user
#       ul.legislator = new_legislator
#       ul.active = true
#       ul.save!

#       user_legislator.active = false
#       user_legislator.save!
#     end
#   end
# end
