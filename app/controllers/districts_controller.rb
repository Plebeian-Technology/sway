# frozen_string_literal: true

class DistrictsController < ApplicationController
  def index
    # @lat: [[system-shape#System shape#One process, two languages#Why a payload goes through a resource rather than the record]]
    districts = current_user&.districts(current_sway_locale) || []
    render json: DistrictResource.new(districts).serializable_hash, status: :ok
  end
end
