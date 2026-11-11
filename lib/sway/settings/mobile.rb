# frozen_string_literal: true

module Sway
  module Settings
    # @lat: [[settings-groups#Why some groups declare a blank env prefix]]
    class Mobile < Base
      config_name "mobile"
      env_prefix ""

      # @lat: [[settings-groups#Why the mobile group's id and version numbers are text]]
      attr_config apple_app_store_id: "<APPLE_APP_ID>"
      coerce_types apple_app_store_id: :string

      # @lat: [[settings-groups#Why the mobile group's id and version numbers are text]]
      attr_config mobile_min_version: "1.0.0"
      coerce_types mobile_min_version: :string

      attr_config mobile_latest_version: "1.0.0"
      coerce_types mobile_latest_version: :string

      attr_config android_cert_sha256_fingerprints: []
      coerce_types android_cert_sha256_fingerprints: {array: true, type: :string}

      attr_config apple_team_id: nil
      coerce_types apple_team_id: :string

      attr_config apple_bundle_id: nil
      coerce_types apple_bundle_id: :string

      # @lat: [[well-known-controller-notes#Why the served hosts are configuration]]
      attr_config app_association_hosts: []
      coerce_types app_association_hosts: {array: true, type: :string}

      required :apple_app_store_id, :mobile_min_version, :mobile_latest_version,
        :android_cert_sha256_fingerprints, :app_association_hosts

      # @lat: [[settings-groups#Why the fingerprint list is compacted on load]]
      on_load do
        self.android_cert_sha256_fingerprints = android_cert_sha256_fingerprints.compact
        self.app_association_hosts = app_association_hosts.compact
      end

      # @lat: [[settings-groups#Why the freeze runs after a group's own repair]]
      on_load { self.class.freeze_mutable_attributes!(self) }
    end
  end
end
