# @lat: [[well-known-controller-notes#Why both hosts are authoritative]]

class WellKnownController < ApplicationController
  skip_before_action :authenticate_sway_user!

  class << self
    # @lat: [[well-known-controller-notes#Why the dev tunnel host is appended only in development]]
    def dev_tunnel_host
      return nil unless Rails.env.development?

      Sway::Settings.ops.dev_tunnel_host
    end

    # @lat: [[well-known-controller-notes#Why the served hosts are configuration]]
    def association_hosts
      [*Sway::Settings.mobile.app_association_hosts, dev_tunnel_host].compact.uniq
    end

    def webauthn_hosts
      [*Sway::Settings.webauthn.related_hosts, dev_tunnel_host].compact.uniq
    end

    # @lat: [[well-known-controller-notes#Why the related origins are the related hosts]]
    def related_origins
      webauthn_hosts.map { |host| "https://#{host}" }
    end

    # Returns the "<team id>.<bundle id>" pair Apple matches the app against,
    # or nil when either half is unset.
    def apple_app_id
      team_id = Sway::Settings.mobile.apple_team_id
      bundle_id = Sway::Settings.mobile.apple_bundle_id
      return nil if team_id.nil? || bundle_id.nil?

      "#{team_id}.#{bundle_id}"
    end
  end

  def index
    SwayLogging.info(
      "WellKnownController.index.request.host - #{request.host}"
    )
    if self.class.webauthn_hosts.include?(request.host)
      return (
        render json: {
          origins: self.class.related_origins
        }
      )
    end

    head :no_content
  end

  def aasa
    return head :no_content unless self.class.association_hosts.include?(request.host)

    app_id = self.class.apple_app_id
    return head :no_content if app_id.nil?

    response.headers["Cache-Control"] = "public, max-age=3600"
    render json: {
      webcredentials: {
        apps: [app_id]
      },
      applinks: {
        details: [
          {
            appID: app_id,
            # @lat: [[well-known-controller-notes#Why the AASA paths list is tested against the real route table]]
            paths: [
              "/bills/*",
              "/bills",
              "/past_bills_of_the_month",
              "/legislators/*",
              "/legislators",
              "/bill_of_the_week",
              "/bill_of_the_month",
              "/organizations/*/memberships/*",
              "/organizations/*",
              "/organizations",
              "/s/*",
              "/invite/*/*",
              "/invites/*/*",
              "/bill_shares/*",
              "/feed",
              "/users/organization_memberships",
              "/users/profile"
            ]
          }
        ]
      }
    }
  end

  def assetlinks
    return head :no_content unless self.class.association_hosts.include?(request.host)

    package_name = Sway::Settings.mobile.apple_bundle_id
    return head :no_content if package_name.nil?

    response.headers["Cache-Control"] = "public, max-age=3600"
    fingerprints = Sway::Settings.mobile.android_cert_sha256_fingerprints

    render json: [
      {
        relation: [
          "delegate_permission/common.get_login_creds",
          "delegate_permission/common.handle_all_urls"
        ],
        target: {
          namespace: "android_app",
          package_name: package_name,
          sha256_cert_fingerprints: fingerprints
        }
      }
    ]
  end
end
