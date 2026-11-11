# frozen_string_literal: true

class UserLegislatorsController < ApplicationController
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

    SwayRegistrationService.new(
      u,
      u.address,
      current_sway_locale,
      invited_by_id: invited_by_id
    ).call

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
end
