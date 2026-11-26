# frozen_string_literal: true

class BillOfTheMonthScheduleController < ApplicationController
  # @lat: [[bill-of-the-month-schedule-admin-guard-order#Bill of the Month schedule: admin guard order and tab redirect default]]
  before_action :verify_is_sway_admin
  before_action :set_bill, only: %i[update]

  include BillCreatorTabRedirects

  DATE_TAKEN_MESSAGE = "Another bill is already scheduled for that date."

  def update
    if @bill.update(
         scheduled_release_date_utc:
           schedule_params[:scheduled_release_date_utc]
       )
      # @lat: [[bootstrap-caching-and-rate-limiting#Why locale and featured bill are cached per locale]]
      Api::V1::BootstrapController.expire_botm_cache(@bill.sway_locale_id)
      notice =
        if @bill.scheduled_release_date_utc.blank?
          "Bill - #{@bill.title} - removed from schedule."
        else
          "Added bill - #{@bill.title} - to schedule."
        end
      respond_after_write(redirect_target, notice: notice)
    else
      respond_after_write(redirect_target, alert: "Failed to update bill schedule.", errors: @bill.errors)
    end
  rescue ActiveRecord::RecordNotUnique
    # @lat: [[mobile-bill-creator#Sections#The schedule section]]
    respond_after_write(
      redirect_target,
      alert: DATE_TAKEN_MESSAGE,
      errors: {scheduled_release_date_utc: ["is already taken"]}
    )
  end

  private

  def redirect_target
    bill_creator_tab_path(
      bill_creator_tab_param(schedule_params),
      bill_id: @bill.id,
      default: :schedule_bill_creator_path
    )
  end

  def schedule_params
    raw = if params.key?(:bill_of_the_month_schedule)
      params.require(:bill_of_the_month_schedule)
    else
      params
    end
    raw.permit(:bill_id, :scheduled_release_date_utc, :bill_creator_tab, :tab_key)
  end
  alias_method :bill_of_the_month_schedule_params, :schedule_params

  def set_bill
    @bill =
      Bill.includes(:sway_locale).find(
        schedule_params[:bill_id]
      )
  end
end
