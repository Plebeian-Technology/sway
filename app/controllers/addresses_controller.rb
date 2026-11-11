# frozen_string_literal: true

# @lat: [[address-place-classification#Nominatim place classification and usage constraints]]
class AddressesController < ApplicationController
  skip_before_action :authenticate_sway_user!

  rate_limit to: 60, within: 1.minute,
    by: -> { request.remote_ip },
    with: -> { render_rate_limited },
    store: ApplicationController::RATE_LIMIT_STORE

  def autocomplete
    query = params[:q].to_s.strip
    if query.blank?
      render json: []
      return
    end

    results = NominatimService.search(
      query: query,
      viewbox: params[:viewbox],
      bounded: params[:bounded],
      countrycodes: params[:countrycodes],
      limit: params[:limit] || 5
    )

    render json: results
  end
end
