# frozen_string_literal: true

module Admin
  class PartnerReportsController < ApplicationController
    # @lat: [[partner-article-engagement#Administrative interface]]
    before_action :verify_is_sway_admin

    def index
      organizations = Organization.joins(:article_bills).distinct.order(:name)
      reports = organizations.map do |org|
        report = PartnerEngagementReportService.new(organization: org).call
        PartnerEngagementReportResource.new(report).serializable_hash
      end

      respond_to do |format|
        format.html do
          render_inertia_or_json(
            page: Pages::ADMIN_PARTNER_REPORTS,
            props: {reports: reports}
          )
        end
        format.json do
          render json: reports, status: :ok
        end
      end
    end

    def show
      org = Organization.find_by(id: params[:id]) ||
        Organization.joins(:article_bills).find_by(article_bills: {partner_slug: params[:id]}) ||
        Organization.find(params[:id])

      report = PartnerEngagementReportService.new(organization: org).call
      serialized_report = PartnerEngagementReportResource.new(report).serializable_hash

      respond_to do |format|
        format.html do
          render_inertia_or_json(
            page: Pages::ADMIN_PARTNER_REPORTS,
            props: {report: serialized_report}
          )
        end
        format.json do
          render json: serialized_report, status: :ok
        end
      end
    end
  end
end
