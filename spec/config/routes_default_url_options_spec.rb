# frozen_string_literal: true

require "rails_helper"

# @lat: [[routes-default-url-options-sync#Development: why config.x.default_url_options is set separately]]
RSpec.describe "config/routes.rb default_url_options" do
  around do |example|
    original_config = Rails.application.config.x.default_url_options
    original_routes = Rails.application.routes.default_url_options

    begin
      example.run
    ensure
      Rails.application.config.x.default_url_options = original_config
      Rails.application.routes.default_url_options = original_routes
      Rails.application.reload_routes!
    end
  end

  it "restores the host a previous reload already discarded" do
    Rails.application.config.x.default_url_options = {
      host: "reload.test",
      port: 4444,
      protocol: "https"
    }
    # The damaged state a server left by the old code is sitting in right now.
    Rails.application.routes.default_url_options = {protocol: "https"}

    Rails.application.reload_routes!

    expect(Rails.application.routes.default_url_options)
      .to include(host: "reload.test", port: 4444)
  end

  it "keeps the host across repeated reloads" do
    Rails.application.config.x.default_url_options = {
      host: "reload.test",
      port: 4444,
      protocol: "https"
    }

    3.times { Rails.application.reload_routes! }

    expect(Rails.application.routes.default_url_options)
      .to include(host: "reload.test", port: 4444)
  end

  it "still applies the protocol when no host is configured" do
    Rails.application.config.x.default_url_options = nil

    Rails.application.reload_routes!

    expect(Rails.application.routes.default_url_options).to include(protocol: "https")
  end
end
