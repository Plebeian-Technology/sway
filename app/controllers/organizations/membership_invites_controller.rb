# frozen_string_literal: true

class Organizations::MembershipInvitesController < Organizations::BaseController
  before_action :verify_is_organization_admin!, except: %i[confirm_accept accept]

  rate_limit to: 100, within: 1.hour,
    by: -> { request.remote_ip },
    only: :create,
    if: -> { RateLimitConfig.enabled?(:org_invite) },
    with: -> { render_rate_limited },
    store: ApplicationController::RATE_LIMIT_STORE
  # @lat: [[organization-invitation-controller#Why the invite email limit reads the raw nested parameter]]
  rate_limit to: 5, within: 1.hour,
    by: -> { EmailCacheKey.digest(params.dig(:invite, :invitee_email)) },
    only: :create,
    if: -> { RateLimitConfig.enabled?(:org_invite) },
    with: -> { render_rate_limited },
    store: ApplicationController::RATE_LIMIT_STORE
  rate_limit to: 30, within: 1.hour,
    by: -> { current_user&.id || "anonymous" },
    only: :create,
    if: -> { RateLimitConfig.enabled?(:org_invite) },
    with: -> { render_rate_limited },
    store: ApplicationController::RATE_LIMIT_STORE

  rate_limit to: 30, within: 1.hour,
    by: -> { request.remote_ip },
    only: %i[confirm_accept accept destroy],
    if: -> { RateLimitConfig.enabled?(:org_invite) },
    with: -> { render_rate_limited },
    store: ApplicationController::RATE_LIMIT_STORE
  rate_limit to: 30, within: 1.hour,
    by: -> { current_user&.id || "anonymous" },
    only: %i[confirm_accept accept destroy],
    if: -> { RateLimitConfig.enabled?(:org_invite) },
    with: -> { render_rate_limited },
    store: ApplicationController::RATE_LIMIT_STORE

  class InviteAlreadyAccepted < StandardError; end
  class InviteRevoked < StandardError; end
  class InviteExpired < StandardError; end
  class InviteEmailMismatch < StandardError; end

  def confirm_accept
    invite = UserOrganizationMembershipInvite.find_signed!(
      params[:id],
      purpose: :accept_invite
    )

    # @lat: [[organization-invite-authorization#Invite acceptance is bound to token, organization, and email]]
    unless invite.organization_id.to_s == params[:organization_id].to_s
      return respond_invite_failure("Invitation not found.", status: :not_found)
    end

    unless email_matches?(invite, current_user)
      return respond_invite_failure("Forbidden", status: :forbidden)
    end

    if invite.expires_at.present? && Time.current > invite.expires_at
      return respond_invite_failure("Invitation expired.", status: :gone)
    end

    if invite.accepted_at.present? || invite.revoked_at.present?
      return respond_invite_failure(
        "This invitation is no longer valid.",
        status: :unprocessable_content
      )
    end

    render_inertia_or_json(
      page: Pages::ORGANIZATION_INVITE_CONFIRM,
      props: {
        signed_token: params[:id],
        organization: invite.organization.to_simple_builder.attributes!,
        inviter_name: invite.inviter&.full_name,
        expires_at: invite.expires_at
      }
    )
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    # @lat: [[organization-invite-authorization#Invite acceptance is bound to token, organization, and email]]
    respond_invite_failure("Invitation expired.", status: :gone)
  rescue ActiveRecord::RecordNotFound
    respond_invite_failure("Invitation not found.", status: :not_found)
  end

  def accept
    if current_user && params[:id].to_s.match?(/\A\d+\z/)
      membership = current_user.user_organization_memberships.find_by(
        id: params[:id],
        organization_id: params[:organization_id],
        status: :pending
      )
      return respond_invite_failure("Invitation not found.", status: :not_found) unless membership

      membership.update!(role: :standard) unless membership.standard?
      membership.activate!
      flash[:notice] = "You've joined #{membership.organization.name}."
      return redirect_or_json(users_organization_memberships_path, flash_message: flash[:notice], status: :see_other)
    end

    invite = UserOrganizationMembershipInvite.find_signed!(
      params[:id],
      purpose: :accept_invite
    )

    # @lat: [[organization-invite-authorization#Invite acceptance is bound to token, organization, and email]]
    unless invite.organization_id.to_s == params[:organization_id].to_s
      return respond_invite_failure("Invitation not found.", status: :not_found)
    end

    ActiveRecord::Base.transaction do
      invite.lock!
      raise InviteAlreadyAccepted if invite.accepted_at.present?
      raise InviteRevoked if invite.revoked_at.present?
      raise InviteExpired if invite.expires_at.present? && Time.current > invite.expires_at
      raise InviteEmailMismatch unless email_matches?(invite, current_user)

      # @lat: [[organization-invite-authorization#Reaccepting an invite restores the existing membership]]
      existing = UserOrganizationMembership.find_by(
        user: current_user,
        organization: invite.organization
      )

      if existing
        unless existing.active?
          existing.update!(role: :standard) unless existing.standard?
          existing.activate!
        end
      else
        UserOrganizationMembership.create!(
          user: current_user,
          organization: invite.organization,
          role: :standard,
          status: :pending
        ).activate!
      end

      invite.update!(accepted_at: Time.current, invitee_user_id: current_user.id)
    end

    flash[:notice] = "You've joined #{invite.organization.name}."
    # @lat: [[organization-invitation-controller#Why accepting an invite redirects with See Other]]
    redirect_or_json(users_organization_memberships_path, flash_message: flash[:notice], status: :see_other)
  rescue InviteAlreadyAccepted
    respond_invite_failure("Invite already accepted", status: :unprocessable_content)
  rescue InviteRevoked
    respond_invite_failure("Invite has been revoked", status: :unprocessable_content)
  rescue InviteExpired, ActiveSupport::MessageVerifier::InvalidSignature
    # @lat: [[organization-invite-authorization#Invite acceptance is bound to token, organization, and email]]
    respond_invite_failure("Invitation expired.", status: :gone)
  rescue InviteEmailMismatch
    respond_invite_failure("Forbidden", status: :forbidden)
  rescue ActiveRecord::RecordNotFound
    respond_invite_failure("Invitation not found.", status: :not_found)
  rescue StateMachines::InvalidTransition
    respond_invite_failure("Membership already activated", status: :unprocessable_content)
  end

  def destroy
    invite = UserOrganizationMembershipInvite
      .where(organization_id: params[:organization_id])
      .find(params[:id])

    if invite.accepted_at.present?
      return render status: :unprocessable_content, json: {errors: ["Invite already accepted"]}
    end

    if invite.revoked_at.present?
      return render status: :unprocessable_content, json: {errors: ["Already revoked"]}
    end

    invite.update!(revoked_at: Time.current)
    head :no_content
  end

  # @lat: [[organization-invitation-controller#Creating an invite returns format-specific responses]]
  def create
    @invite =
      UserOrganizationMembershipInvite.new(
        invite_params.merge(
          inviter: current_user,
          organization_id: params[:organization_id]
        )
      )

    unless @invite.save
      if mobile_api_request?
        return render_error(
          code: "validation_failed",
          message: @invite.errors.full_messages.to_sentence.presence || "Invite could not be created.",
          status: :unprocessable_content,
          details: {base: @invite.errors.full_messages}
        )
      end

      return redirect_to(members_tab_path, inertia: {errors: @invite.errors})
    end

    if Rails.env.test?
      UserOrganizationMembershipInviteMailer.invite(@invite).deliver_now
    else
      UserOrganizationMembershipInviteMailer.invite(@invite).deliver_later
    end

    redirect_or_json(members_tab_path, flash_message: "Invite sent.")
  end

  private

  def email_matches?(invite, user)
    return false if user.nil? || invite.invitee_email.blank? || user.email.blank?
    ActiveSupport::SecurityUtils.secure_compare(
      invite.invitee_email.to_s.downcase,
      user.email.to_s.downcase
    )
  end

  # @lat: [[organization-invitation-controller#Why failed invite acceptance has format-specific responses]]
  def respond_invite_failure(message, status:)
    if request.format.json?
      render status: status, json: {errors: [message]}
    else
      flash[:alert] = message
      redirect_to users_organization_memberships_path, status: :see_other
    end
  end

  def invite_params
    params.require(:invite).permit(:invitee_email)
  end

  # @lat: [[organization-invitation-controller#Creating an invite returns format-specific responses]]
  def members_tab_path
    membership = current_user_membership ||
      raise("members_tab_path requires a current_user_membership")
    organization_membership_path(
      organization_id: organization.id,
      id: membership.id,
      org_tab: "members"
    )
  end
end
