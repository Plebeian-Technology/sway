# typed: true

class Users::UserDetailsController < ApplicationController
  extend T::Sig

  def create
    unless current_user&.update(full_name: user_details_params[:full_name])
      flash[:error] = "Failed to save your name. Please try again."
    end
    redirect_to(redirect_path)
  end

  private

  def redirect_path
    bill_path(user_details_params[:bill_id], {with: "legislator,address"})
  end

  # Currently this flow only works on bill path, TODO: Decouple
  def user_details_params
    params.require(:user_detail).permit(:bill_id, :full_name)
  end
end
