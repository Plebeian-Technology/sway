# frozen_string_literal: true

require "rails_helper"

# @lat: [[cloudflare-trusted-proxies#Why spec/requests/force_ssl_spec.rb checks config files and deleted methods, not live HTTPS behavior]]

RSpec.describe "HTTPS enforcement", type: :request do
  describe "production.rb configuration source" do
    let(:config_src) { Rails.root.join("config", "environments", "production.rb").read }

    it "force_ssl is true inside the DISABLE_FORCE_SSL guard" do
      expect(config_src).to match(/ENV\["DISABLE_FORCE_SSL"\]\s*==\s*"true"/)
      expect(config_src).to include("config.force_ssl = true")
    end

    it "ssl_options disables redirect (Cloudflare handles it, no loop)" do
      expect(config_src).to include("redirect: false")
    end

    it "HSTS is configured with 1.year, includeSubDomains, no preload" do
      expect(config_src).to match(/expires: 1\.year/)
      expect(config_src).to include("subdomains: true")
      expect(config_src).to include("preload: false")
    end

    it "secure_cookies is enabled" do
      expect(config_src).to include("secure_cookies: true")
    end

    it "delegates trusted_proxies to the cloudflare-rails gem, not a static list" do
      # The hand-kept config/cloudflare_ips.txt file and the manual
      # trusted_proxies block are gone. The cloudflare-rails gem now looks up
      # Cloudflare's address ranges itself. production.rb must mention neither.
      expect(config_src).not_to include("cloudflare_ips.txt")
      expect(config_src).not_to include("action_dispatch.trusted_proxies")
    end
  end

  describe "Cloudflare proxy trust via cloudflare-rails" do
    it "the static config/cloudflare_ips.txt artifact has been removed" do
      expect(Rails.root.join("config", "cloudflare_ips.txt")).not_to be_exist
    end

    it "the cloudflare-rails gem is declared in the production group as the trusted-proxy source" do
      # @lat: [[cloudflare-trusted-proxies#Why spec/requests/force_ssl_spec.rb checks config files and deleted methods, not live HTTPS behavior]]
      production_group = Rails.root.join("Gemfile").read[/group :production do(.*?)^end/m, 1] || ""
      expect(production_group).to match(/gem ["']cloudflare-rails["']/)
    end
  end

  describe "DISABLE_FORCE_SSL kill switch" do
    around do |example|
      previous = ENV["DISABLE_FORCE_SSL"]
      begin
        ENV["DISABLE_FORCE_SSL"] = "true"
        example.run
      ensure
        if previous.nil?
          ENV.delete("DISABLE_FORCE_SSL")
        else
          ENV["DISABLE_FORCE_SSL"] = previous
        end
      end
    end

    it "ENV guard pattern is present in production config source" do
      # Flipping force_ssl for real needs an app reboot, which RSpec cannot do
      # cheaply. Reading the config source here, plus a manual check on a
      # preview deploy, covers it.
      config_src = Rails.root.join("config", "environments", "production.rb").read
      expect(config_src).to match(/if ENV\["DISABLE_FORCE_SSL"\] == "true"/)
      expect(config_src).to include("config.force_ssl = false")
      expect(config_src).to include("config.force_ssl = true")
    end
  end

  describe "redirect_to_https_if_needed deletion" do
    it "no longer exists as a private method on ApplicationController" do
      expect(ApplicationController.private_instance_methods).not_to include(:redirect_to_https_if_needed)
    end

    it "is not defined in application_controller.rb source" do
      app_src = Rails.root.join("app", "controllers", "application_controller.rb").read
      expect(app_src).not_to match(/def\s+redirect_to_https_if_needed/)
    end

    it "before_action is not registered in application_controller.rb source" do
      app_src = Rails.root.join("app", "controllers", "application_controller.rb").read
      expect(app_src).not_to match(/before_action\s+:redirect_to_https_if_needed/)
    end
  end

  describe "pre-existing rate limit baseline preserved (plan 23-04)" do
    it "ApplicationController still includes RateLimitResponder" do
      expect(ApplicationController.ancestors).to include(RateLimitResponder)
    end

    it "ApplicationController source still has the 1000/min domain baseline rate_limit" do
      app_src = Rails.root.join("app", "controllers", "application_controller.rb").read
      expect(app_src).to include("rate_limit(to: 1000, within: 1.minute")
    end
  end
end
