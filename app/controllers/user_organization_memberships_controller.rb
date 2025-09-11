class UserOrganizationMembershipsController < ApplicationController
  before_action :set_current_user_membership, except: %i[index]

  inertia_share do
    u = current_user.to_sway_json

    {
      tab: params[:tab] || "positions",
      user: {
        **u,
        memberships:
          current_user.user_organization_memberships&.map(&:to_sway_json),
      },
    }
  end

  def index
    render_component(Pages::USER_ORGANIZATION_MEMBERSHIPS)
  end

  def show
    props = {
      **@current_user_membership.to_sway_json,
      organization: organization.to_simple_builder.attributes!,
      role: @current_user_membership.role,
      positions:
        positions.map do |p|
          {
            id: p.id,
            support: p.support,
            summary: p.summary,
            bill: p.bill.to_sway_json,
          }
        end,
    }

    if @current_user_membership.admin?
      props[:members] = members.map do |m|
        {
          id: m.id,
          user_id: m.user.id,
          full_name: m.user.full_name,
          email: m.user.email,
          role: m.role,
        }
      end
      props[:pending_changes] = pending_changes.map(&:to_sway_json)
    else
      props[:pending_changes] = pending_changes.where(
        updated_by: current_user,
      ).map(&:to_sway_json)
    end

    render_component(Pages::USER_ORGANIZATION_MEMBERSHIP, membership: props)
  end

  def update
    # Only allow admins of the organization to change roles
    unless @current_user_membership&.admin?
      flash[:alert] = "Forbidden"
      redirect_to user_organization_membership_path(
                    @current_user_membership,
                  ) and return
    end

    if working_membership.update(
         role: UserOrganizationMembership.roles.fetch(params[:role]),
       )
      flash[:notice] = "Member updated"
    else
      Rails.logger.error(working_membership.errors.full_messages)
      flash[:alert] = "Could not update member"
    end

    redirect_to user_organization_membership_path(@current_user_membership)
  end

  def destroy
    # Only allow admins of the organization to remove members
    if @current_user_membership&.admin?
      working_membership.destroy
      flash[:notice] = "Member removed"
    else
      flash[:alert] = "Forbidden"
    end

    if working_membership.id == @current_user_membership.id
      redirect_to user_organization_memberships_path
    else
      redirect_to user_organization_membership_path(@current_user_membership)
    end
  end

  private

  def pending_changes
    OrganizationBillPositionChange.includes(
      organization_bill_position: :organization,
    ).where(
      approved_by_id: nil, # NOTE: Commnet-out to show all changes, not just pending
      organization_bill_position: {
        organization: organization,
      },
    )
  end

  def organization
    @organization ||= @current_user_membership.organization
  end

  def members
    organization.user_organization_memberships.includes(:user)
  end

  def positions
    organization.positions.eager_load(:bill)
  end

  def working_membership
    @working_membership ||=
      UserOrganizationMembership.find(params[:working_membership_id])
  end

  def set_current_user_membership
    @current_user_membership =
      UserOrganizationMembership.includes(:organization).find(params[:id])
  end
end
