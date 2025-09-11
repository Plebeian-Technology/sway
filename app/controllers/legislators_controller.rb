# frozen_string_literal: true
# typed: true

class LegislatorsController < ApplicationController
  before_action :set_legislator, only: %i[show]
  skip_before_action :authenticate_sway_user!, only: %i[show]

  # GET /legislators or /legislators.json
  def index
    render_component(
      Pages::LEGISLATORS,
      lambda { { legislators: json_legislators } },
    )
  end

  def show
    render_component(
      Pages::LEGISLATORS,
      lambda { { legislators: [@legislator.to_sway_json] } },
    )
  end

  private

  def set_legislator
    @legislator = Legislator.find(params[:id])
  end

  def json_legislators
    current_user
      &.user_legislators
      &.joins(:legislator)
      &.where(active: true, legislators: { active: true })
      &.map { |ul| ul.legislator.to_sway_json }
  end

  # Only allow a list of trusted parameters through.
  def legislator_params
    params.require(:legislator).permit(:id)
  end
end
