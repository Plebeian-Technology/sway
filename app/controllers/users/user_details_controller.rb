# typed: true

class Users::UserDetailsController < ApplicationController
  extend T::Sig

  def create
    unless current_user&.update(full_name: user_details_params[:full_name])
      flash[:error] = "Failed to save your name. Please try again."
    end
    redirect_to(params[:redirect_to])
  end

  private

  def user_details_params
    params.require(:user_detail).permit(:redirect_to, :full_name)
  end
end
