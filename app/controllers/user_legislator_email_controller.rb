class UserLegislatorEmailController < ApplicationController
  before_action :set_bill

  def create
    if @bill.present?
      current_user.user_legislators_by_locale(@bill.sway_locale).each do |user_legislator|
        UserLegislatorEmail.create({
          user_legislator:,
          bill: @bill,
          message: user_legislator_email_params[:message]
        })
      end
    end
  end

  private

  def set_bill
    @bill = Bill.find_by(id: user_legislator_email_params[:bill_id])
  end

  def user_legislator_email_params
    params.require(:user_legislator_email).permit(:bill_id, :message)
  end
end
