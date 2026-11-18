# frozen_string_literal: true

module RegistrationControllerHelpers
  extend ActiveSupport::Concern

  def registration_page_props
    props = {}
    if flash[:registration_outcome].present?
      props[:registration_outcome] = RegistrationOutcomeResource.new(
        flash[:registration_outcome].symbolize_keys
      ).serializable_hash
    end
    props
  end

  def confirm_deactivate_legislators?
    ActiveModel::Type::Boolean.new.cast(sway_registration_params[:confirm_deactivate_legislators]) == true
  end

  def sway_registration_params
    submitted = params[:sway_registration]
    submitted = ActionController::Parameters.new unless submitted.is_a?(ActionController::Parameters)
    submitted.permit(
      :latitude,
      :longitude,
      :street,
      :street2,
      :street3,
      :city,
      :region,
      :region_code,
      :postal_code,
      :country,
      :is_voter_registration_address_confirmed,
      :confirm_deactivate_legislators,
      place_types: []
    )
  end

  def respond_json_or_redirect(status:, json:, redirect:)
    if mobile_api_request?
      render json: json, status: status
    else
      redirect_path = if current_user&.registered? && redirect == sway_registration_index_path
                        edit_user_address_path
                      else
                        redirect
                      end
      redirect_to redirect_path, inertia: {errors: json[:error]}
    end
  end

  def mobile_api_request?
    request.headers["Accept"] == "application/json" || params[:format] == "json"
  end
  
  # ... Add other methods needed by AddressSwitching here ...
end
