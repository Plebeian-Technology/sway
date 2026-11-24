# frozen_string_literal: true

class UsersController < ApplicationController
  SIGNED_OUT_ALL_DEVICES_NOTICE = "You have been signed out on every device."

  # @lat: [[identity-and-access#Why UsersController#destroy revokes devices before cascading account deletion]]
  def destroy
    user = current_user
    unless user && params[:id].to_i == user.id
      return render_forbidden_or_redirect
    end

    user.revoke_all_devices!
    user.destroy!
    sign_out

    if mobile_api_request?
      head :no_content
    else
      redirect_to root_path, notice: "Your account has been deleted.", inertia: {clear_history: true}
    end
  end

  # @lat: [[identity-and-access#Sessions, cookies and bearer tokens#Signing out every browser]]
  def sign_out_all_devices
    current_user.sign_out_all_devices!
    sign_out

    redirect_to root_path, notice: SIGNED_OUT_ALL_DEVICES_NOTICE, inertia: {clear_history: true}
  end

  private

  def render_forbidden_or_redirect
    if mobile_api_request?
      render(
        json: {error: "forbidden", message: "You can only delete your own account."},
        status: :forbidden
      )
    else
      redirect_to(root_path)
    end
  end
end
