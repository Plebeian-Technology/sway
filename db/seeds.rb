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

# # Create UserLegislators for new legislators
# locales.each do |locale|
#   Rails.logger.info("Seeding UserLegislators for Locale: #{locale.name}")

#   locale.legislators.each do |legislator|
#     # Find the legislators that were created for the latest election year
#     new_legislators = locale.legislators.select { |l| l.active }.select do |l|
#       l.district.name == legislator.district.name &&
#         l.title == legislator.title &&
#         l.election_year == l.district.sway_locale.latest_election_year
#     end

#     if new_legislators.blank?
#       Rails.logger.info("No new_legislators found for legislator.id = #{legislator.id}, district.name = #{legislator.district.name}, title = #{legislator.title}, election_year = #{legislator.election_year}. Cannot create new UserLegislator ")
#       next
#     end

#     # Get the user's current UserLegislators for the locale/legislator
#     new_legislators.each do |new_legislator|
#       UserLegislator.where(active: true, legislator:).each do |user_legislator|
#         next if UserLegislator.find_by(user: user_legislator.user, legislator: new_legislator).present?

#         ul = UserLegislator.new
#         ul.user = user_legislator.user
#         ul.legislator = new_legislator
#         ul.active = true

#         if ul.save
#           user_legislator.update_attribute(:active, false)
#         end
#       end
#     end
#   end
# end
