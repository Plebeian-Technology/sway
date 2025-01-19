# frozen_string_literal: true
# typed: true

class UserLegislatorsController < ApplicationController
  before_action :set_sway_locale

  def index
    render json: current_user&.user_legislators_by_locale(T.cast(current_sway_locale, SwayLocale)), status: :ok
  end

  def create
    u = T.cast(current_user, User)

    SwayRegistrationService.new(
      u,
      T.cast(u.address, Address),
      @sway_locale,
      invited_by_id: session[UserInviter::INVITED_BY_SESSION_KEY]
    ).run

    redirect_to legislators_path
  end

  private

  def set_sway_locale
    @set_sway_locale ||= SwayLocale.find(params[:sway_locale_id])
  end
end
