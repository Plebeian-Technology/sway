# typed: true
class UserDistrictsController < ApplicationController

  def index
    render json: current_user&.districts(T.cast(current_sway_locale, SwayLocale)), status: :ok
  end


end
