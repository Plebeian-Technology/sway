# typed: true

module Users
  class UserDetailsController < ApplicationController
    extend T::Sig

    def create
      unless current_user.update(full_name: user_details_params[:full_name])
        flash[:error] = "Failed to save your name. Please try again."
      end
      redirect_to redirect_path, inertia: { errors: current_user.errors }, allow_other_host: false
    end

    private

    sig { returns(User) }
    def current_user
      T.cast(super, User)
    end

    def redirect_path
      if user_details_params[:redirect_url].present?
        user_details_params[:redirect_url]
      elsif user_details_params[:bill_id].present?
        bill_path(user_details_params[:bill_id], { with: "legislator,address" })
      else
        root_path
      end
    end

    # Currently this flow only works on bill path, TODO: Decouple
    def user_details_params
      params.require(:user_detail).permit(:bill_id, :full_name, :redirect_url)
    end
  end
end
