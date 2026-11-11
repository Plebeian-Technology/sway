class Organizations::BaseController < ApplicationController
  inertia_share do
    # @type self: Organizations::BaseController
    {
      tab: send(:organization_tab_param) || "positions",
      new_position_id: params[:new_position_id]
    }
  end

  def organization
    @organization ||= Organization.with_attached_icon.find(params[:organization_id])
  end

  def members
    @members ||= organization.user_organization_memberships.includes(:user)
  end

  def positions
    @positions ||=
      organization
        .positions
        .where(active: true)
        .includes(:bill)
        .eager_load(:bill)
        .preload(bill: %i[roll_calls categories legislative_session bill_llm_provisioning bill_summary_revisions])
  end

  def pending_changes
    @pending_changes ||= OrganizationBillPositionChange.pending(organization).joins(organization_bill_position: :bill)
  end

  def current_user_membership
    @current_user_membership ||=
      UserOrganizationMembership.find_by(
        organization: organization,
        user: current_user
      )
  end

  # @lat: [[organizations-base-controller-membership-guards#Organizations base controller membership guards#Why membership redirects check for nil first]]
  def redirect_to_current_user_membership(**kwargs)
    membership = current_user_membership
    if membership.nil?
      return redirect_to(users_organization_memberships_path)
    end

    # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
    redirect_params = {org_tab: organization_tab_param}.merge(kwargs)
    redirect_to organization_membership_path(organization_id: organization.id, id: membership.id, **redirect_params)
  end

  private

  # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
  def organization_tab_param
    return params[:org_tab].presence if params.key?(:org_tab)
    return params[:tab].presence if params.key?(:tab)

    params[:tab_key].presence
  end

  def verify_is_organization_admin!
    membership = current_user_membership
    return if membership&.admin? && membership.active?

    if request.format.json?
      render_error(code: "forbidden", message: "Forbidden", status: :forbidden)
    elsif membership.nil?
      # @lat: [[organizations-base-controller-membership-guards#Why a missing membership returns a direct 403]]
      render plain: "Forbidden", status: :forbidden
    else
      flash[:alert] = "Forbidden"
      redirect_to_current_user_membership
    end
  end

  def membership_as_props
    membership = current_user_membership ||
      raise("membership_as_props requires a current_user_membership")

    props = {
      **membership.to_sway_json.symbolize_keys,
      organization: organization.to_simple_builder.attributes!,
      role: membership.role,
      positions:
        (
          positions.map do |p|
            {
              id: p.id,
              support: p.support,
              summary: p.summary_for_readers,
              # @lat: [[ai-unreviewed-notice-component-design#The server sends a derived boolean, not the source text]]
              summary_ai_unreviewed: p.summary_ai_unreviewed?,
              bill: p.bill.to_sway_json
            }
          end
        )
    } #: Hash[Symbol, untyped]

    if membership.admin? && membership.active?
      props[:members] = (
        members.map do |m|
          {
            id: m.id,
            user_id: m.user.id,
            full_name: m.user.full_name,
            email: m.user.email,
            role: m.role
          }
        end
      )
    end
    props[:pending_changes] = pending_changes_props
    props
  end

  def pending_changes_props
    membership = current_user_membership ||
      raise("pending_changes_props requires a current_user_membership")

    scope =
      if membership.admin? && membership.active?
        pending_changes
      elsif membership.active?
        pending_changes.where(updated_by: current_user)
      else
        pending_changes.none
      end
    scope.map(&:to_sway_json)
  end
end
