# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  include Devise::Passkeys::Controllers::SessionsControllerConcern
  include RelyingParty

  def set_relying_party_in_request_env
    request.env[relying_party_key] = relying_party
  end

  # before_action :configure_sign_in_params, only: [:create]

  # GET /resource/sign_in
  # def new
  #   super
  # end

  # POST /resource/sign_in
  # def create
  #   super
  # end

  # DELETE /resource/sign_out
  # def destroy
  #   super
  # end

  # protected

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_sign_in_params
  #   devise_parameter_sanitizer.permit(:sign_in, keys: [:attribute])
  # end

  # before_action :configure_sign_in_params, only: [:create]

  # protected

  # def configure_sign_in_params
  #   devise_parameter_sanitizer.permit(:sign_in, keys: [:token])
  # end
end
