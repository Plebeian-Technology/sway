# frozen_string_literal: true

require "rails_helper"

# @lat: [[client-caches-and-identity#What the page cache is allowed to hold]]
RSpec.describe "Cache-Control on the responses Sway builds", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:inertia_headers) do
    {
      "X-Inertia" => "true",
      "X-Inertia-Version" => InertiaRails.configuration.version.to_s
    }
  end

  it "marks a page built for a signed-in reader private, and leaves it storable" do
    setup

    get notifications_path, headers: inertia_headers

    expect(response.headers["Cache-Control"]).to eq(ApplicationController::PRIVATE_CACHE_CONTROL)
    expect(response.headers["Cache-Control"]).to include("private")
    expect(response.headers["Cache-Control"]).not_to include("no-store")
  end

  it "still forbids storing the one response carrying a one-time secret" do
    setup

    post "/api_keys", params: {}
    follow_redirect!

    expect(response.headers["Cache-Control"]).to eq("no-store")
  end

  it "keeps the public max-age the association files serve themselves" do
    host! "app.example.test"

    with_app_config(:mobile, apple_team_id: "ABCDE12345", apple_bundle_id: "app.example.test", app_association_hosts: "app.example.test") do
      get "/.well-known/apple-app-site-association"
    end

    expect(response.headers["Cache-Control"]).to include("public")
    expect(response.headers["Cache-Control"]).to include("max-age=3600")
    expect(response.headers["Cache-Control"]).not_to include("private")
  end

  it "leaves a signed-out page as it was" do
    get "/", headers: inertia_headers

    expect(response.headers["Cache-Control"]).to eq("max-age=0, private, must-revalidate")
  end
end
