# frozen_string_literal: true

module RecordsBillViews
  extend ActiveSupport::Concern

  private

  def record_bill_view(bill)
    return if current_user.nil? || inertia_partial_reload? || prefetch_request?

    BillView.record_for(user: current_user, bill:)
  end

  def inertia_partial_reload?
    request.headers["X-Inertia-Partial-Data"].present? ||
      request.headers["X-Inertia-Partial-Except"].present? ||
      request.headers["X-Inertia-Partial-Component"].present?
  end

  def prefetch_request?
    request.headers["Purpose"].to_s.casecmp?("prefetch") ||
      request.headers["Sec-Purpose"].to_s.casecmp?("prefetch")
  end
end
