# frozen_string_literal: true

class SwayLocalesController < ApplicationController
  skip_before_action :authenticate_sway_user!

  # @lat: [[request-locale-selection#Anonymous fallback locale lists are filtered to declared locales]]
  def index
    render json:
             (current_user&.sway_locales || SwayLocale.declared).map(&:to_sway_json),
      status: :ok
  end

  # @lat: [[request-locale-selection#Why SwayLocalesController#show falls back with find_by and never sets a cookie]]
  def show
    locale = SwayLocale.find_by(id: params[:id]) || SwayLocale.default_locale
    if locale.nil?
      nil
    else
      render json: locale.to_sway_json, status: :ok
    end
  end
end
