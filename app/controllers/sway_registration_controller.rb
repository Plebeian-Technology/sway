# frozen_string_literal: true

class SwayRegistrationController < ApplicationController
  skip_before_action :authenticate_sway_user!

  # @lat: [[registration-dead-ends#Correcting an address after a failed lookup]]
  REGISTRATION_UNAVAILABLE_MESSAGE =
    "We couldn't verify your address right now — the district lookup service is " \
    "temporarily unavailable. Please try again in a few minutes."
  # @lat: [[registration-dead-ends#Correcting an address after a failed lookup]]
  REGISTRATION_NO_REPRESENTATIVES_MESSAGE =
    "We couldn't find representatives for this address. Check that it is in a Sway-supported area and try again."
  REGISTRATION_ADDRESS_SWITCH_CONFIRMATION_MESSAGE =
    "Switching your address deactivates your current representative links. Please confirm to continue."
  REGISTRATION_ADDRESS_SWITCH_COOLDOWN_MESSAGE =
    "You recently changed your address. To prevent cross-district voting abuse, please wait before switching addresses again."

  def index
    u = current_user
    if u.nil?
      redirect_to root_path
    elsif u.registered?
      u.complete! unless u.completed? && u.is_registration_complete
      redirect_to legislators_path
    elsif u.processing?
      render inertia: Pages::REGISTRATION, props: registration_page_props(processing: true)
    else
      render inertia: Pages::REGISTRATION, props: registration_page_props
    end
  end

  # @lat: [[registration-dead-ends#An empty list says which kind of empty it is]]
  def create
    u = current_user
    if u.nil?
      return respond_json_or_redirect(status: :unauthorized, json: {error: {code: "unauthorized"}}, redirect: root_path)
    end

    # @lat: [[identity-and-access#Two voter-registration flags mean different things]]
    u.update!(is_voter_registration_address_confirmed: registered_voter_address_confirmed)

    # @lat: [[identity-and-access#A user holds one address]]
    address_instance = address
    existing_link = u.user_address
    if u.registered? && existing_link.present? && existing_link.address_id != address_instance.id
      return handle_address_switch(u, existing_link.address, address_instance)
    end

    if existing_link
      existing_link.update!(address: address_instance)
    else
      UserAddress.create!(user: u, address: address_instance)
    end

    if u.registered?
      u.complete! unless u.completed? && u.is_registration_complete
      return redirect_after_registration_completion(u)
    end

    begin
      # @lat: [[registration-dead-ends#Correcting an address after a failed lookup]]
      ActiveRecord::Base.transaction do
        address_instance.sway_locales.each do |sway_locale|
          SwayRegistrationService.new(
            u,
            address_instance,
            sway_locale,
            invited_by_id: invited_by_id,
            async: false
          ).call
        end
      end
    rescue SwayGeocode::ServiceUnavailableError => e
      return render_geocoding_unavailable(u, address_instance, e)
    end

    u.reload
    if u.registered?
      u.complete! unless u.completed? && u.is_registration_complete
      redirect_after_registration_completion(u)
    else
      render_no_representatives
    end
  end

  private

  def handle_address_switch(u, previous_address, new_address)
    unless confirm_deactivate_legislators?
      error = RegistrationErrorResource.new(
        {
          code: "confirmation_required",
          message: REGISTRATION_ADDRESS_SWITCH_CONFIRMATION_MESSAGE
        }
      ).serializable_hash
      return respond_json_or_redirect(
        status: :unprocessable_content,
        json: {error: error},
        redirect: sway_registration_index_path
      )
    end

    if UserAddressSwitchService.cooldown_active_for?(u)
      error = RegistrationErrorResource.new(
        {
          code: "address_switch_cooldown",
          message: REGISTRATION_ADDRESS_SWITCH_COOLDOWN_MESSAGE
        }
      ).serializable_hash
      return respond_json_or_redirect(
        status: :unprocessable_content,
        json: {error: error},
        redirect: sway_registration_index_path
      )
    end

    change =
      begin
        UserAddressSwitchService.new(u, previous_address: previous_address, new_address: new_address).call
      rescue SwayGeocode::ServiceUnavailableError => e
        return render_geocoding_unavailable(u, new_address, e)
      end

    if change
      u.reload
      u.complete! unless u.completed? && u.is_registration_complete
      redirect_after_registration_completion(u)
    else
      render_no_representatives
    end
  end

  def render_geocoding_unavailable(u, address_instance, exception)
    SwayLogging.log_exception(
      "sway_registration.geocoding_unavailable",
      exception: exception,
      user_id: u.id,
      address_id: address_instance.id
    )
    flash[:alert] = REGISTRATION_UNAVAILABLE_MESSAGE
    respond_json_or_redirect(
      status: :service_unavailable,
      json: {error: {code: "geocoding_unavailable", message: REGISTRATION_UNAVAILABLE_MESSAGE}},
      redirect: sway_registration_index_path
    )
  end

  def render_no_representatives
    error = RegistrationErrorResource.new(
      {
        code: "no_representatives",
        message: REGISTRATION_NO_REPRESENTATIVES_MESSAGE
      }
    ).serializable_hash
    flash[:registration_outcome] = {
      reason: "no_representatives",
      message: REGISTRATION_NO_REPRESENTATIVES_MESSAGE
    }
    respond_json_or_redirect(
      status: :unprocessable_content,
      json: {error: error},
      redirect: sway_registration_index_path
    )
  end

  def redirect_after_registration_completion(u)
    # @lat: [[low-friction-voting#Reconciliation on registration and sign-in]]
    reconciliation = PendingVoteReconciliationService.call(user: u, cookies: cookies)
    if reconciliation[:success] && reconciliation[:bill].present?
      respond_json_or_redirect(status: :ok, json: {ok: true, registration_status: "completed"}, redirect: bill_path(reconciliation[:bill]))
    else
      respond_json_or_redirect(status: :ok, json: {ok: true, registration_status: "completed"}, redirect: legislators_path)
    end
  end

  def registration_page_props(processing: false)
    props = {}
    props[:processing] = true if processing
    if flash[:registration_outcome].present?
      props[:registration_outcome] = RegistrationOutcomeResource.new(
        flash[:registration_outcome].symbolize_keys
      ).serializable_hash
    end
    props
  end

  def registered_voter_address_confirmed
    ActiveModel::Type::Boolean.new.cast(sway_registration_params[:is_voter_registration_address_confirmed]) || false
  end

  def confirm_deactivate_legislators?
    ActiveModel::Type::Boolean.new.cast(sway_registration_params[:confirm_deactivate_legislators]) == true
  end

  # @lat: [[identity-and-access#Registration is asynchronous by necessity#Browser and mobile preserve their response formats]]
  def respond_json_or_redirect(status:, json:, redirect:)
    if mobile_api_request?
      render json: json, status: status
    else
      redirect_to redirect, inertia: {errors: json[:error]}
    end
  end

  # @lat: [[address-normalized-key#Finding an address during registration]]
  def address
    found = address_by_normalized_key || Address.create!(
      street: sway_registration_params.fetch(:street),
      street2: sway_registration_params[:street2],
      street3: sway_registration_params[:street3],
      city: sway_registration_params.fetch(:city),
      region_code: sway_registration_params.fetch(:region_code),
      postal_code: sway_registration_params.fetch(:postal_code),
      country: sway_registration_params.fetch(:country),
      latitude: sway_registration_params.fetch(:latitude),
      longitude: sway_registration_params.fetch(:longitude)
    )

    changes = {}
    if submitted_normalized_key.present? && found.normalized_key != submitted_normalized_key
      changes[:normalized_key] = submitted_normalized_key
    end
    changes[:place_types] = submitted_place_types if found.place_types.blank? && submitted_place_types.present?
    found.update!(**changes) if changes.any?

    found
  end

  def address_by_normalized_key
    return nil if submitted_normalized_key.blank?

    Address.find_by(normalized_key: submitted_normalized_key)
  end

  def submitted_normalized_key
    return @submitted_normalized_key if defined?(@submitted_normalized_key)

    @submitted_normalized_key = Address.normalized_key_for(
      latitude: submitted_coordinate(:latitude),
      longitude: submitted_coordinate(:longitude),
      street2: sway_registration_params[:street2],
      street3: sway_registration_params[:street3]
    )
  end

  def submitted_coordinate(name)
    value = sway_registration_params[name]
    return nil if value.nil? || value.to_s.strip.empty?

    value.to_f
  end

  def submitted_place_types
    return @submitted_place_types if defined?(@submitted_place_types)

    submitted = sway_registration_params[:place_types]
    types = submitted.is_a?(Array) ? submitted : [] #: Array[untyped]
    @submitted_place_types = types.filter_map do |type|
      text = type.to_s
      text unless text.empty?
    end
  end

  def sway_registration_params
    params.require(:sway_registration).permit(
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
end
