# frozen_string_literal: true

# @lat: [[representative-resolution#Checking that seeded locales can register]]
namespace :sway do
  namespace :locales do
    desc "Register each locale's sample address in a rolled-back transaction and fail on any error or skipped term"
    task verify_registration: :environment do
      declared_names = SwayLocale::JurisdictionRulesRegistry.declared_locale_names
      failed_names = [] #: Array[String]
      reached_names = [] #: Array[String]

      ActiveRecord::Base.transaction(requires_new: true) do
        sample_locales = declared_names.filter_map do |name|
          sway_locale = SwayLocale.resolve_by_computed_name(name)
          sway_locale if sway_locale && DevelopmentAccountAddressService::SAMPLE_ADDRESS_COLUMNS.all? { |column| sway_locale.public_send(column).present? }
        end

        sample_locales.each_with_index do |sample_locale, index|
          user = User.create!(phone: format("%010d", 333_999_0000 + index))
          address = DevelopmentAccountAddressService.resolve(sway_locale: sample_locale)
          UserAddress.create!(user:, address:)

          address.sway_locales.each do |sway_locale|
            reached_names << sway_locale.name
            service = SwayRegistrationService.new(user, address, sway_locale, invited_by_id: nil, async: false)
            representatives = ActiveRecord::Base.transaction(requires_new: true) { service.call }
            errors = service.skipped_resolution_errors
            errors.each do |error|
              SwayLogging.log_exception("sway_locales.verify_registration_failed", exception: error, sway_locale: sway_locale.name)
            end
            failed_names << sway_locale.name if errors.any?
            puts "#{sample_locale.name} sample -> #{sway_locale.name}: #{representatives.size} representatives, #{errors.size} skipped"
          rescue => e
            SwayLogging.log_exception("sway_locales.verify_registration_failed", exception: e, sway_locale: sway_locale.name)
            failed_names << sway_locale.name
            puts "#{sample_locale.name} sample -> #{sway_locale.name}: raised #{e.class}"
          end
        end

        raise ActiveRecord::Rollback
      end

      unreached_names = declared_names - reached_names
      if unreached_names.any?
        SwayLogging.error("sway_locales.verify_registration_unreached", sway_locales: unreached_names)
      end

      problems = []
      problems << "failed: #{failed_names.uniq.join(", ")}" if failed_names.any?
      problems << "reached by no sample address: #{unreached_names.join(", ")}" if unreached_names.any?
      abort "Locale registration check #{problems.join("; ")}" if problems.any?
    end
  end
end
