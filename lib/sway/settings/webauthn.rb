# frozen_string_literal: true

module Sway
  module Settings
    # @lat: [[settings-groups#Why the webauthn group binds one shared prefix]]
    class Webauthn < Base
      config_name "webauthn"
      env_prefix "WEBAUTHN"

      attr_config allowed_origins: []
      coerce_types allowed_origins: {array: true, type: :string}
      required :allowed_origins

      # @lat: [[settings-groups#Why the fingerprint list is compacted on load]]
      on_load do
        self.allowed_origins = allowed_origins.compact
        self.related_hosts = related_hosts.compact
      end

      # @lat: [[well-known-controller-notes#Why the served hosts are configuration]]
      attr_config related_hosts: []
      coerce_types related_hosts: {array: true, type: :string}
      required :related_hosts

      # @lat: [[settings-groups#Why rp id has no default]]
      attr_config rp_id: nil
      coerce_types rp_id: :string

      # @lat: [[settings-groups#Why the freeze runs after a group's own repair]]
      on_load { self.class.freeze_mutable_attributes!(self) }
    end
  end
end
