# frozen_string_literal: true

module AddressSwitching
  extend ActiveSupport::Concern

  def handle_address_switch(u, previous_address, new_address)
    unless confirm_deactivate_legislators?
      error = RegistrationErrorResource.new(
        {
          code: "confirmation_required",
          message: SwayRegistrationController::REGISTRATION_ADDRESS_SWITCH_CONFIRMATION_MESSAGE
        }
      ).serializable_hash
      return respond_json_or_redirect(
        status: :unprocessable_content,
        json: {error: error},
        redirect: address_change_redirect_path
      )
    end

    if UserAddressSwitchService.cooldown_active_for?(u)
      error = RegistrationErrorResource.new(
        {
          code: "address_switch_cooldown",
          message: SwayRegistrationController::REGISTRATION_ADDRESS_SWITCH_COOLDOWN_MESSAGE
        }
      ).serializable_hash
      return respond_json_or_redirect(
        status: :unprocessable_content,
        json: {error: error},
        redirect: address_change_redirect_path
      )
    end

    change =
      begin
        UserAddressSwitchService.new(u, previous_address: previous_address, new_address: new_address).call
      rescue SwayGeocode::ServiceUnavailableError => e
        return render_geocoding_unavailable(u, new_address, e)
      rescue => e
        return render_address_switch_unavailable(u, new_address, e)
      end

    if change
      new_address.sway_locales.each { |sway_locale| u.add_pending_representative_locale(sway_locale) } unless new_address.located?
      u.reload
      u.complete_registration!
      return render_address_not_located(u, new_address) unless new_address.located?

      redirect_after_registration_completion(u)
    else
      render_no_representatives
    end
  end

  def address_change_redirect_path
    if current_user&.registered?
        edit_user_address_path
    else
        sway_registration_index_path
    end
  end
end
