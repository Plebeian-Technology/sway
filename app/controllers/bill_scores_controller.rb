# typed: true

class BillScoresController < ApplicationController


  # GET /bill_scores/1 or /bill_scores/1.json
  def show
    render json: BillScore.find_by(bill_id: params[:id])&.to_builder&.target!, status: :ok
  end

  private

  # Only allow a list of trusted parameters through.
  def bill_score_params
    params.require(:bill_score).permit(:bill_id)
  end
end
