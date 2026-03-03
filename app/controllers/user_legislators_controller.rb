# frozen_string_literal: true

class UserLegislatorsController < ApplicationController
  def index
    render json: current_user&.user_legislators_by_locale(current_sway_locale),
           status: :ok
  end

  def create
    u = current_user

    SwayRegistrationService.new(
      u,
      u.address,
      current_sway_locale,
      invited_by_id: invited_by_id,
    ).run

    # route_component(legislators_path)
    render json: { success: true }, status: :ok
  end
end
