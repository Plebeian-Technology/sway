class Organizations::MembershipsController < Organizations::BaseController
  before_action :verify_own_non_removed_membership!, only: %i[show]
  before_action :verify_is_organization_admin!, only: %i[update]
  before_action :verify_admin_or_own_membership!, only: %i[destroy]
  before_action :working_membership_must_be_same_organization_as_current_user!,
    only: %i[update destroy]

  def show
    render_inertia_or_json(
      page: Pages::USER_ORGANIZATION_MEMBERSHIP,
      props: {
        membership: membership_as_props
      }
    )
  end

  # @lat: [[organizations-memberships-controller-notes#Why leave is separate from destroy]]
  def leave
    membership =
      current_user.user_organization_memberships.find_by(
        organization_id: params[:organization_id],
        status: :active
      )

    unless membership
      flash[:alert] = "You are not an active member of this organization."
      redirect_to users_organization_memberships_path, status: :see_other
      return
    end

    if membership.remove
      flash[:notice] = "You have left #{membership.organization.name}."
    else
      flash[:alert] =
        membership.errors[:base].first.presence ||
        "Failed to leave organization."
    end

    redirect_to users_organization_memberships_path, status: :see_other
  end

  def update
    # @lat: [[organizations-memberships-controller-notes#Why update checks the role before modifying records]]
    role = UserOrganizationMembership.roles[params[:role].to_s]
    if role.nil?
      flash[:alert] = "Invalid role."
      return redirect_to_current_user_membership
    end

    if working_membership.update(role: role)
      flash[:notice] = "Member updated."
    else
      SwayLogging.error("organization_membership.update_failed", errors: working_membership.errors.full_messages)
      flash[:alert] = "Could not update member."
    end
    redirect_to_current_user_membership
  end

  def destroy
    if working_membership.destroy
      flash[:notice] = "Member removed."
    else
      SwayLogging.error("organization_membership.destroy_failed", errors: working_membership.errors.full_messages)
      flash[:alert] = "Failed to remove member."
    end

    if mobile_api_request?
      return head :no_content if working_membership.destroyed?
      return render_error(code: "destroy_failed", message: flash[:alert] || "Failed to remove member.", status: :unprocessable_content)
    end

    membership = current_user_membership
    if membership && working_membership.id == membership.id
      redirect_to users_organization_memberships_path
    else
      redirect_to_current_user_membership
    end
  end

  private

  # @lat: [[organizations-base-controller-membership-guards#Why show requires the caller's own non-removed membership]]
  def verify_own_non_removed_membership!
    membership = current_user_membership
    if membership && (membership.active? || membership.pending?) && membership.id.to_s == params[:id].to_s
      return
    end

    if request.format.json?
      render_error(code: "forbidden", message: "Forbidden", status: :forbidden)
    else
      flash[:alert] = "Forbidden"
      redirect_to organization_path(organization)
    end
  end

  def verify_admin_or_own_membership!
    return if working_membership.user_id == current_user&.id

    verify_is_organization_admin!
  end

  def working_membership
    @working_membership ||= organization.user_organization_memberships.find(params[:id])
  end

  def working_membership_must_be_same_organization_as_current_user!
    membership = current_user_membership
    unless membership &&
        working_membership.organization_id == membership.organization_id
      flash[:alert] = "Forbidden"
      redirect_to_current_user_membership
    end
  end
end
