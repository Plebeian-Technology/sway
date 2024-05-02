# typed: true

class SwayLocalesController < ApplicationController
  before_action :redirect_if_no_current_user

  # GET /sway_locales or /sway_locales.json
  def index
    render json: current_user&.sway_locales&.map { |s| s.to_builder.attributes! }, status: :ok
  end

  # GET /sway_locales/1 or /sway_locales/1.json
  def show
    render json: SwayLocale.find(params[:id]).to_builder.attributes!, status: :ok
  end

  private

  # Only allow a list of trusted parameters through.
  def sway_locale_params
    params.require(:sway_locale).permit(:id)
  end
end
