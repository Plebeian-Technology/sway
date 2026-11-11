# frozen_string_literal: true

# @lat: [[user-legislator-emails-controller-notes#Why this controller exists and how it stays idempotent]]
class UserLegislatorEmailsController < ApplicationController
  # @lat: [[user-legislator-emails-controller-notes#Why wrap_parameters lists full_name explicitly]]
  wrap_parameters :user_legislator_email, include: %i[bill_id full_name]

  before_action :set_bill

  rate_limit to: 10, within: 1.hour,
    by: -> { current_user&.id || request.remote_ip },
    only: :create,
    if: -> { RateLimitConfig.enabled?(:legislator_email) },
    with: -> { render_rate_limited },
    store: ApplicationController::RATE_LIMIT_STORE

  def create
    # @lat: [[user-legislator-emails-controller-notes#Why a missing bill redirects instead of returning bare]]
    bill = @bill
    return redirect_to(bills_path, alert: "Bill not found.") if bill.blank?

    target = bill_path(bill.id)

    # @lat: [[user-legislator-emails-controller-notes#Why the user's name is captured inline, in this form]]
    if user_legislator_email_params[:full_name].present? && current_user.full_name.blank?
      unless current_user.update(full_name: user_legislator_email_params[:full_name])
        return respond_failure(:full_name, "Names may only use letters, spaces, commas, periods, apostrophes and hyphens.", target)
      end
    end

    if current_user.full_name.blank?
      return respond_failure(:full_name, "Add your name so your representatives know who is writing.", target)
    end

    unless current_user.email_sendable?
      return respond_failure(:email, "Verify your email address before emailing your representatives.", target)
    end

    emails =
      current_user
        .user_legislators_by_locale(bill.sway_locale)
        .map do |user_legislator|
          UserLegislatorEmail.find_or_create_by({user_legislator:, bill:})
        end

    # @lat: [[user-legislator-emails-controller-notes#Why failed sends are re-enqueued explicitly]]
    emails.select(&:failed?).each do |user_legislator_email|
      OnUserEmailSavedSendEmailToLegislatorJob.perform_later(user_legislator_email)
    end

    redirect_or_json(
      target,
      flash_message: "Sending emails to your representatives. You will be CC'ed on them."
    )
  end

  private

  def respond_failure(field, message, target)
    if mobile_api_request?
      render_error(
        code: "legislator_email_failed",
        message: message,
        status: :unprocessable_content,
        details: {field => message}
      )
    else
      redirect_to(target, inertia: {errors: {field => message}})
    end
  end

  def set_bill
    @bill = Bill.find_by(id: user_legislator_email_params[:bill_id])
  end

  def user_legislator_email_params
    params.require(:user_legislator_email).permit(:bill_id, :full_name)
  end
end
