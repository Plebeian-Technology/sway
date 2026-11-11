# frozen_string_literal: true

class BillSummaryReportResource < ApplicationResource
  attributes :id,
    :bill_id,
    :user_id,
    :reason,
    :details,
    :status,
    :summary_snapshot,
    :summary_ai_unreviewed,
    :resolved_at,
    :admin_notes,
    :created_at,
    :updated_at

  attribute :reporter_display do |report|
    report.reporter_display_name
  end

  attribute :reason_label do |report|
    report.reason_label
  end

  attribute :bill_title do |report|
    report.bill.title
  end

  attribute :bill_external_id do |report|
    report.bill.external_id
  end

  attribute :bill_current_summary do |report|
    report.bill.summary
  end

  attribute :bill_link do |report|
    report.bill.link
  end

  attribute :sway_locale_id do |report|
    report.bill.sway_locale_id
  end

  attribute :sway_locale_name do |report|
    report.bill.sway_locale&.name
  end

  attribute :resolved_by_name do |report|
    report.resolved_by&.full_name.presence || report.resolved_by&.email
  end
end
