class ApiKeysController < ApplicationController
  # include ApiKeyAuthenticatable
  # Require API key authentication
  # prepend_before_action :authenticate_with_api_key!, only: %i[index destroy]

  def index
    render_component(Pages::API_KEYS, { api_keys: current_user.api_keys })
  end

  def create
    if current_user.api_keys.blank?
      api_key = current_user.api_keys.create!(token: SecureRandom.hex)
      flash[:notice] = "API Key Created!"

      render json: { **api_key.attributes, token: api_key.token }, status: :ok
    else
      flash[:alert] = "You may only have 1 API Key."
      route_component(api_keys_path)
    end
  end

  def update
    current_user.api_keys.find_by(id: params[:id])&.update!(update_params)
    flash[:notice] = "API Key Name Updated"
    route_component(api_keys_path)
  end

  def destroy
    current_user.api_keys.find_by(id: params[:id])&.destroy
    flash[:notice] = "API Key Deleted!"
    route_component(api_keys_path)
  end

  private

  def update_params
    params.require(:api_keys_update_params).permit(:name)
  end
end
