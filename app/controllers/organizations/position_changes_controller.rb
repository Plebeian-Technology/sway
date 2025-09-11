class Organizations::PositionChangesController < Organizations::BaseController
  before_action :current_user_must_be_admin_to_approve!
  before_action :set_change, only: %i[update]

  def update
    if @change.update(approved_by: current_user)
      position.support = @change.new_support
      position.summary = @change.new_summary
      position.active = true
      position.save!

      flash[:notice] = "Change approved and position updated."
    else
      Rails.logger.error(change.errors.full_messages)
      flash[:alert] = "Could not approve change."
    end
    redirect_to_current_user_membership
  end

  private

  def position
    @position ||= @change.organization_bill_position
  end

  def set_change
    @change = OrganizationBillPositionChange.find(params[:id])
  end

  def current_user_must_be_admin_to_approve!
    return if current_user_membership.admin?

    flash[:alert] = "Forbidden"
    redirect_to_current_user_membership
  end
end
