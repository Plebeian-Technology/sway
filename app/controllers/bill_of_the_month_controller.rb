# frozen_string_literal: true

# @lat: [[bill-of-the-month-no-redirect-on-empty#Why an empty Bill of the Month stays on the page]]
class BillOfTheMonthController < ApplicationController
  skip_before_action :authenticate_sway_user!, only: %i[index]

  def index
    b = Bill.of_the_month(sway_locale: current_sway_locale)

    if b.blank?
      return render_inertia_or_json(page: Pages::BILL_OF_THE_MONTH, props: {bill: nil})
    end

    record_bill_view(b)
    to_render = b.render(current_user, current_sway_locale, district_legislator_names: mobile_api_request?)
    enrich_with_first_legislator!(to_render)

    render_inertia_or_json(page: Pages::BILL_OF_THE_MONTH, props: to_render)
  end

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
