# frozen_string_literal: true

module Users
  class AddressesController < ApplicationController
    include AddressSwitching
    include RegistrationControllerHelpers

    before_action :authenticate_sway_user!

    def edit
      render inertia: "users/AddressEdit", props: {
        address: current_user.user_address&.address&.to_builder&.serializable_hash,
        mode: "change_address"
      }
    end

    def update
      u = current_user
      previous_address = u.user_address&.address
      new_address = address
      
      handle_address_switch(u, previous_address, new_address)
    rescue => e
      render_address_switch_unavailable(u, address, e)
    end
    
    private
    
    # Required by AddressSwitching
    def render_geocoding_unavailable(u, address_instance, exception)
      SwayLogging.log_exception(
        "sway_registration.geocoding_unavailable",
        exception: exception,
        user_id: u.id,
        address_id: address_instance.id
      )
      flash[:alert] = SwayRegistrationController::REGISTRATION_UNAVAILABLE_MESSAGE
      respond_json_or_redirect(
        status: :service_unavailable,
        json: {error: {code: "geocoding_unavailable", message: SwayRegistrationController::REGISTRATION_UNAVAILABLE_MESSAGE}},
        redirect: address_change_redirect_path
      )
    end

    # Required by AddressSwitching
    def render_address_switch_unavailable(u, address_instance, exception)
      SwayLogging.log_exception(
        "sway_registration.address_switch_failed",
        exception: exception,
        user_id: u.id,
        address_id: address_instance.id
      )
      Sentry.capture_exception(exception, extra: {user_id: u.id, address_id: address_instance.id})
      flash[:alert] = SwayRegistrationController::REGISTRATION_ADDRESS_SWITCH_UNAVAILABLE_MESSAGE
      error = RegistrationErrorResource.new(
        {
          code: "registration_unavailable",
          message: SwayRegistrationController::REGISTRATION_ADDRESS_SWITCH_UNAVAILABLE_MESSAGE
        }
      ).serializable_hash
      respond_json_or_redirect(
        status: :service_unavailable,
        json: {error: error},
        redirect: address_change_redirect_path
      )
    end

    # Required by AddressSwitching
    def render_address_not_located(u, address_instance)
      PendingVoteReconciliationService.call(user: u, cookies: cookies)
      SwayLogging.warn("sway_registration.address_not_located", user_id: u.id, address_id: address_instance.id)
      Sentry.capture_message(
        "sway_registration.address_not_located",
        level: :warning,
        extra: {user_id: u.id, address_id: address_instance.id}
      )
      flash[:registration_outcome] = {
        reason: "address_not_located",
        message: SwayRegistrationController::ADDRESS_NOT_LOCATED_MESSAGE
      }
      respond_json_or_redirect(
        status: :ok,
        json: {
          ok: true,
          registration_status: "completed",
          address_located: false,
          message: SwayRegistrationController::ADDRESS_NOT_LOCATED_MESSAGE
        },
        redirect: address_change_redirect_path
      )
    end
    
    # Required by AddressSwitching
    def render_no_representatives
      error = RegistrationErrorResource.new(
        {
          code: "no_representatives",
          message: SwayRegistrationController::REGISTRATION_NO_REPRESENTATIVES_MESSAGE
        }
      ).serializable_hash
      flash[:registration_outcome] = {
        reason: "no_representatives",
        message: SwayRegistrationController::REGISTRATION_NO_REPRESENTATIVES_MESSAGE
      }
      respond_json_or_redirect(
        status: :unprocessable_content,
        json: {error: error},
        redirect: address_change_redirect_path
      )
    end

    def redirect_after_registration_completion(u)
      # @lat: [[low-friction-voting#Reconciliation on registration and sign-in]]
      reconciliation = PendingVoteReconciliationService.call(user: u, cookies: cookies)
      if reconciliation[:success] && reconciliation[:bill].present?
        respond_json_or_redirect(status: :ok, json: {ok: true, registration_status: "completed"}, redirect: bill_path(reconciliation[:bill]))
      else
        respond_json_or_redirect(status: :ok, json: {ok: true, registration_status: "completed"}, redirect: feed_path)
      end
    end
    
    # Copy of address logic from SwayRegistrationController
    # @lat: [[address-normalized-key#Finding an address during registration]]
    def address
      found = address_by_normalized_key || linked_address_with_submitted_text
      if found
        found.geocode_and_save unless found.located?
      else
        found = Address.create!(**submitted_address_attributes)
      end

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

    # @lat: [[address-normalized-key#Finding an address during registration#A repeated unlocated submission reuses the user's own row]]
    def linked_address_with_submitted_text
      return nil if submitted_normalized_key.present?

      linked = current_user&.user_address&.address
      return nil if linked.nil?
      return nil if linked.normalized_key.present?

      submitted = NormalizeAddressService.call(Address.new(**submitted_address_attributes))
      linked if SwayRegistrationController::ADDRESS_TEXT_FIELDS.all? { |field| same_submitted_text?(field, linked, submitted) }
    end

    def same_submitted_text?(field, linked, submitted)
      submitted_value = submitted.public_send(field).to_s
      return true if submitted_value.empty? && SwayRegistrationController::GEOCODE_FILLED_FIELDS.include?(field)

      linked.public_send(field).to_s == submitted_value
    end

    def submitted_address_attributes
      {
        street: submitted_text(:street),
        street2: sway_registration_params[:street2],
        street3: sway_registration_params[:street3],
        city: submitted_text(:city),
        region_code: submitted_text(:region_code),
        postal_code: submitted_text(:postal_code),
        country: submitted_text(:country),
        latitude: submitted_coordinate(:latitude),
        longitude: submitted_coordinate(:longitude)
      }
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

    def submitted_text(name)
      sway_registration_params[name].to_s
    end

    def submitted_coordinate(name)
      submitted_coordinates[name]
    end

    # @lat: [[address-normalization#Defensive coordinate parsing and validation bounds]]
    def submitted_coordinates
      return @submitted_coordinates if defined?(@submitted_coordinates)

      latitude = parsed_coordinate(sway_registration_params[:latitude], 90)
      longitude = parsed_coordinate(sway_registration_params[:longitude], 180)
      @submitted_coordinates =
        if latitude && longitude
          {latitude: latitude, longitude: longitude}
        else
          {latitude: nil, longitude: nil}
        end
    end

    def parsed_coordinate(value, bound)
      number = Float(value, exception: false)
      number if number&.finite? && number.abs <= bound
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
  end
end
