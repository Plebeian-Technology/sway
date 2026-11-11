# frozen_string_literal: true

class OrganizationBillPositionsController < ApplicationController
  include BillCreatorTabRedirects

  # @lat: [[organization-position-removal#Removal is recorded where the other decisions are]]
  LoggedPosition = Struct.new(:id, :organization_name)

  # @lat: [[organization-position-removal#Organization position admin endpoints expose drafts]]
  before_action :verify_is_sway_admin

  def index
    # @lat: [[system-shape#One process, two languages#Why a payload goes through a resource rather than the record]]
    if params[:bill_id]
      positions = OrganizationBillPosition.joins(:bill).where(bill_id: params[:bill_id])
      render json: OrganizationBillPositionResource.new(positions).serializable_hash,
        status: :ok
    elsif params[:organization_id]
      positions =
        OrganizationBillPosition.joins(:bill).where(
          organization: Organization.find_by(id: params[:organization_id])
        )
      render json: OrganizationBillPositionResource.new(positions).serializable_hash,
        status: :ok
    else
      empty_payload = []
      # @type var empty_payload: Array[untyped]
      render json: empty_payload, status: :ok
    end
  end

  def show
    position =
      OrganizationBillPosition.joins(:bill).find_by(
        bill_id: params[:bill_id],
        organization: Organization.find_by(id: params[:organization_id])
      )
    # @lat: [[organization-position-removal#Organization position JSON preserves its empty shapes]]
    render json: position && OrganizationBillPositionResource.new(position).serializable_hash,
      status: :ok
  end

  # @lat: [[organization-position-removal#Bulk position writes stay behind the service boundary]]
  def create
    result = ReplaceBillOrgPositionsService.call(
      positions: organization_bill_positions_params[:positions],
      actor: current_user
    )

    if result.ok?
      render json: result.payload, status: :ok
    elsif result.empty?
      head :no_content
    else
      # @lat: [[organization-position-removal#Bulk position writes stay behind the service boundary]]
      render_error(
        code: result.error.to_s,
        message: result.message.to_s,
        status: result.http_status || :unprocessable_content
      )
    end
  end

  # @lat: [[organization-position-removal#Removal deactivates, it does not delete]]
  def destroy
    position = OrganizationBillPosition.joins(:bill).find_by(id: params[:id])
    if position.nil?
      return render_error(
        code: "not_found",
        message: "Organization position not found.",
        status: :not_found
      )
    end

    bill = position.bill

    # @lat: [[organization-position-removal#Removal is recorded where the other decisions are]]
    if position.active?
      position.update!(active: false)
      PipelineActivityLogger.log_org_position_decision!(
        bill: bill,
        draft: LoggedPosition.new(position.id.to_s, position.organization.name.to_s),
        decision: :removed,
        actor: current_user
      )
    end

    redirect_to bill_creator_tab_path(
      bill_creator_tab_param,
      bill_id: bill.id,
      default: :positions_bill_creator_path,
      event_key: "organizations"
    ),
      notice: "Removed #{position.organization.name} from #{bill.external_id}."
  end

  private

  def organization_bill_positions_params
    params.require(:organization_bill_position).permit(
      positions: %i[bill_id organization_id support summary]
    )
  end
end
