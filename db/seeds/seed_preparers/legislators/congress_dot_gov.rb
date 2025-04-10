# typed: true

require_relative "base"

module SeedPreparers
  module Legislators
    class CongressDotGov < Base
      extend T::Sig

      attr_reader :json

      sig { params(json: T::Hash[String, String], sway_locale: SwayLocale).void }
      def initialize(json, sway_locale)
        super

        @json = CongressDotGov.prepare(json)
      end

      def external_id
        @_external_id ||= json.fetch("bioguideId")
      end

      def active
        json.fetch("currentMember")
      end

      def title
        (json.fetch("terms").last&.fetch("chamber", nil) == "Senate") ? "Sen." : "Rep."
      end

      def party
        @_party ||= Legislator.to_party_char_from_name(json.fetch("partyHistory").first&.fetch("partyAbbreviation"))
      end

      def first_name
        json.fetch("first_name", json.fetch("firstName", nil))
      end

      def last_name
        json.fetch("last_name", json.fetch("lastName", nil))
      end

      def phone
        json.dig("addressInformation", "phoneNumber")
      end

      def link
        default_link = "https://api.congress.gov/v3/member/#{external_id}"
        json.fetch("officialWebsiteUrl", default_link) || default_link
      end

      def country
        @_country ||= RegionUtil.from_country_code_to_name(json.fetch("country", "United States"))
      end

      def region_code
        @_region_code ||= RegionUtil.from_region_name_to_region_code(json.fetch("state"))
      end

      def postal_code
        @_postal_code ||= json.dig("addressInformation", "zipCode") || "20004" # US Capitol
      end

      def photo_url
        @_photo_url ||= json.dig("depiction", "imageUrl")
      end

      def congress?
        true
      end

      class << self
        def prepare(json)
          api_key = ENV["CONGRESS_GOV_API_KEY"]
          if api_key.blank?
            raise "No Congress API Key Found. Cannot seed Legislator in #{Rails.env}."
          end

          bioguide_id = json.fetch("bioguideId", nil)
          if bioguide_id.blank?
            raise "No bioguide id in Legislator json. Cannot seed Legislator."
          end

          d = (json.fetch("district", nil).presence || "0").to_s
          query = {
            # We don't need to check active: true for congressional because all legislators in the data.json file,
            # at storage/seeds/data/congress-congress-united_states/legislators.json are active
            # active: true,
            external_id: bioguide_id,
            district: {
              name: SeedLegislator.district_name(
                RegionUtil.from_region_name_to_region_code(json.fetch("state")),
                d.remove_non_digits.to_i
              )
            },
            party: Legislator.to_party_char_from_name(json.fetch("partyName"))
          }

          existing = Legislator.joins(:district).find_by(query)

          # Skips line 114
          if existing.present?
            return nil
          end

          # T.unsafe - .get does not exist on Faraday
          response = T.unsafe(Faraday).get("https://api.congress.gov/v3/member/#{bioguide_id}?&api_key=#{api_key}")
          result = JSON.parse(response.body).fetch("member")

          if result.nil?
            raise "No legislator data from congress.gov member object - #{response.body}."
          end

          # Skipped by line 102
          if existing.present?
            Rails.logger.info("SKIP Seeding Congressional Legislator #{bioguide_id}. Already exists by external_id, district.name and party char.")
            existing.update(
              active: true,
              photo_url: existing.photo_url || result.dig("depiction", "imageUrl"),
              phone: existing.phone || result.dig("addressInformation", "phoneNumber"),
              link: existing.link || result.dig("officialWebsiteUrl")
            )
            nil
          else
            result
          end
        end
      end
    end
  end
end
