# frozen_string_literal: true

class BillSummaryReportsController < ApplicationController
  skip_before_action :authenticate_sway_user!, only: :create

  rate_limit to: 5, within: 1.hour,
    by: -> { current_user ? "user:#{current_user.id}" : "ip:#{request.remote_ip}" },
    only: :create,
    if: -> { RateLimitConfig.enabled?(:bill_summary_report) },
    with: -> { render_rate_limited },
    store: ApplicationController::RATE_LIMIT_STORE

  def create
    bill = Bill.find(params[:bill_id])

    report = bill.bill_summary_reports.build(report_params)
    report.user = current_user
    report.ip_address = request.remote_ip
    report.user_agent = request.user_agent&.truncate(255)

    if report.save
      respond_to do |format|
        format.html do
          redirect_back_or_to(bill_path(bill), notice: "Thank you for reporting this summary. Our team will review it.")
        end
        format.json do
          render json: BillSummaryReportResource.new(report).serializable_hash, status: :created
        end
      end
    else
      respond_to do |format|
        format.html do
          redirect_back_or_to(
            bill_path(bill),
            alert: report.errors.full_messages.to_sentence,
            inertia: {errors: report.errors.to_hash}
          )
        end
        format.json do
          render_error(
            code: "validation_failed",
            message: report.errors.full_messages.to_sentence,
            status: :unprocessable_content
          )
        end
      end
    end
  end

  private

  def report_params
    raw = params.require(:bill_summary_report).permit(:reason, :details, :explanation)
    raw[:details] = raw.delete(:explanation) if raw[:explanation].present? && raw[:details].blank?
    raw
  end
end
