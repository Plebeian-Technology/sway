class UserLegislatorEmailController < ApplicationController
  before_action :set_bill

  def create
    return if @bill.blank?
    current_user
      .user_legislators_by_locale(@bill.sway_locale)
      .each do |user_legislator|
        UserLegislatorEmail.find_or_create_by({ user_legislator:, bill: @bill })
      end

    redirect_to(bill_path(@bill.id))
  end

  private

  def set_bill
    @bill = Bill.find_by(id: user_legislator_email_params[:bill_id])
  end

  def user_legislator_email_params
    params.require(:user_legislator_email).permit(:bill_id)
  end
end
