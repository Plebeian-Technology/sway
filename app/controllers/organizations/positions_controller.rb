# frozen_string_literal: true

# @lat: [[organization-position-change-controller#Position submissions remain proposals until approval]]
class Organizations::PositionsController < Organizations::BaseController
  # @lat: [[organization-position-change-controller#Position submissions remain proposals until approval]]
  before_action :verify_is_active_member!, only: %i[create new update]
  before_action :verify_is_organization_admin!, only: %i[destroy]
  before_action :set_position, only: %i[update destroy]
  before_action :set_change, only: %i[update]
  before_action :change_must_not_be_finalized!, only: %i[update]
  before_action :change_must_be_different!, only: %i[update]

  def create
    bill = Bill.find(params[:bill_id])
    unless bill.sway_locale_id == organization.sway_locale_id
      if request.format.json?
        render_error(
          code: "unprocessable_content",
          message: "Bill does not belong to this organization's locale.",
          status: :unprocessable_content
        )
      else
        flash[:alert] = "Bill does not belong to this organization's locale."
        redirect_to organization_path(organization)
      end
      return
    end

    position =
      OrganizationBillPosition.find_or_initialize_by(
        organization: organization,
        bill_id: params[:bill_id]
      )
    if position.active
      flash[:alert] = "Position for that bill already exists."
      redirect_to_current_user_membership and return
    end

    normalized_support = OrganizationBillPosition.normalize_support(params[:support]) || params[:support]
    was_new_record = position.new_record?
    if was_new_record
      position.support = normalized_support
      position.summary = OrganizationBillPosition::DEFAULT_SUMMARY
    end

    change =
      OrganizationBillPositionChange.new(
        organization_bill_position: position,
        previous_summary: was_new_record ? "" : position.summary,
        previous_support: was_new_record ? normalized_support : position.support,
        new_support: normalized_support,
        new_summary: params[:summary],
        updated_by: current_user
      )

    begin
      ActiveRecord::Base.transaction do
        position.save! if position.new_record? || position.changed?
        change.save!
      end
      flash[:notice] = "Created position, subject to approval."
    rescue ActiveRecord::RecordInvalid => e
      SwayLogging.error(
        "organization_bill_position.create_failed",
        errors: e.record.errors.full_messages
      )
      flash[:alert] = e.record.errors.full_messages.presence&.to_sentence || "Failed to create position."
      redirect_to_current_user_membership and return
    end

    redirect_to_current_user_membership(
      org_tab: "approvals",
      new_position_id: position.id
    )
  end

  def new
    render inertia: Pages::NEW_USER_ORGANIZATION_POSITION,
      props: {
        membership: membership_as_props,
        bills: pickable_bills.map(&:to_sway_json)
      }
  end

  def update
    if @change.save
      flash[:notice] = "Created change to position, subject to approval."
    else
      SwayLogging.error("organization_bill_position.update_failed", errors: @position.errors.full_messages)
      flash[:alert] = "Failed to save change to position."
    end
    redirect_to_current_user_membership
  end

  def destroy
    @position.update!(active: false)
    flash[:notice] = "Position for bill #{@position.bill.title} de-activated and hidden."
    redirect_to_current_user_membership
  end

  private

  # @lat: [[organization-position-change-controller#Position submissions remain proposals until approval]]
  def verify_is_active_member!
    return if current_user_membership&.active?

    if request.format.json?
      render_error(code: "forbidden", message: "Forbidden", status: :forbidden)
    else
      render plain: "Forbidden", status: :forbidden
    end
  end

  # @lat: [[pagination#Search filters the capped list, not the full table]]
  def pickable_bills
    Bill
      .current_session(organization.sway_locale)
      .where.not(
        {
          id:
            organization
              .organization_bill_positions
              .where(active: true)
              .select(:bill_id)
        }
      )
      .includes(:roll_calls, :categories, :sway_locale, :bill_llm_provisioning, :bill_summary_revisions, :legislative_session)
      .order(introduced_date_time_utc: :desc, id: :desc)
      .limit(BillsController::BILLS_INDEX_PAGE_SIZE)
  end

  # @lat: [[organization-position-removal#Position lookup stays within the organization]]
  def set_position
    @position = organization.organization_bill_positions.joins(:bill).find(params[:id])
  end

  # @lat: [[organization-position-change-controller#Position submissions remain proposals until approval]]
  def set_change
    normalized_support = OrganizationBillPosition.normalize_support(params[:support]) || params[:support]
    @change =
      OrganizationBillPositionChange.find_by(
        organization_bill_position: @position,
        updated_by: current_user,
        status: :pending,
        approved_by_id: nil
      )
    if @change.present?
      @change.new_support = normalized_support
      @change.new_summary = params[:summary]
      @change.approved_by = nil
    else
      @change =
        OrganizationBillPositionChange.new(
          organization_bill_position: @position,
          updated_by: current_user,
          previous_support: OrganizationBillPosition.normalize_support(@position.support) || @position.support,
          previous_summary: @position.summary,
          new_support: normalized_support,
          new_summary: params[:summary]
        )
    end
  end

  # @lat: [[organization-position-change-controller#Position submissions remain proposals until approval]]
  def change_must_not_be_finalized!
    return unless @change.finalized?

    flash[:notice] = "Change to position has already been finalized."
    redirect_to_current_user_membership
  end

  def change_must_be_different!
    current_support = OrganizationBillPosition.normalize_support(@position.support) || @position.support
    if @change.new_support == current_support &&
        @change.new_summary == @position.summary
      flash[:notice] = "No changes to position detected."
      redirect_to_current_user_membership
    end
  end
end
