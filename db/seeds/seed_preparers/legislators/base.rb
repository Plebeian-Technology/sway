# typed: true

require_relative "../../seed_errors"

module SeedPreparers
    module Legislators
        class Base
            extend T::Sig

            attr_reader :json, :sway_locale, :is_internet_connected

            sig { params(json: T::Hash[String, String], sway_locale: SwayLocale, is_internet_connected: T::Boolean).void }
            def initialize(json, sway_locale, is_internet_connected)
                @sway_locale = sway_locale
                @json = json
                @is_internet_connected = is_internet_connected
            end

            sig { returns(District) }
            def district
                if region_code.blank?
                    raise SeedErrors::MissingRegionCode,
                                "No region_code attribute found in legislator json. Sway locale - #{sway_locale.name}, Legislator - #{external_id}"
                end

                # Used in sway_registration_service.district_legislators
                unless RegionUtil::STATE_CODES_NAMES.key?(region_code.to_sym)
                    raise SeedErrors::NonStateRegionCode,
                                "region_code must be a US state (until Sway goes international :) - Received #{region_code}"
                end

                d = (json.fetch("district", nil).presence || "0").to_s
                name = SeedLegislator.district_name(region_code, d.remove_non_digits.to_i)

                District.find_or_create_by!(name:, sway_locale:)
            end

            def phone
                json.fetch("phone", nil)
            end

            def email
                json.fetch("email", nil)
            end

            def twitter
                json.fetch("twitter", nil)
            end

            def link
                json.fetch("link", nil)
            end

            ##################################################
            #
            # Overrides
            #
            ##################################################

            def external_id
                raise NotImplementedError
            end

            def active
                raise NotImplementedError
            end

            def title
                raise NotImplementedError
            end

            def party
                raise NotImplementedError
            end

            def first_name
                raise NotImplementedError
            end

            def last_name
                raise NotImplementedError
            end

            def country
                "United States"
            end

            def region_code
                raise NotImplementedError
            end

            def postal_code
                raise NotImplementedError
            end

            def photo_url
                raise NotImplementedError
            end

            def congress?
                false
            end
        end
    end
end
