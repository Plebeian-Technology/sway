# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-of-the-month-no-redirect-on-empty#Why an empty Bill of the Month stays on the page#Legacy route preservation and query parameter carry]]
RSpec.describe "Retired Bill of the Week paths", type: :request do
  def redirected_query
    Rack::Utils.parse_nested_query(URI(response.headers["Location"]).query)
  end

  it "redirects GET /bill_of_the_week permanently to /bill_of_the_month with the query string" do
    get "/bill_of_the_week?sway_locale_id=2&sort=newest"

    expect(response).to have_http_status(:moved_permanently)
    expect(URI(response.headers["Location"]).path).to eq("/bill_of_the_month")
    expect(redirected_query).to eq("sway_locale_id" => "2", "sort" => "newest")
  end

  it "redirects a bare /bill_of_the_week to /bill_of_the_month without a trailing question mark" do
    get "/bill_of_the_week?"

    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to("/bill_of_the_month")
  end

  it "redirects a trailing-slash /bill_of_the_week/ and keeps the query string" do
    get "/bill_of_the_week/?sway_locale_id=42&with=legislator"

    expect(response).to have_http_status(:moved_permanently)
    expect(URI(response.headers["Location"]).path).to eq("/bill_of_the_month")
    expect(redirected_query).to eq("sway_locale_id" => "42", "with" => "legislator")
  end

  it "keeps nested, array and encoded query values" do
    get "/bill_of_the_week?filter%5Bstatus%5D=active&tags%5B%5D=civic&tags%5B%5D=tax&encoded=foo%20bar%2Bbaz"

    expect(response).to have_http_status(:moved_permanently)
    expect(redirected_query).to eq(
      "filter" => {"status" => "active"},
      "tags" => %w[civic tax],
      "encoded" => "foo bar+baz"
    )
  end

  it "redirects GET /api/bill_of_the_week permanently to /api/bill_of_the_month" do
    get "/api/bill_of_the_week?sway_locale_id=2"

    expect(response).to have_http_status(:moved_permanently)
    expect(URI(response.headers["Location"]).path).to eq("/api/bill_of_the_month")
    expect(redirected_query).to eq("sway_locale_id" => "2")
  end
end
