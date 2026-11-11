class Organizations::PositionChangesController < Organizations::BaseController
  # @lat: [[position-change-response-shaping#Why the message constant exists]]
  ALREADY_FINALIZED_MESSAGE = "Change is already finalized."

  before_action :verify_is_organization_admin!
  before_action :set_change, only: %i[update destroy]

  # @lat: [[position-change-response-shaping#Why ApprovePositionChangeService and RejectPositionChangeService re-read the row under a lock]]
  def update
    case ApprovePositionChangeService.new(change: @change, approver: current_user).call
    when :already_finalized
      respond_already_finalized
    when :approve_failed
      # @lat: [[position-change-response-shaping#Why the mobile/web response split is hand-written instead of redirect_or_json]]
      if mobile_api_request?
        render_error(code: "approve_failed", message: "Could not approve change.", status: :unprocessable_content)
      else
        flash[:alert] = "Could not approve change."
        redirect_to_current_user_membership
      end
    else
      # @lat: [[position-change-response-shaping#Why the mobile/web response split is hand-written instead of redirect_or_json]]
      if mobile_api_request?
        head :no_content
      else
        flash[:notice] = "Change approved and position updated."
        redirect_to_current_user_membership
      end
    end
  end

  # @lat: [[position-change-response-shaping#Why the mobile/web response split is hand-written instead of redirect_or_json]]
  def destroy
    if RejectPositionChangeService.new(change: @change, rejecter: current_user).call == :already_finalized
      respond_already_finalized
      return
    end

    # @lat: [[position-change-response-shaping#Why the rejection audit log line exists and logs named fields]]
    SwayLogging.info(
      "organization_bill_position_change.soft_rejected",
      change_id: @change.id,
      rejected_by_user_id: current_user.id,
      organization_id: organization.id
    )

    # @lat: [[position-change-response-shaping#Why the mobile/web response split is hand-written instead of redirect_or_json]]
    if mobile_api_request?
      head :no_content
    else
      flash[:notice] = "Change rejected."
      redirect_to_current_user_membership
    end
  end

  private

  # @lat: [[position-change-response-shaping#Why the mobile/web response split is hand-written instead of redirect_or_json]]
  def respond_already_finalized
    if mobile_api_request?
      render_error(code: "already_finalized", message: ALREADY_FINALIZED_MESSAGE, status: :unprocessable_content)
    else
      flash[:alert] = ALREADY_FINALIZED_MESSAGE
      redirect_to_current_user_membership
    end
  end

  # @lat: [[organization-position-removal#Position lookup stays within the organization]]
  def set_change
    @change = OrganizationBillPositionChange
      .joins(organization_bill_position: :bill)
      .where(organization_bill_positions: {organization_id: params[:organization_id]})
      .find(params[:id])
  end
end
