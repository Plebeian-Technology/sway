class OrganizationBillPositionsController < ApplicationController
  before_action :verify_is_admin, only: %i[create]

  def index
    render json: Organization.where(organization_id: organization_bill_position_params[:organization_id]), status: :ok
  end

  def show
    render json: Organization.find_by(
      bill_id: organization_bill_position_params[:bill_id],
      organization_id: organization_bill_position_params[:organization_id]
    ), status: :ok
  end

  def create
    render json: Organization.find_or_create_by(organization_bill_position_params), status: :ok
  end

  private

  def organization_bill_position_params
    params.require(:organization).permit(:bill_id, :organization_id, :support, :summary)
  end
end
