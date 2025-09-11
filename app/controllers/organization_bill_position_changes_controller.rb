class OrganizationBillPositionChangesController < ApplicationController
  before_action :set_change, only: %i[update]
  before_action :set_membership, only: %i[update]
  before_action :current_user_must_be_member!

  def update
    unless @membership.admin?
      flash[:alert] = "Forbidden"
      redirect_to user_organization_membership_path(@membership) and return
    end

    if @change.update(approved_by: current_user)
      position.support = @change.new_support
      position.summary = @change.new_summary
      position.save!

      flash[:notice] = "Change approved and position updated."
    else
      Rails.logger.error(change.errors.full_messages)
      flash[:alert] = "Could not approve change."
    end
    redirect_to user_organization_membership_path(@membership)
  end

  private

  def organization
    @organization ||= position.organization
  end

  def position
    @position ||= @change.organization_bill_position
  end

  def set_change
    @change = OrganizationBillPositionChange.find(params[:id])
  end

  def set_membership
    @membership =
      UserOrganizationMembership.find_by(
        organization: organization,
        user: current_user,
      )
  end

  def current_user_must_be_member!
    return if @membership.user_id == current_user.id

    Rails.logger.info(
      "Membership user_id #{@membership.user_id} does not match current_user.id #{current_user.id}",
    )
    flash[:alert] = "Forbidden"
    redirect_to root_path and return
  end
end
