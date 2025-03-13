# frozen_string_literal: true
# typed: true

class LegislatorsController < ApplicationController
  before_action :set_legislator, only: %i[show]
  skip_before_action :authenticate_user!, only: %i[show]

  # GET /legislators or /legislators.json
  def index
    render_component(Pages::LEGISLATORS,
      lambda do
        {
          legislators: json_legislators
        }
      end)
  end

  def show
    render_component(Pages::LEGISLATORS,
      lambda do
        {
          legislators: [@legislator.to_sway_json]
        }
      end)
  end

  private

  def set_legislator
    @legislator = Legislator.find(params[:id])
  end

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
