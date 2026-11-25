# frozen_string_literal: true

class BillScoreDistrictsController < ApplicationController
  def show
    bill_score =
      BillScore.includes(bill_score_districts: :district).find_by(id: bill_score_district_params[:bill_score_id])
    render json: (bill_score&.publishable_districts || []).map(&:to_sway_json), status: :ok
  end

  private

  def bill_score_district_params
    params.require(:bill_score_district).permit(:bill_score_id, :district)
  end
end
