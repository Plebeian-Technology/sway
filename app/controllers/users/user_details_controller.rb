module Users
  class UserDetailsController < ApplicationController
    def create
      flash[
        :error
      ] = "Failed to save your name. Please try again." unless current_user.update(
        full_name: user_details_params[:full_name],
      )
      redirect_to redirect_path,
                  inertia: {
                    errors: current_user.errors,
                  },
                  allow_other_host: false
    end

    private

    def current_user
      super
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
