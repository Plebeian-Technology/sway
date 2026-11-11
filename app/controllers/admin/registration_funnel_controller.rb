# frozen_string_literal: true

# @lat: [[admin-hub-and-tabs#Why /admin exists]]
# @lat: [[identity-and-access#The admin gate is a lint rule]]
module Admin
  class RegistrationFunnelController < ApplicationController
    before_action :verify_is_sway_admin

    def index
      time_range = params[:time_range].presence || "30d"
      attribution_key = params[:attribution_key].presence
      traffic = params[:traffic].presence || "humans"

      metrics = RegistrationFunnelMetricsService.new(
        time_range: time_range,
        attribution_key: attribution_key,
        traffic: traffic
      ).call

      serialized_funnel = RegistrationFunnelResource.new(metrics).serializable_hash

      respond_to do |format|
        format.html do
          render_inertia_or_json(
            page: Pages::ADMIN_REGISTRATION_FUNNEL,
            props: {funnel: serialized_funnel}
          )
        end
        format.json do
          render json: serialized_funnel, status: :ok
        end
      end
    end
  end
end
