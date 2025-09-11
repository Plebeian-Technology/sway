# frozen_string_literal: true
# typed: true

class Organizations::PositionsController < Organizations::BaseController
  before_action :set_position, only: %i[update destroy]
  before_action :set_change, only: %i[update]
  before_action :change_must_not_be_approved!, only: %i[update]
  before_action :change_must_be_different!, only: %i[update]

  # TODO: Create a position on a bill
  def create
    position =
      OrganizationBillPosition.find_or_initialize_by(
        organization: organization,
        bill_id: params[:bill_id],
      )
    if position.active
      flash[:alert] = "Position for that bill already exists."
      redirect_to_current_user_membership and return
    end

    position.support = params[:support]
    position.summary = OrganizationBillPosition::DEFAULT_SUMMARY

    unless position.save
      flash[:alert] = "Failed to create position."
      Rails.logger.error(position.errors.full_messages)
      redirect_to_current_user_membership and return
    end

    change =
      OrganizationBillPositionChange.find_or_initialize_by(
        organization_bill_position: position,
      )

    change.previous_summary = ""
    change.previous_support = params[:support]
    change.new_support = params[:support]
    change.new_summary = params[:summary]
    change.updated_by = current_user

    if change.save
      flash[:notice] = "Created position, subject to approval."
    else
      Rails.logger.error(change.errors.full_messages)
      flash[:alert] = "Failed to create position."
    end

    redirect_to_current_user_membership(
      tab: "approvals",
      new_position_id: position.id,
    )
  end

  def new
    render_component(
      Pages::NEW_USER_ORGANIZATION_POSITION,
      {
        membership: membership_as_props,
        bills:
          Bill
            .where(sway_locale: organization.sway_locale)
            .where.not(
              {
                id:
                  organization
                    .organization_bill_positions
                    .where(active: true)
                    .select(:bill_id),
              },
            )
            .map(&:to_sway_json),
      },
    )
  end

  def update
    if @change.save
      flash[:notice] = "Created change to position, subject to approval."
    else
      Rails.logger.error(@position.errors.full_messages)
      flash[:alert] = "Failed to save change to position."
    end
    redirect_to_current_user_membership
  end

  def destroy
    if current_user_membership.admin?
      @position.update!(active: false)
      flash[
        :notice
      ] = "Position for bill #{@position.bill.title} de-activated and hidden."
    else
      flash[:alert] = "Forbidden"
    end
    redirect_to_current_user_membership
  end

  private

  def set_position
    @position = OrganizationBillPosition.find(params[:id])
  end

  def set_change
    @change =
      OrganizationBillPositionChange.find_by(
        organization_bill_position: @position,
        updated_by: current_user,
        approved_by_id: nil,
      )
    if @change.present?
      @change.new_support = params[:support]
      @change.new_summary = params[:summary]
      @change.approved_by = nil
    else
      @change =
        OrganizationBillPositionChange.new(
          organization_bill_position: @position,
          updated_by: current_user,
          previous_support: @position.support,
          previous_summary: @position.summary,
          new_support: params[:support],
          new_summary: params[:summary],
        )
    end
  end

  def change_must_not_be_approved!
    return unless @change.approved?

    flash[:notice] = "Change to position has already been approved."
    redirect_to_current_user_membership
  end

  def change_must_be_different!
    if @change.new_support == @position.support &&
         @change.new_summary == @position.summary
      flash[:notice] = "No changes to position detected."
      redirect_to_current_user_membership
    end
  end
end
