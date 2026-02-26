# frozen_string_literal: true
# typed: true

class UserLegislatorScoresController < ApplicationController
  # GET /user_legislator_scores or /user_legislator_scores.json
  def index
    render json:
             UserLegislatorScore
               .joins(:user_legislator)
               .where(user_legislators: { user_id: current_user.id })
               .includes(
                 user_legislator: {
                   legislator: [{ district: :sway_locale }, :legislator_district_score],
                 },
               )
               .map(&:to_sway_json),
           status: :ok
  end

  # GET /user_legislator_scores/1 or /user_legislator_scores/1.json
  def show
    uls =
      UserLegislator.find_by(
        user: current_user,
        legislator_id: params[:id],
      )&.user_legislator_score

    if uls.present? && !uls.empty?
      render json: uls.to_sway_json, status: :ok
    else
      render json: nil, status: :ok
    end
  end

  private

  # Only allow a list of trusted parameters through.
  def user_legislator_score_params
    params.require(:user_legislator_score).permit(:legislator_id)
  end
end
