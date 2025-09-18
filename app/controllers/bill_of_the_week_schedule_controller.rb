class BillOfTheWeekScheduleController < ApplicationController
  before_action :set_bill, only: %i[update]

  def update
    if @bill.present?
      if @bill.update(
           scheduled_release_date_utc:
             bill_of_the_week_schedule_params[:scheduled_release_date_utc],
         )
        flash[:notice] = (
          if @bill.scheduled_release_date_utc.blank?
            "Bill - #{@bill.title} - removed from schedule."
          else
            "Added bill - #{@bill.title} - to schedule."
          end
        )
        route_component(
          edit_bill_path(
            @bill.id,
            tab_key: bill_of_the_week_schedule_params[:tab_key],
          ),
        )
      else
        flash[:alert] = "Failed to update bill schedule."
        render_component(Pages::BILL_CREATOR, { errors: @bill.errors })
      end
    else
      flash[:alert] = "Failed to update bill schedule. Bill not found."
      route_component(
        edit_bill_path(
          @bill.id,
          tab_key: bill_of_the_week_schedule_params[:tab_key],
        ),
      )
    end
  end

  private

  def bill_of_the_week_schedule_params
    params.require(:bill_of_the_week_schedule).permit(
      :bill_id,
      :scheduled_release_date_utc,
      :tab_key,
    )
  end

  def set_bill
    @bill =
      Bill.includes(:sway_locale).find(
        bill_of_the_week_schedule_params[:bill_id],
      )
  end
end
