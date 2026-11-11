# frozen_string_literal: true

module Sway
  module Settings
    # @lat: [[settings-group-declaration-notes#Why some groups declare env_prefix ""]]
    class Ops < Base
      config_name "ops"
      env_prefix ""

      # @lat: [[inbound-sms#Inbound SMS#Forwarding goes to email, not SMS]]
      attr_config inbound_sms_forward_to: "sms@sway.vote"
      coerce_types inbound_sms_forward_to: :string
      required :inbound_sms_forward_to

      # @lat: [[seeded-development-users#Outbound SMS is refused outside production]]
      attr_config allow_nonproduction_sms: false
      coerce_types allow_nonproduction_sms: :boolean
      required :allow_nonproduction_sms

      # @lat: [[settings-group-declaration-notes#Why Ops.sway_deployed_at has no default]]
      attr_config sway_deployed_at: nil
      coerce_types sway_deployed_at: :string

      # @lat: [[settings-groups#Why the base class replaces the gem's casters]]
      attr_config sway_skip_db_backup: false
      coerce_types sway_skip_db_backup: :boolean
      required :sway_skip_db_backup

      # @lat: [[host-boot-guard-docker-storage#Why Rails refuses to boot on the host]]
      attr_config is_docker: false
      coerce_types is_docker: :boolean
      required :is_docker

      attr_config dev_tunnel_host: nil
      coerce_types dev_tunnel_host: :string

      attr_config beszel_url: nil
      coerce_types beszel_url: :string

      # @lat: [[admin-hub-index#Who sees the monitoring link]]
      attr_config beszel_admin_email_domains: []
      coerce_types beszel_admin_email_domains: {array: true, type: :string}
      required :beszel_admin_email_domains

      # @lat: [[settings-groups#Why the fingerprint list is compacted on load]]
      on_load { self.beszel_admin_email_domains = beszel_admin_email_domains.compact }

      # @lat: [[settings-groups#Why the freeze runs after a group's own repair]]
      on_load { self.class.freeze_mutable_attributes!(self) }
    end
  end
end
