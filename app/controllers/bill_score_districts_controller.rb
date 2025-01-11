# frozen_string_literal: true
# typed: true

class BillScoreDistrictsController < ApplicationController
  # GET /bill_score_districts/1 or /bill_score_districts/1.json
  def show
    render json: BillScoreDistrict.where(bill_score_id: bill_score_district_params[:bill_score_id]).map(&:to_sway_json),
      status: :ok
  end

  private

  # Only allow a list of trusted parameters through.
  def bill_score_district_params
    params.require(:bill_score_district).permit(:bill_score_id, :district)
  end
end
