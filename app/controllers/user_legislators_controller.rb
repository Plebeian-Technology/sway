# typed: true

class UserLegislatorsController < ApplicationController
  def index
    render json: current_user&.user_legislators_by_locale(T.cast(current_sway_locale, SwayLocale)), status: :ok
  end
end
