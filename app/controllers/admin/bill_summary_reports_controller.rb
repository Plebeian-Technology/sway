# frozen_string_literal: true

module Admin
  class BillSummaryReportsController < ApplicationController
    before_action :verify_is_sway_admin
    before_action :set_report, only: %i[show update]

    def index
      reports = BillSummaryReport.joins(:bill).includes(:user, :resolved_by, bill: :sway_locale).recent_first

      if params[:status].present? && params[:status] != "all" && BillSummaryReport.statuses.key?(params[:status])
        reports = reports.where(status: params[:status])
      end

      if params[:locale_id].present?
        reports = reports.joins(:bill).where(bills: {sway_locale_id: params[:locale_id]})
      elsif params[:sway_locale_id].present?
        reports = reports.joins(:bill).where(bills: {sway_locale_id: params[:sway_locale_id]})
      end

      if params[:bill_id].present?
        reports = reports.where(bill_id: params[:bill_id])
      end

      serialized_reports = BillSummaryReportResource.new(reports).serializable_hash

      props = {
        reports: serialized_reports,
        filter_status: params[:status].presence || "all",
        filter_locale_id: params[:locale_id].presence || params[:sway_locale_id].presence,
        locales: SwayLocale.all.map { |l| {id: l.id, name: l.name} },
        status_counts: {
          all: BillSummaryReport.joins(:bill).count,
          pending: BillSummaryReport.joins(:bill).pending.count,
          reviewed: BillSummaryReport.joins(:bill).reviewed.count,
          resolved: BillSummaryReport.joins(:bill).resolved.count,
          dismissed: BillSummaryReport.joins(:bill).dismissed.count
        }
      }

      respond_to do |format|
        format.html do
          render_inertia_or_json(page: Pages::ADMIN_BILL_SUMMARY_REPORTS, props: props)
        end
        format.json do
          render json: props, status: :ok
        end
      end
    end

    def show
      serialized_report = BillSummaryReportResource.new(@report).serializable_hash
      respond_to do |format|
        format.html do
          render_inertia_or_json(page: Pages::ADMIN_BILL_SUMMARY_REPORTS, props: {report: serialized_report})
        end
        format.json do
          render json: serialized_report, status: :ok
        end
      end
    end

    def update
      attrs = report_params

      if attrs[:status].present?
        case attrs[:status].to_s
        when "resolved", "dismissed"
          @report.resolved_by = current_user
          @report.resolved_at = Time.current
        when "pending", "reviewed"
          @report.resolved_by = nil
          @report.resolved_at = nil
        end
      end

      if @report.update(attrs)
        respond_to do |format|
          format.html do
            redirect_to admin_bill_summary_reports_path, notice: "Report ##{@report.id} updated."
          end
          format.json do
            render json: BillSummaryReportResource.new(@report).serializable_hash, status: :ok
          end
        end
      else
        respond_to do |format|
          format.html do
            redirect_back_or_to(admin_bill_summary_reports_path, alert: @report.errors.full_messages.to_sentence)
          end
          format.json do
            render_error(code: "validation_failed", message: @report.errors.full_messages.to_sentence, status: :unprocessable_content)
          end
        end
      end
    end

    private

    def set_report
      @report = BillSummaryReport.joins(:bill).find(params[:id])
    end

    def report_params
      params.require(:bill_summary_report).permit(:status, :admin_notes)
    end
  end
end
