# frozen_string_literal: true

class DistrictsController < ApplicationController
  def index
    render json: current_user&.districts(current_sway_locale), status: :ok
  end
end
