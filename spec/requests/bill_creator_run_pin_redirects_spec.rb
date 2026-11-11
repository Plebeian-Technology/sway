# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-creator-run-pin-redirect-interceptor#Why a refusal's error messages are pinned alongside the run pin]]
RSpec.describe "Bill Creator redirects keep the pinned run", type: :request do
  include_context "SessionDouble"

  let(:sway_locale) do
    create(:sway_locale, city: "baltimore", state: "maryland",
      country: "united_states")
  end
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:bill) { create(:bill, sway_locale: sway_locale, legislator: legislator) }
  # A second bill in the same jurisdiction needs its own release date: one
  # jurisdiction can only feature one bill per date.
  let(:other_bill) do
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      scheduled_release_date_utc: bill.scheduled_release_date_utc + 7.days
    )
  end
  let(:admin) { create(:user, :sway_admin) }

  before do
    session_hash[:user_id] = admin.id
    cookies_hash[:sway_locale_id] = sway_locale.id
  end

  def summary_address(id, query = nil)
    base = "http://www.example.com/admin/bill_creator/#{id}/summary"
    query ? "#{base}?#{query}" : base
  end

  def generate_summary_from(referer)
    post(
      "/bills/#{bill.id}/generate_summary",
      headers: {"HTTP_REFERER" => referer}
    )
  end

  def redirect_query
    query = URI.parse(response.location).query.to_s
    query.empty? ? {} : URI.decode_www_form(query).to_h
  end

  it "carries the pin from the page the write was sent from" do
    generate_summary_from(summary_address(bill.id, "run_id=77"))

    expect(response).to be_redirect
    expect(redirect_query["run_id"]).to eq("77")
  end

  it "leaves the redirect alone when no run is pinned" do
    generate_summary_from(summary_address(bill.id))

    expect(response).to be_redirect
    expect(redirect_query).not_to have_key("run_id")
  end

  # A run is not scoped to a bill when it is read back, so carrying the pin
  # across bills would show one bill's run under another bill's heading. The
  # browser side drops the pin when the bill changes; this matches it.
  it "does not carry the pin onto a different bill" do
    generate_summary_from(summary_address(other_bill.id, "run_id=77"))

    expect(response).to be_redirect
    expect(redirect_query).not_to have_key("run_id")
  end

  # The value goes straight back into a redirect address, so anything that is
  # not a run id is refused rather than escaped.
  it "refuses a pin that is not a run id" do
    generate_summary_from(summary_address(bill.id, "run_id=%2F%2Fevil.test"))

    expect(response).to be_redirect
    expect(response.location).not_to include("evil.test")
    expect(redirect_query).not_to have_key("run_id")
  end

  it "ignores a referer pointing at another site" do
    generate_summary_from(
      "http://evil.test/admin/bill_creator/#{bill.id}/summary?run_id=77"
    )

    expect(response).to be_redirect
    expect(redirect_query).not_to have_key("run_id")
  end

  # @lat: [[bill-creator-run-pin-redirect-interceptor#Why a refusal's error messages are pinned alongside the run pin]]
  it "keeps a refusal's error messages when the address gains the pin" do
    post(
      "/bills/#{bill.id}/generate_summary",
      headers: {
        "HTTP_REFERER" => summary_address(bill.id, "run_id=77"),
        "X-Inertia" => "true",
        "X-Inertia-Version" => ""
      }
    )

    expect(redirect_query["run_id"]).to eq("77")
    expect(session[:inertia_errors]).to eq({generation: "No pipeline data available"})
  end

  # Redirects that leave the Bill Creator must not grow the parameter: it means
  # nothing outside those screens.
  it "does not add the pin to a redirect away from the Bill Creator" do
    delete(
      "/bills/#{bill.id}",
      headers: {"HTTP_REFERER" => summary_address(bill.id, "run_id=77")}
    )

    expect(response).to be_redirect
    expect(response.location).to include("/admin/bill_creator/new")
    expect(redirect_query).not_to have_key("run_id")
  end
end
