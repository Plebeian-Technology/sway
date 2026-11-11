# frozen_string_literal: true

class UsersController < ApplicationController
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
