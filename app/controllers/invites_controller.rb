# typed: true

class InvitesController < ApplicationController
  extend T::Sig

  skip_before_action :redirect_if_no_current_user

  def show
    case i = UserInviter.find_by(invite_params)
    when nil
      # noop
    else
      session[UserInviter::INVITED_BY_SESSION_KEY] = i.user_id
    end

    redirect_to root_path
  end

  private

  def invite_params
    params.permit(:user_id, :invite_uuid)
  end
end
