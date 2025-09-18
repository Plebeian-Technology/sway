class Organizations::MembershipsController < Organizations::BaseController
  before_action :current_user_must_be_organization_admin!,
                only: %i[update destroy]
  before_action :working_membership_must_be_same_organization_as_current_user!,
                only: %i[update destroy]

  def show
    render_component(
      Pages::USER_ORGANIZATION_MEMBERSHIP,
      membership: membership_as_props,
    )
  end

  def update
    if working_membership.update(
         role: UserOrganizationMembership.roles.fetch(params[:role]),
       )
      flash[:notice] = "Member updated."
    else
      Rails.logger.error(working_membership.errors.full_messages)
      flash[:alert] = "Could not update member."
    end
    redirect_to_current_user_membership
  end

  def destroy
    if working_membership.destroy
      flash[:notice] = "Member removed."
    else
      Rails.logger.error(working_membership.errors.full_messages)
      flash[:alert] = "Failed to remove member."
    end

    if working_membership.id == current_user_membership.id
      redirect_to users_organization_memberships_path
    else
      redirect_to_current_user_membership
    end
  end

  private

  def current_user_must_be_organization_admin!
    return if current_user_membership&.admin?

    flash[:alert] = "Forbidden"
    redirect_to_current_user_membership
  end

  def working_membership
    @working_membership ||= UserOrganizationMembership.find(params[:id])
  end

  def working_membership_must_be_same_organization_as_current_user!
    unless working_membership.organization_id ==
             current_user_membership.organization_id
      flash[:alert] = "Forbidden"
      redirect_to_current_user_membership
    end
  end
end
