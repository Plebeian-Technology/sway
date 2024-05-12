class InvitesController < ApplicationController

  def show
    i = UserInviter.find_by(invite_params)
    if i.present?
      session[UserInviter::INVITED_BY_SESSION_KEY] = i.user_id
    end

    redirect_to root_path
  end

  private

  def invite_params
    params.require(:invite).permit(:user_id, :invite_uuid)
  end
end
