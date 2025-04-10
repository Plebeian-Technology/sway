# frozen_string_literal: true
# typed: true

class SwayLocalesController < ApplicationController
  # GET /sway_locales or /sway_locales.json
  def index
    render json: current_user&.sway_locales&.map(&:to_sway_json), status: :ok
  end

  # GET /sway_locales/1 or /sway_locales/1.json
  def show
    locale = T.let(SwayLocale.find(params[:id]), T.nilable(SwayLocale)) || T.cast(SwayLocale.default_locale, SwayLocale)
    if locale.nil?
      nil
    else
      cookies.permanent[:sway_locale_id] = locale.id
      render json: locale.to_sway_json, status: :ok
    end
  end

  private

  # Only allow a list of trusted parameters through.
  def sway_locale_params
    params.require(:sway_locale).permit(:id)
  end
end
