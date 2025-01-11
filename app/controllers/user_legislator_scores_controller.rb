# frozen_string_literal: true
# typed: true

class UserLegislatorScoresController < ApplicationController
  # GET /user_legislator_scores or /user_legislator_scores.json
  def index
    render json: UserLegislatorScore.where(user: current_user).map(&:to_sway_json), status: :ok
  end

  # GET /user_legislator_scores/1 or /user_legislator_scores/1.json
  def show
    render json: UserLegislator.find_by(
      user: current_user,
      legislator_id: params[:id]
    )&.user_legislator_score&.to_builder&.attributes!,
      status: :ok
  end

  private

  # Only allow a list of trusted parameters through.
  def user_legislator_score_params
    params.require(:user_legislator_score).permit(:legislator_id)
  end
end
