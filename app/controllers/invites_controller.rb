# frozen_string_literal: true

class InvitesController < ApplicationController
  skip_before_action :authenticate_sway_user!

  def show
    UserInviteLink
      .find_by(invite_params)
      .tap do |i|
        if i.present?
          cookies.permanent[UserInviteLink::INVITED_BY_SESSION_KEY] = i.user_id
          cookies.permanent[:sway_attribution_key] = "invite:#{params[:invite_uuid]}" if params[:invite_uuid].present?
        end
      end

    redirect_to root_path
  end

  private

  def invite_params
    params.permit(:user_id, :invite_uuid)
  end
end
