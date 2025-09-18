module Users
  class OrganizationMembershipsController < ApplicationController
    def index
      u = current_user.to_sway_json

      render_component(
        Pages::USER_ORGANIZATION_MEMBERSHIPS,
        {
          tab: params[:tab] || "positions",
          user: {
            **u,
            memberships:
              current_user.user_organization_memberships&.map(&:to_sway_json),
          },
        },
      )
    end
  end
end
