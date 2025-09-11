class Organizations::BaseController < ApplicationController
  inertia_share do
    {
      tab: params[:tab] || "positions",
      new_position_id: params[:new_position_id],
    }
  end

  def with_props
    { organization: organization.to_simple_builder.attributes! }
  end

  def organization
    @organization ||= Organization.find(params[:organization_id])
  end

  def members
    @members ||= organization.user_organization_memberships.includes(:user)
  end

  def positions
    @positions ||= organization.positions.eager_load(:bill)
  end

  def pending_changes
    @pending_changes ||= OrganizationBillPositionChange.pending(organization)
  end

  def current_user_membership
    @current_user_membership ||=
      UserOrganizationMembership.find_by(
        organization: organization,
        user: current_user,
      )
  end

  def redirect_to_current_user_membership(**kwargs)
    redirect_to organization_membership_path(
                  organization_id: organization.id,
                  id: current_user_membership.id,
                  tab: params[:tab],
                  **kwargs,
                )
  end

  def membership_as_props
    props = {
      **current_user_membership.to_sway_json,
      organization: organization.to_simple_builder.attributes!,
      role: current_user_membership.role,
      positions:
        (
          positions.map do |p|
            {
              id: p.id,
              support: p.support,
              summary: p.summary,
              bill: p.bill.to_sway_json,
            }
          end
        ),
    }

    if current_user_membership.admin?
      props[:members] = (
        members.map do |m|
          {
            id: m.id,
            user_id: m.user.id,
            full_name: m.user.full_name,
            email: m.user.email,
            role: m.role,
          }
        end
      )
      props[:pending_changes] = pending_changes.map(&:to_sway_json)
    else
      props[:pending_changes] = pending_changes.where(
        updated_by: current_user,
      ).map(&:to_sway_json)
    end
    props
  end
end
