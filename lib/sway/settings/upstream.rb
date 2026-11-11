# frozen_string_literal: true

module Sway
  module Settings
    # @lat: [[settings-group-declaration-notes#Why the class is named Upstream, not UpstreamConfig]]
    class Upstream < Base
      config_name "upstream"
      env_prefix ""

      attr_config legistar_api_base_url: "https://webapi.legistar.com/v1"
      coerce_types legistar_api_base_url: :string
      required :legistar_api_base_url

      attr_config law_xml_github_base_url: "https://github.com"
      coerce_types law_xml_github_base_url: :string
      required :law_xml_github_base_url

      attr_config openstates_api_base_url: "https://v3.openstates.org"
      coerce_types openstates_api_base_url: :string
      required :openstates_api_base_url

      attr_config congress_gov_api_base_url: "https://api.congress.gov/v3"
      coerce_types congress_gov_api_base_url: :string
      required :congress_gov_api_base_url

      # @lat: [[settings-group-declaration-notes#Why the Congress Legislators base URL keeps its trailing slash]]
      attr_config congress_legislators_base_url:
        "https://unitedstates.github.io/congress-legislators/"
      coerce_types congress_legislators_base_url: :string
      required :congress_legislators_base_url

      attr_config nominatim_api_base_url: "https://nominatim.openstreetmap.org"
      coerce_types nominatim_api_base_url: :string
      required :nominatim_api_base_url

      attr_config open_legislator_base_url: "http://localhost:3000/api/v1"
      coerce_types open_legislator_base_url: :string
      required :open_legislator_base_url

      attr_config brave_search_api_base_url: "https://api.search.brave.com"
      coerce_types brave_search_api_base_url: :string
      required :brave_search_api_base_url

      # @lat: [[settings-groups#Why the freeze runs after a group's own repair]]
      on_load { self.class.freeze_mutable_attributes!(self) }
    end
  end
end
