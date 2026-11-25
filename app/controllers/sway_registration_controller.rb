# frozen_string_literal: true

class SwayRegistrationController < ApplicationController
  include OnboardingSafetyNet

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
  REGISTRATION_ADDRESS_SWITCH_UNAVAILABLE_MESSAGE =
    "We couldn't change your address right now. Please try again in a few minutes."
  # @lat: [[registration-dead-ends#A skipped lookup is recorded so it can be retried#An unlocated address waits for its geocode]]
  ADDRESS_NOT_LOCATED_MESSAGE =
    "We could not find this address on the map. Add your city and state, or your ZIP code, so we can match you to your district."
  ADDRESS_TEXT_FIELDS = %i[street street2 street3 city region_code postal_code country].freeze
  GEOCODE_FILLED_FIELDS = %i[city region_code postal_code country].freeze

  def index
    u = current_user
    if u.nil?
      redirect_to root_path
    elsif address_not_located_outcome?
      render inertia: Pages::REGISTRATION, props: registration_page_props
    elsif u.registered?
      u.complete_registration!
      redirect_to feed_path
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
    return_path = address_switch_return_path(u)

    # @lat: [[identity-and-access#A user holds one address]]
    existing_link = u.user_address
    previous_address = existing_link&.address
    previously_unlocated = previous_address.present? && !previous_address.located?
    address_instance = address
    if holds_representatives?(u, previous_address) && existing_link.present? && existing_link.address_id != address_instance.id
      return handle_address_switch(u, existing_link.address, address_instance, return_path)
    end

    record_voter_registration_address_confirmation(u)
    if existing_link
      existing_link.update!(address: address_instance)
    else
      begin
        UserAddress.create!(user: u, address: address_instance)
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        # @lat: [[identity-and-access#A user holds one address]]
        UserAddress.find_by!(user: u).update!(address: address_instance)
      end
    end

    if !previously_unlocated && holds_representatives?(u, previous_address)
      u.complete_registration!
      return redirect_after_registration_completion(u)
    end

    previous_legislators = clear_previous_unlocated_address(u, previous_address, address_instance)
    skipped_locales = [] #: Array[SwayLocale]
    resolved_locales = [] #: Array[SwayLocale]
    # @lat: [[sway-registration-controller-notes#Why one locale's failed lookup is skipped and reported]]
    address_instance.sway_locales.each do |sway_locale|
      service = SwayRegistrationService.new(
        u,
        address_instance,
        sway_locale,
        invited_by_id: invited_by_id
      )
      ActiveRecord::Base.transaction { service.call }
      if service.skipped_resolution_errors.any?
        skipped_locales << sway_locale
      else
        resolved_locales << sway_locale
      end
    rescue => e
      report_skipped_locale(u, address_instance, sway_locale, e)
      skipped_locales << sway_locale
    end

    # @lat: [[registration-dead-ends#A skipped lookup is recorded so it can be retried]]
    skipped_locales.each { |sway_locale| u.add_pending_representative_locale(sway_locale) }
    if address_instance.located?
      resolved_locales.each { |sway_locale| u.remove_pending_representative_locale(sway_locale) }
    else
      # @lat: [[registration-dead-ends#A skipped lookup is recorded so it can be retried#An unlocated address waits for its geocode]]
      address_instance.sway_locales.each { |sway_locale| u.add_pending_representative_locale(sway_locale) }
    end
    recompute_deactivated_legislator_scores(u, previous_legislators)

    u.reload
    wait_for_congress_representatives(u, address_instance) unless u.registered?
    u.complete_registration!
    return render_address_not_located(u, address_instance, redirect: return_path) unless address_instance.located?

    redirect_after_registration_completion(u)
  end

  private

  # @lat: [[registration-dead-ends#Correcting an address after a failed lookup#A President link alone is not a registration]]
  def holds_representatives?(u, previous_address = u.address)
    return false if previous_address && !previous_address.located?

    links = u.user_legislators.where(active: true).includes(legislator: {active_term: :seat})
    return false if links.empty?
    return true if u.pending_representative_locale_ids.empty?

    links.any? { |link| link.legislator.active_term&.seat&.seat_identifier != RepresentativeReassignmentObserver::PRESIDENT_SEAT_IDENTIFIER }
  end

  def clear_previous_unlocated_address(u, previous_address, new_address)
    return [] unless previous_address && !previous_address.located? && previous_address.id != new_address.id

    active_uls = u.user_legislators.where(active: true).includes(legislator: :active_term).to_a
    active_uls.each { |ul| ul.update!(active: false) }
    u.user_districts.where(active: true).find_each { |ud| ud.update!(active: false) }
    previous_address.sway_locales.each { |sway_locale| u.remove_pending_representative_locale(sway_locale) }
    active_uls.filter_map(&:legislator)
  end

  def recompute_deactivated_legislator_scores(u, previous_legislators)
    return if previous_legislators.empty?

    active_ids = u.user_legislators.where(active: true).pluck(:legislator_id)
    stale_legislators = previous_legislators.reject { |legislator| active_ids.include?(legislator.id) }.uniq(&:id)
    return if stale_legislators.empty?

    stale_legislators.each do |legislator|
      term = legislator.active_term
      ScoreRecomputeService.recompute_legislator!(term) if term
    end
    Bill.where(id: u.user_votes.select(:bill_id)).find_each do |bill|
      ScoreRecomputeService.recompute_bill!(bill)
    end
  end

  # @lat: [[onboarding-safety-net#Why every onboarding endpoint answers an unexpected error#A user with a representative link is completed]]
  def render_onboarding_unavailable
    u = current_user
    return super if u.nil?
    if address_switch_return_path(u) == edit_users_address_path
      return redirect_to(edit_users_address_path, alert: ONBOARDING_UNAVAILABLE_MESSAGE)
    end
    return super unless u.user_legislators.where(active: true).exists?

    u.complete_registration!
    respond_json_or_redirect(status: :ok, json: {ok: true, registration_status: "completed"}, redirect: feed_path)
  end

  # @lat: [[registration-dead-ends#A skipped lookup is recorded so it can be retried#An unlocated address waits for its geocode]]
  def handle_address_switch(u, previous_address, new_address, return_path)
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
        redirect: return_path
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
        redirect: return_path
      )
    end

    change =
      begin
        UserAddressSwitchService.new(u, previous_address: previous_address, new_address: new_address).call
      rescue SwayGeocode::ServiceUnavailableError => e
        return render_geocoding_unavailable(u, new_address, e, redirect: return_path)
      rescue => e
        return render_address_switch_unavailable(u, new_address, e, redirect: return_path)
      end

    if change
      record_voter_registration_address_confirmation(u)
      new_address.sway_locales.each { |sway_locale| u.add_pending_representative_locale(sway_locale) } unless new_address.located?
      u.reload
      u.complete_registration!
      return render_address_not_located(u, new_address, redirect: return_path) unless new_address.located?

      redirect_after_registration_completion(u)
    else
      render_no_representatives(redirect: return_path)
    end
  end

  # @lat: [[web-profile-page#Web profile page#Changing the address from the web]]
  def address_switch_return_path(u)
    change_address = ActiveModel::Type::Boolean.new.cast(sway_registration_params[:change_address]) == true
    (request.inertia? && change_address && u.registered?) ? edit_users_address_path : sway_registration_index_path
  end

  def render_geocoding_unavailable(u, address_instance, exception, redirect:)
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
      redirect: redirect
    )
  end

  # @lat: [[registration-dead-ends#A failed address switch changes nothing]]
  def render_address_switch_unavailable(u, address_instance, exception, redirect:)
    SwayLogging.log_exception(
      "sway_registration.address_switch_failed",
      exception: exception,
      user_id: u.id,
      address_id: address_instance.id
    )
    Sentry.capture_exception(exception, extra: {user_id: u.id, address_id: address_instance.id})
    flash[:alert] = REGISTRATION_ADDRESS_SWITCH_UNAVAILABLE_MESSAGE
    error = RegistrationErrorResource.new(
      {
        code: "registration_unavailable",
        message: REGISTRATION_ADDRESS_SWITCH_UNAVAILABLE_MESSAGE
      }
    ).serializable_hash
    respond_json_or_redirect(
      status: :service_unavailable,
      json: {error: error},
      redirect: redirect
    )
  end

  def report_skipped_locale(u, address_instance, sway_locale, exception)
    SwayLogging.log_exception(
      "sway_registration.locale_skipped",
      exception: exception,
      user_id: u.id,
      address_id: address_instance.id,
      sway_locale: sway_locale.name
    )
    Sentry.capture_exception(
      exception,
      extra: {user_id: u.id, address_id: address_instance.id, sway_locale: sway_locale.name}
    )
  end

  # @lat: [[registration-dead-ends#An empty list says which kind of empty it is]]
  def wait_for_congress_representatives(u, address_instance)
    sway_locales = address_instance.sway_locales
    sway_locale_names = sway_locales.map(&:name)
    SwayLogging.warn("sway_registration.no_representatives_resolved", user_id: u.id, sway_locales: sway_locale_names)
    Sentry.capture_message(
      "sway_registration.no_representatives_resolved",
      level: :warning,
      extra: {user_id: u.id, sway_locales: sway_locale_names}
    )
    congress = sway_locales.find(&:congress?)
    u.add_pending_representative_locale(congress) if congress
  end

  def render_no_representatives(redirect:)
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
      redirect: redirect
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

  # @lat: [[registration-dead-ends#A skipped lookup is recorded so it can be retried#An unlocated address waits for its geocode]]
  def render_address_not_located(u, address_instance, redirect: sway_registration_index_path)
    PendingVoteReconciliationService.call(user: u, cookies: cookies)
    SwayLogging.warn("sway_registration.address_not_located", user_id: u.id, address_id: address_instance.id)
    Sentry.capture_message(
      "sway_registration.address_not_located",
      level: :warning,
      extra: {user_id: u.id, address_id: address_instance.id}
    )
    flash[:registration_outcome] = {
      reason: "address_not_located",
      message: ADDRESS_NOT_LOCATED_MESSAGE
    }
    respond_json_or_redirect(
      status: :ok,
      json: {
        ok: true,
        registration_status: "completed",
        address_located: false,
        message: ADDRESS_NOT_LOCATED_MESSAGE
      },
      redirect: redirect
    )
  end

  def address_not_located_outcome?
    flash[:registration_outcome].present? &&
      flash[:registration_outcome].symbolize_keys[:reason] == "address_not_located"
  end

  def registration_page_props
    props = {}
    if flash[:registration_outcome].present?
      props[:registration_outcome] = RegistrationOutcomeResource.new(
        flash[:registration_outcome].symbolize_keys
      ).serializable_hash
    end
    props
  end

  # @lat: [[identity-and-access#Two voter-registration flags mean different things]]
  # @lat: [[sway-registration-controller-notes#Why create's own user writes skip unrelated validations]]
  def record_voter_registration_address_confirmation(u)
    u.update_column(:is_voter_registration_address_confirmed, registered_voter_address_confirmed)
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
    linked if ADDRESS_TEXT_FIELDS.all? { |field| same_submitted_text?(field, linked, submitted) }
  end

  def same_submitted_text?(field, linked, submitted)
    submitted_value = submitted.public_send(field).to_s
    return true if submitted_value.empty? && GEOCODE_FILLED_FIELDS.include?(field)

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

  # Returns an empty string for a missing or null field.
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

  # Returns nil unless the value is a finite number within -bound..bound.
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
      :change_address,
      place_types: []
    )
  end
end
