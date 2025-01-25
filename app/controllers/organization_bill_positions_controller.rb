# frozen_string_literal: true

class OrganizationBillPositionsController < ApplicationController
  before_action :verify_is_admin, only: %i[create]

  def index
    if params[:bill_id]
      render json: OrganizationBillPosition.where(bill_id: params[:bill_id]), status: :ok
    elsif params[:organization_id]
      render json: OrganizationBillPosition.where(organization: Organization.find_by(id: params[:organization_id])),
        status: :ok
    else
      render json: [], status: :ok
    end
  end

  def show
    render json: OrganizationBillPosition.find_by(
      bill_id: params[:bill_id],
      organization: Organization.find_by(id: params[:organization_id])
    ), status: :ok
  end

  def create
    if organization_bill_positions_params[:positions].present?
      OrganizationBillPosition.where(bill_id: organization_bill_positions_params[:positions].first[:bill_id]).destroy_all

      render json: OrganizationBillPosition.insert_all!(organization_bill_positions_params[:positions]), status: :ok # rubocop:disable Rails/SkipsModelValidations
    else
      render json: [], status: :no_content
    end
  end

  private

  def organization_bill_positions_params
    params.require(:organization_bill_position).permit(positions: %i[bill_id organization_id support summary])
  end

  def organization_bill_position_params
    params.require(:organization_bill_position).permit(:bill_id, :organization_id, :support, :summary)
  end
end
