# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

require_relative "seeds/seed_log"
require_relative "seeds/models/sway_locale"
require_relative "seeds/models/sway_organization"
require_relative "seeds/models/seed_llm_bill_summarization_instruction"
require_relative "seeds/models/legislator"
require_relative "seeds/models/seed_category"
require_relative "../app/services/development_account_address_service"
# SeedBill is intentionally NOT required here. Bill seeding runs the
# legislation pipeline (network-heavy) and is opt-in via the rake task
# `bin/rails sway:seed_bills` — run it after db:seed when you want bills.

Rails.logger.debug(
  "\n########################################################################################\n"
)

Rails.logger.debug(
  "\nseeds.rb -> Seeding SwayLocales and from SeedLegislator and SeedBill\n"
)
Rails.logger.debug(
  "\n########################################################################################\n"
)
# @lat: [[boot-failure-reporting]]
BootStep.run("db:seed") do
  SeedLog.say("Seeding SwayLocales + Legislators (db:seed)…")
  locales = SeedSwayLocale.run
  SeedLog.say("✓ #{locales.size} SwayLocales")

  SeedLlmBillSummarizationInstruction.run(locales)
  SeedLog.say("✓ LLM bill summarization instructions in #{locales.size} SwayLocales")

  SeedSwayOrganization.run(locales)
  SeedLog.say("✓ Sway organization in #{locales.size} SwayLocales")

  SeedLegislator.run(locales)

  # Seed the 20 categories. This runs in every environment, not just
  # development, because production needs the category taxonomy too.
  SeedCategory.call
  SeedLog.say("✓ #{Category.where(active: true).count} categories")

  SeedLog.say(
    "✓ db:seed complete (locales + legislators + categories). Bills are NOT seeded here — " \
    "run `bin/rails db:seed:bills` (network-heavy legislation pipeline)."
  )
end

if Rails.env.development?
  sway_locale = SwayLocale.find_by(city: "baltimore", state: "maryland")
  raise "No baltimore, maryland sway locale" if sway_locale.nil?

  phone = ENV.fetch("DEFAULT_PHONE").split("+1").join("")
  user = User.find_or_initialize_by(phone: phone)
  user.assign_attributes(
    email: "#{phone}@sway.vote",
    full_name: Sway::Settings.dev_login.dev_account_full_name.tr("+", " ")
  )
  User.transaction do
    user.save!
    user.update!(
      is_email_verified: true,
      is_phone_verified: true,
      is_registered_to_vote: true
    )
    address = DevelopmentAccountAddressService.resolve(sway_locale:)
    # @lat: [[identity-and-access#A user holds one address]]
    UserAddress.find_or_initialize_by(user:).update!(address:)

    SwayRegistrationService.new(user, address, sway_locale, invited_by_id: nil).call
    active_pairings = user.user_legislators.where(active: true).joins(legislator: :district)
      .where(districts: {sway_locale_id: sway_locale.id})
      .includes(:legislator)
      .to_a
    has_mayor = active_pairings.any? do |pairing|
      pairing.legislator.active_term&.title == "Mayor"
    end
    unless user.registered? && active_pairings.any? && has_mayor
      raise "Development admin registration produced no active Baltimore pairing including the Mayor"
    end
  end

  organization = Organization.find_by!(name: SeedSwayOrganization::NAME, sway_locale: sway_locale)

  sway_membership = UserOrganizationMembership.find_or_create_by!(
    user: user,
    organization: organization,
    role: :admin
  )
  sway_membership.activate! if sway_membership.pending?

  sway_locale
    .bills
    .limit(5)
    .each_with_index do |bill, index|
      OrganizationBillPosition.find_or_create_by!(
        organization: organization,
        bill: bill,
        support:
          (
            if index.even?
              LegislatorVote::Support::FOR
            else
              LegislatorVote::Support::AGAINST
            end
          ),
        summary: "This is a sample position statement for #{bill.title}"
      ) { |position| position.source_kind = OrganizationBillPosition::SourceKind::ORGANIZATION }
    end

  User.all.each do |user|
    Organization.all.each do |organization|
      m = UserOrganizationMembership.find_or_create_by!(
        user: user,
        organization: organization,
        role: :admin
      )
      m.activate! if m.pending?
    end
  end
end
