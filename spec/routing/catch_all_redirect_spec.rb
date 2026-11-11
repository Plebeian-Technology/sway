# frozen_string_literal: true

require "rails_helper"

# @lat: [[catch-all-redirect-real-request-testing#Why the "catch-all switched on" example exists separately]]
RSpec.describe "The catch-all redirect", type: :request do
  # The regression guard. Before the fix this answered 301 and the browser
  # followed it to a web page instead of loading a picture. A signed id that
  # resolves to nothing is used on purpose — what is being checked is which
  # route answers, not whether the file is found.
  it "does not redirect a stored-file address, even one that resolves to nothing" do
    get "/rails/active_storage/blobs/proxy/not-a-real-signed-id/x.png"

    expect(response).not_to have_http_status(:moved_permanently)
    expect(response.headers["Location"]).to be_nil
  end

  it "does not redirect an unknown path under the app's own prefixes" do
    ["/rails/nope", "/api/nope", "/vite/nope", "/assets/nope"].each do |path|
      get path

      expect(response).not_to have_http_status(:moved_permanently),
        "#{path} was swallowed by the catch-all instead of failing visibly"
    end
  end

  # @lat: [[bad-request-responses#A path nothing matches stays on this machine]]
  it "does not send a mistyped path anywhere off this machine" do
    get "/definitely-not-a-real-page"

    expect(response).to have_http_status(:not_found)
    expect(response.headers["Location"]).to be_nil
  end

  # The guard that keeps the sentence above true no matter how the destination
  # is worked out. Any redirect a mistyped path produces must stay on the host
  # that was asked, so a future change that reintroduces an outside address
  # fails here by name.
  it "never names an outside host" do
    get "http://www.example.com/definitely-not-a-real-page"

    location = response.headers["Location"]
    next if location.nil?

    expect(URI.parse(location).host).to eq("www.example.com")
  end

  # @lat: [[catch-all-redirect-real-request-testing#Why the "catch-all switched on" example exists separately]]
  describe "with the catch-all switched on, as production has it" do
    around do |example|
      original = Rails.application.config.x.catch_all_enabled
      begin
        Rails.application.config.x.catch_all_enabled = true
        Rails.application.reload_routes!

        example.run
      ensure
        Rails.application.config.x.catch_all_enabled = original
        Rails.application.reload_routes!
      end
    end

    it "sends a mistyped path to the front page of whichever host was asked" do
      {"sway.vote" => "https://sway.vote/", "app.sway.vote" => "https://app.sway.vote/"}
        .each do |asked, expected|
          get "https://#{asked}/definitely-not-a-real-page"

          expect(response).to have_http_status(:moved_permanently)
          expect(response.headers["Location"]).to eq(expected),
            "a reader on #{asked} was sent to #{response.headers["Location"]}"
        end
    end

    # @lat: [[bad-request-responses#A path nothing matches stays on this machine]]
    it "still refuses to swallow the app's own prefixes" do
      ["/rails/nope", "/api/nope", "/vite/nope", "/assets/nope"].each do |path|
        get "https://app.sway.vote#{path}"

        expect(response).not_to have_http_status(:moved_permanently),
          "#{path} was swallowed by the catch-all instead of failing visibly"
      end
    end
  end

  # @lat: [[catch-all-redirect-real-request-testing#Why the "declared for production, and nowhere else" example reads the production file]]
  it "is declared for production, and nowhere else" do
    # @lat: [[catch-all-redirect-real-request-testing#Why the "catch-all switched on" example exists separately]]
    expect(Rails.application.config.x.catch_all_enabled).to be_blank

    production = Rails.root.join("config", "environments", "production.rb").read

    expect(production).to match(/^\s*config\.x\.catch_all_enabled\s*=/)
  end
end
