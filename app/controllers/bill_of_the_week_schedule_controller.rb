class BillOfTheWeekScheduleController < ApplicationController
  before_action :set_bill, only: %i[update]

  def update
    redirect_path = @bill.nil? ? new_bill_path : edit_bill_path(@bill.id, tabKey: params[:tab_key])
    new_release = bill_of_the_week_schedule_params[:scheduled_release_date_utc]

    if @bill.present?
      if @bill.update(scheduled_release_date_utc: new_release)
        flash[:notice] = new_release.blank? ? "Bill - #{@bill.title} - removed from schedule." : "Added bill - #{@bill.title} - to schedule."
        redirect_to redirect_path
      else
        flash[:alert] = "Failed to update bill schedule."
        redirect_to redirect_path, inertia: {
          errors: @bill.errors
        }
      end
    else
      flash[:alert] = "Failed to update bill schedule. Bill not found."
      redirect_to redirect_path
    end
  end

  private

  def bill_of_the_week_schedule_params
    params.require(:bill_of_the_week_schedule).permit(:bill_id, :scheduled_release_date_utc, :tab_key)
  end

  def set_bill
    @bill = Bill.includes(:sway_locale).find(bill_of_the_week_schedule_params[:bill_id])
  end
end
