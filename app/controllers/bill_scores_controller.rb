# frozen_string_literal: true
# typed: true

class BillScoresController < ApplicationController
  skip_before_action :redirect_if_no_current_user, only: %i[show]

  def show
    render json: BillScore.find_by(bill_id: params[:id])&.to_builder_with_user(current_user)&.attributes!, status: :ok
  end

  private

  # Only allow a list of trusted parameters through.
  def bill_score_params
    params.require(:bill_score).permit(:bill_id)
  end
end
