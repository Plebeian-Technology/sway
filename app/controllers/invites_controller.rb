# frozen_string_literal: true

class InvitesController < ApplicationController
  skip_before_action :authenticate_sway_user!

  def show
    UserInviter
      .find_by(invite_params)
      .tap do |i|
        cookies.permanent[UserInviter::INVITED_BY_SESSION_KEY] = i&.user_id
      end

    redirect_to root_path
  end

  private

  def invite_params
    params.permit(:user_id, :invite_uuid)
  end
end
