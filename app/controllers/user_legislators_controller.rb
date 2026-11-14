# frozen_string_literal: true

class UserLegislatorsController < ApplicationController
  REPRESENTATIVES_UNAVAILABLE_MESSAGE =
    "We couldn't look up your representatives right now. Please try again in a few minutes."

  def index
    # @lat: [[serializer-whitelist-endpoints#BillsController follows the same rule]]
    rows = current_user&.user_legislators_by_locale(current_sway_locale) || []
    render json: UserLegislatorResource.new(rows).serializable_hash, status: :ok
  end

  def create
    u = current_user
    unless u&.address.present? && u.sway_locales.include?(current_sway_locale)
      respond_to do |format|
        format.json { head :forbidden }
        format.html { redirect_to legislators_path, alert: "Unable to add representatives for this locale." }
      end
      return
    end

    begin
      SwayRegistrationService.new(
        u,
        u.address,
        current_sway_locale,
        invited_by_id: invited_by_id
      ).call
    rescue => e
      return render_representatives_unavailable(u, e)
    end

    # @lat: [[user-legislators-controller-format-split#Why UserLegislatorsController.create splits its response by format]]
    respond_to do |format|
      format.json do
        # @lat: [[serializer-whitelist-endpoints#BillsController follows the same rule]]
        rows = u.reload.user_legislators_by_locale(current_sway_locale)
        render json: UserLegislatorResource.new(rows).serializable_hash,
          status: :ok
      end
      format.html do
        redirect_to legislators_path, notice: "Your representatives have been added to your account!"
      end
    end
  end

  private

  # @lat: [[user-legislators-controller-format-split#Why UserLegislatorsController.create splits its response by format#A failed lookup leaves the links alone]]
  def render_representatives_unavailable(u, exception)
    SwayLogging.log_exception(
      "user_legislators.resolution_failed",
      exception: exception,
      user_id: u.id,
      sway_locale: current_sway_locale&.name
    )
    Sentry.capture_exception(exception, extra: {user_id: u.id, sway_locale: current_sway_locale&.name})
    respond_to do |format|
      format.json do
        error = RegistrationErrorResource.new(
          {code: "registration_unavailable", message: REPRESENTATIVES_UNAVAILABLE_MESSAGE}
        ).serializable_hash
        render json: {error: error}, status: :service_unavailable
      end
      format.html { redirect_to legislators_path, alert: REPRESENTATIVES_UNAVAILABLE_MESSAGE }
    end
  end
end
