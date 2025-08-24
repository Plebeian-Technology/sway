# typed: true

require_relative "base"

module SeedPreparers
  module Legislators
    class CongressDotGov < Base
      extend T::Sig

      attr_reader :json

      sig { params(json: T::Hash[String, String], sway_locale: SwayLocale, is_internet_connected: T::Boolean).void }
      def initialize(json, sway_locale, is_internet_connected)
        super

        @json = CongressDotGov.prepare(json, is_internet_connected)
      end

      def external_id
        @_external_id ||= json.fetch("bioguideId")
      end

      def active
        json.fetch("currentMember", true)
      end

      def title
        if potus?
          "Pres."
        else
          (json.fetch("terms").last&.fetch("chamber", nil) == "Senate") ? "Sen." : "Rep."
        end
      end

      def party
        return @_party if @_party.present?

        par = json.fetch("partyName", json.dig("partyHistory", 0, "partyAbbreviation"))
        if par.blank?
          par = (json.dig("terms", "item").last&.fetch("chamber", nil) == "Senate") ? "Sen." : "Rep."
        end

        @_party ||= Legislator.to_party_char_from_name(par)
      end

      def first_name
        json.fetch("first_name", json.fetch("firstName", json.fetch("name", "").split(",").last&.strip))
      end

      def last_name
        json.fetch("last_name", json.fetch("lastName", json.fetch("name", "").split(",").first&.strip))
      end

      def phone
        json.dig("addressInformation", "phoneNumber")
      end

      def link
        default_link = "https://api.congress.gov/v3/member/#{external_id}"
        json.fetch("url", json.fetch("officialWebsiteUrl", default_link)) || default_link
      end

      def country
        @_country ||= RegionUtil.from_country_code_to_name(json.fetch("country", "United States"))
      end

      def region_code
        @_region_code ||= potus? ? json.fetch("state") : RegionUtil.from_region_name_to_region_code(json.fetch("state"))
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

      def potus?
        external_id == "POTUS" # set by Sway
      end

      class << self
        def prepare(json, is_internet_connected)
          return json if !is_internet_connected

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

          if bioguide_id == "POTUS"
            return json
          end

          # T.unsafe - .get does not exist on Faraday
          begin
            response = T.unsafe(Faraday).get("https://api.congress.gov/v3/member/#{bioguide_id}?&api_key=#{api_key}", timeout: 1)
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
              result.deep_stringify_keys
            end
          rescue Faraday::ConnectionFailed
            Rails.logger.warn("No connection, skip getting legislator data from congress.gov")
            nil
          end
        end
      end
    end
  end
end
