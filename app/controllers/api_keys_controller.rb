class ApiKeysController < ApplicationController
  before_action :verify_is_sway_api_user

  def index
    render inertia: Pages::API_KEYS, props: {api_keys: developer_api_keys.map(&:to_sway_json)}
  end

  def create
    current_user.with_lock do
      if developer_api_keys.blank?
        api_key = current_user.api_keys.create!(token: SecureRandom.hex)
        flash[:notice] = "API Key Created!"
        flash[:new_api_key_token] = api_key.token
      else
        flash[:alert] = "You may only have 1 API Key."
      end
    end
    redirect_to api_keys_path
  end

  def update
    developer_api_keys.find_by(id: params[:id])&.update!(api_key_params)
    flash[:notice] = "API Key Name Updated"
    redirect_to api_keys_path
  end

  def destroy
    developer_api_keys.find_by(id: params[:id])&.destroy
    flash[:notice] = "API Key Deleted!"
    redirect_to api_keys_path
  end

  private

  def developer_api_keys
    current_user.api_keys.where(user_device_id: nil)
  end

  # @lat: [[identity-and-access#The phone number is the account#Admin and API phone lists represent separate privileges]]
  def verify_is_sway_api_user
    return if current_user&.is_sway_api_user?

    if mobile_api_request?
      render_error(code: "forbidden", message: "API key access required.", status: :forbidden)
    else
      redirect_to root_path
    end
  end

  def api_key_params
    params.require(:api_keys_update_params).permit(:name)
  end
end
