# typed: true

class SwayLocalesController < ApplicationController
  before_action :redirect_if_no_current_user

  # GET /sway_locales or /sway_locales.json
  def index
    render json: current_user&.sway_locales&.map { |s| s.to_builder(current_user).attributes! }, status: :ok
  end

  # GET /sway_locales/1 or /sway_locales/1.json
  def show
    locale = T.let(SwayLocale.find(params[:id]), T.nilable(SwayLocale)) || T.cast(SwayLocale.default_locale, SwayLocale)
    if locale.nil?
      nil
    else
      session[:sway_locale_id] = locale.id
      render json: locale.to_builder(current_user).attributes!, status: :ok
    end
  end

  private

  # Only allow a list of trusted parameters through.
  def sway_locale_params
    params.require(:sway_locale).permit(:id)
  end
end
