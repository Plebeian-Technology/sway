class InvitesController < ApplicationController
  def index
    render json: Invite.where(inviter: current_user), status: :ok
  end

  def create
    i = Invite.find_by(invitee_phone: invite_params[:invitee_phone])
    if i.present?
      render json: { success: false, message: "Could not send invite. Already invited." }, status: :ok
    elsif User.find_by(phone: invite_params[:invitee_phone]).present?
      render json: { success: false, message: "Could not send invite." }, status: :ok
    else
      invite = Invite.create(**invite_params, inviter_id: current_user.id)
      if invite
        if invite.notify_invitee
          render json: { success: true }, status: :ok
        else
          render json: { success: false, message: "Could not send invite. Invalid phone." }, status: :ok
        end
      else
        render json: { success: false, message: invite.errors.join(", ") }, status: :ok
      end
    end

  end

  def destroy
  end

  private

  def invite_params
    params.require(:invite).permit(:invitee_phone)
  end
end
