# typed: true

class UserLegislatorsController < ApplicationController
  before_action :redirect_if_no_current_user, :set_sway_locale

  def index
    render json: current_user&.user_legislators_by_locale(T.cast(current_sway_locale, SwayLocale)), status: :ok
  end

  def create
    u = T.cast(current_user, User)
    SwayRegistrationService.new(u, T.cast(u.address, Address), @sway_locale).run
    T.unsafe(self).route_legislators
  end

  private

  def set_sway_locale
    @sway_locale ||= SwayLocale.find(params[:sway_locale_id])
  end
end
