# frozen_string_literal: true

# @lat: [[address-place-classification#Nominatim place classification and usage constraints]]
class AddressesController < ApplicationController
  include OnboardingSafetyNet

  MAX_QUERY_LENGTH = 200

  skip_before_action :authenticate_sway_user!

  rate_limit to: 60, within: 1.minute,
    by: -> { request.remote_ip },
    with: -> { render_rate_limited },
    store: ApplicationController::RATE_LIMIT_STORE

  def autocomplete
    query = string_param(:q).to_s.strip
    if query.blank? || query.length > MAX_QUERY_LENGTH
      render json: []
      return
    end

    results = NominatimService.search(
      query: query,
      viewbox: string_param(:viewbox),
      bounded: string_param(:bounded),
      countrycodes: string_param(:countrycodes),
      limit: string_param(:limit) || 5,
      google_fallback: current_user.present?
    )

    render json: results
  end

  private

  def string_param(key)
    value = params[key]
    value if value.is_a?(String)
  end
end
