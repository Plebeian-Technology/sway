# frozen_string_literal: true
# typed: true

class BillScoresController < ApplicationController
  skip_before_action :authenticate_sway_user!, only: %i[show]

  def show
    render json:
             BillScore
               .find_by(bill_id: params[:id])
               &.to_builder_with_user(current_user)
               &.attributes!,
           status: :ok
  end
end
