# frozen_string_literal: true
# typed: true

class Organizations::MembershipInvitesController < Organizations::BaseController
  before_action :require_admin!

  def create
    @invite =
      UserOrganizationMembershipInvite.new(
        invite_params.merge(
          inviter: current_user,
          organization_id: params[:organization_id],
        ),
      )
    if @invite.save
      if Rails.env.test?
        UserOrganizationMembershipInviteMailer.invite(@invite).deliver_now
      else
        UserOrganizationMembershipInviteMailer.invite(@invite).deliver_later
      end
      render json: { success: true }
    else
      render json: {
               errors: @invite.errors.full_messages,
             },
             status: :unprocessable_entity
    end
  end

  private

  def invite_params
    params.require(:invite).permit(:invitee_email, :role)
  end

  def require_admin!
    unless UserOrganizationMembership.find_by(
             user: current_user,
             organization_id: params[:organization_id],
             role: :admin,
           ).present?
      render json: { error: "Forbidden" }, status: :forbidden
    end
  end
end
