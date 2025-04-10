# frozen_string_literal: true
# typed: true

class UserLegislatorsController < ApplicationController
  def index
    render json: current_user&.user_legislators_by_locale(T.cast(current_sway_locale, SwayLocale)), status: :ok
  end

  def create
    u = T.cast(current_user, User)

    SwayRegistrationService.new(
      u,
      T.cast(u.address, Address),
      T.cast(current_sway_locale, SwayLocale),
      invited_by_id: cookies.permanent[UserInviter::INVITED_BY_SESSION_KEY]
    ).run

    route_component(legislators_path)
  end
end
