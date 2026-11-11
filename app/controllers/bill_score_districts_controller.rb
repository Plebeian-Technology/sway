# frozen_string_literal: true

class BillScoreDistrictsController < ApplicationController
  def show
    render json:
             BillScoreDistrict.includes(:district).where(
               bill_score_id: bill_score_district_params[:bill_score_id]
             ).map(&:to_sway_json),
      status: :ok
  end

  private

  def bill_score_district_params
    params.require(:bill_score_district).permit(:bill_score_id, :district)
  end
end
