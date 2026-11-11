module Users
  class OrganizationMembershipsController < ApplicationController
    def index
      # @lat: [[public-organizations-endpoint#The public organizations endpoint#Why the list preloads icons and the detail does not]]
      memberships = current_user.user_organization_memberships
        .includes(organization: {icon_attachment: :blob})
        .to_a

      memberships_json = memberships.select { |m| m.status == "active" }.map(&:to_sway_json)

      pending_memberships_json = memberships.select { |m| m.status == "pending" }.map(&:to_sway_json)

      render_inertia_or_json(
        page: Pages::USER_ORGANIZATION_MEMBERSHIPS,
        props: {
          tab: organization_tab_param || "positions",
          user: {
            **current_user.to_sway_json.symbolize_keys,
            memberships: memberships_json
          },
          # @lat: [[surfaces#Dual-rendered JSON]]
          memberships: memberships_json,
          pending_memberships: pending_memberships_json
        }
      )
    end

    private

    def organization_tab_param
      # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
      return params[:org_tab].presence if params.key?(:org_tab)
      return params[:tab].presence if params.key?(:tab)

      params[:tab_key].presence
    end
  end
end
