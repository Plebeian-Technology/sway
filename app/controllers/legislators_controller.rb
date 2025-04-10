# frozen_string_literal: true
# typed: true

class LegislatorsController < ApplicationController
  # GET /legislators or /legislators.json
  def index
    render_component(Pages::LEGISLATORS,
      lambda do
        {
          legislators: json_legislators
        }
      end)
  end

  private

  def json_legislators
    current_user&.user_legislators&.joins(:legislator)&.where(active: true, legislators: {active: true})&.map do |ul|
      ul.legislator.to_sway_json
    end
  end

  # Only allow a list of trusted parameters through.
  def legislator_params
    params.require(:legislator).permit(:id)
  end
end
