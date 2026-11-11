# frozen_string_literal: true

class SwayLocale
  # @lat: [[jurisdiction-rules#Jurisdiction declarations#Declared executives]]
  module OpenStatesExecutivesRegistry
    DECLARATIONS = {
      # @lat: [[jurisdiction-rules#Jurisdiction declarations#Declared executives]]
      "maryland-maryland-united_states" => [
        {
          "id" => "ocd-person/a6a4f3ad-59c0-471c-8fd3-ea06a8e21a87",
          "given_name" => "Wes",
          "family_name" => "Moore",
          "current_role" => {
            "title" => "Governor",
            "org_classification" => "executive",
            "district" => "0",
            "start_date" => nil
          },
          "jurisdiction" => {"name" => "Maryland"},
          "party" => "Democrat",
          # @lat: [[jurisdiction-rules#Jurisdiction declarations#Declared executives#A stored portrait address keeps no query string]]
          "image" => "https://cdn.maryland.gov/maryland-cms/prod/governor/s3fs-public/styles/3_4_504x672_focal_point_webp/public/images/2026-04/gov%201st%20size.png.webp",
          "openstates_url" => "https://openstates.org/person/wes-moore-54S6mt4X90CqkolXF3n287/"
        },
        {
          "id" => "ocd-person/27dd7c4f-0e25-4cd0-b849-6830e5ec7fa1",
          "given_name" => "Aruna",
          "family_name" => "Miller",
          "current_role" => {
            "title" => "Lt. Governor",
            "org_classification" => "executive",
            "district" => "0",
            "start_date" => nil
          },
          "jurisdiction" => {"name" => "Maryland"},
          "party" => "Democrat",
          "image" => "https://cdn.maryland.gov/maryland-cms/prod/governor/s3fs-public/styles/3_4_504x672_focal_point_webp/public/images/2026-04/lg%201st%20size.png.webp",
          "openstates_url" => "https://openstates.org/person/aruna-miller-1DDv2GtdwdJ0xq2uoyqARF/"
        },
        {
          "id" => "ocd-person/1ad81709-e1d6-42bd-86bc-afdec934288c",
          "given_name" => "Anthony",
          "family_name" => "Brown",
          "current_role" => {
            "title" => "Attorney General",
            "org_classification" => "executive",
            "district" => "0",
            "start_date" => nil
          },
          "jurisdiction" => {"name" => "Maryland"},
          "party" => "Democrat",
          "image" => "https://oag.maryland.gov/our-office/PublishingImages/AttorneyGeneral.jpg",
          "openstates_url" => "https://openstates.org/person/anthony-g-brown-oeYLD6sNWqEsi8LAUTlzI/"
        }
      ].freeze
    }.freeze

    class << self
      # @lat: [[jurisdiction-rules#Jurisdiction declarations#Declared executives]]
      def for(locale_name)
        DECLARATIONS.fetch(locale_name, [])
      end

      def declared?(locale_name)
        DECLARATIONS.key?(locale_name)
      end

      def declared_locale_names
        DECLARATIONS.keys
      end
    end
  end
end
