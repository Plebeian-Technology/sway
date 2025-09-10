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

if Rails.env.development?
    sway_locale = SwayLocale.find_by(city: "baltimore", state: "maryland")
    raise "No baltimore, maryland sway locale" if sway_locale.nil?

    phone = ENV.fetch("DEFAULT_PHONE").split("+1").join("")
    user =
        User.find_or_create_by(
            phone: phone,
            email: "#{phone}@sway.vote",
            full_name: ENV.fetch("DEFAULT_USER_FULL_NAME").split("+").join(" "),
        )
    user.update(
        phone: phone,
        is_admin: true,
        is_email_verified: true,
        is_phone_verified: true,
        is_registered_to_vote: true,
        is_registration_complete: true,
    )
    address =
        Address.find_or_create_by(
            city: ENV.fetch("DEFAULT_CITY"),
            postal_code: ENV.fetch("DEFAULT_REGION_CODE"),
            region_code: ENV.fetch("DEFAULT_POSTAL_CODE"),
            street: ENV.fetch("DEFAULT_STREET").split("+").join(" "),
            latitude: ENV.fetch("DEFAULT_LATITUDE").to_f,
            longitude: ENV.fetch("DEFAULT_LONGITUDE").to_f,
        )
    UserAddress.find_or_create_by(user: user, address: address)

    organization = Organization.find_or_create_by!(name: "Sway", sway_locale: sway_locale)
    organization.update!(icon_path: "/images/sway-us-light.png")

    UserOrganizationMembership.find_or_create_by!(user: user, organization: organization, role: :admin)

    sway_locale
        .bills
        .limit(5)
        .each_with_index do |bill, index|
            OrganizationBillPosition.find_or_create_by!(
                organization: organization,
                bill: bill,
                support: index.even? ? LegislatorVote::Support::FOR : LegislatorVote::Support::AGAINST,
                summary: "This is a sample position statement for #{bill.title}",
            )
        end

    User.all.each do |user|
        Organization.all.each do |organization|
            UserOrganizationMembership.find_or_create_by!(user: user, organization: organization, role: :admin)
        end
    end
end
