# frozen_string_literal: true

require "rails_helper"
require "navigation_route_exclusions"

# @lat: [[query-parameter-navigation-carry#Excluded route constants and security boundaries]]
RSpec.describe NavigationRouteExclusions, type: :request do
  describe "EXCLUDED_PREFIXES constant" do
    it "defines the frozen list of excluded route prefixes" do
      expect(described_class::EXCLUDED_PREFIXES).to be_frozen
      expect(described_class::EXCLUDED_PREFIXES).to contain_exactly(
        "/api/v1",
        "/api",
        "/sessions",
        "/test/sessions",
        "/passkeys",
        "/registrations",
        "/phone_verification",
        "/sway_registration",
        "/users/webauthn",
        "/users/passkeys"
      )
    end

    it "matches the TypeScript frontend NAVIGATION_EXCLUDED_ROUTE_PREFIXES constant" do
      frontend_nav_path = Rails.root.join("app", "frontend", "sway_constants", "navigation.ts")
      expect(File.exist?(frontend_nav_path)).to be true

      content = File.read(frontend_nav_path)
      match = content.match(/export const NAVIGATION_EXCLUDED_ROUTE_PREFIXES = \[(.*?)\] as const;/m)
      expect(match).not_to be_nil

      frontend_prefixes = match ? match[1].scan(/"([^"]+)"/).flatten : []
      expect(described_class::EXCLUDED_PREFIXES).to eq(frontend_prefixes)
    end
  end

  describe ".excluded_path?" do
    describe "Rails routes verification against config/routes.rb" do
      it "identifies all /api/v1 mobile routes as excluded" do
        all_routes = Rails.application.routes.routes
        v1_routes = all_routes.select { |r| r.path.spec.to_s.start_with?("/api/v1") }
        expect(v1_routes).not_to be_empty

        v1_routes.each do |route|
          path = route.path.spec.to_s.sub(/\(\.:format\)\z/, "")
          expect(described_class.excluded_path?(path)).to be(true), "Expected #{path} to be excluded"
        end
      end

      it "identifies all /api web API routes as excluded" do
        all_routes = Rails.application.routes.routes
        api_routes = all_routes.select do |r|
          spec = r.path.spec.to_s
          spec.start_with?("/api/") || spec == "/api(.:format)"
        end
        expect(api_routes).not_to be_empty

        api_routes.each do |route|
          path = route.path.spec.to_s.sub(/\(\.:format\)\z/, "")
          expect(described_class.excluded_path?(path)).to be(true), "Expected #{path} to be excluded"
        end
      end

      it "identifies auth and registration routes as excluded" do
        all_routes = Rails.application.routes.routes
        auth_routes = all_routes.select do |r|
          spec = r.path.spec.to_s
          spec.start_with?("/sessions", "/test/sessions", "/passkeys", "/registrations",
            "/phone_verification", "/sway_registration",
            "/users/webauthn", "/users/passkeys")
        end
        expect(auth_routes).not_to be_empty

        auth_routes.each do |route|
          path = route.path.spec.to_s.sub(/\(\.:format\)\z/, "")
          expect(described_class.excluded_path?(path)).to be(true), "Expected #{path} to be excluded"
        end
      end

      it "does NOT exclude standard navigation routes" do
        standard_paths = [
          "/",
          "/bills",
          "/bills/123",
          "/bills/123/summary_reports",
          "/bill_of_the_month",
          "/legislators",
          "/legislators/1",
          "/notifications",
          "/influence",
          "/public/organizations",
          "/public/organizations/45",
          "/admin",
          "/admin/bill_creator/new",
          "/admin/bill_creator/1/pipeline",
          "/admin/bill_creator/1/summary",
          "/admin/bill_creator/1/positions",
          "/admin/bill_creator/1/schedule",
          "/admin/categories",
          "/admin/llm_settings",
          "/admin/bill_summary_reports",
          "/admin/registration_funnel",
          "/settings",
          "/users/preferences",
          "/users/organization_memberships",
          "/api_keys",
          "/download",
          "/privacy",
          "/sms",
          "/terms"
        ]

        standard_paths.each do |path|
          expect(described_class.excluded_path?(path)).to be(false), "Expected #{path} NOT to be excluded"
        end
      end
    end

    describe "edge cases" do
      it "handles trailing slashes, nested endpoints, query strings, and hashes" do
        expect(described_class.excluded_path?("/api/v1/")).to be true
        expect(described_class.excluded_path?("/sessions/")).to be true
        expect(described_class.excluded_path?("/bills/")).to be false
        expect(described_class.excluded_path?("/api/v1/sessions/challenge?redirect=1#auth")).to be true
        expect(described_class.excluded_path?("/bills?tab=all&sort=date#top")).to be false
        expect(described_class.excluded_path?("https://sway.vote/api/v1/bootstrap")).to be true
        expect(described_class.excluded_path?("http://localhost:3333/bills/101")).to be false
        expect(described_class.excluded_path?("")).to be false
        expect(described_class.excluded_path?(nil)).to be false
      end
    end

    describe "mutation coverage checks" do
      it "fails if any required namespace is omitted from the constant" do
        all_routes = Rails.application.routes.routes

        described_class::EXCLUDED_PREFIXES.each do |prefix|
          mutated_prefixes = described_class::EXCLUDED_PREFIXES - [prefix]

          routes_for_prefix = all_routes.select do |r|
            spec = r.path.spec.to_s.sub(/\(\.:format\)\z/, "")
            (spec == prefix || spec.start_with?("#{prefix}/")) &&
              mutated_prefixes.none? { |other| spec == other || spec.start_with?("#{other}/") }
          end

          if routes_for_prefix.any?
            sample_path = routes_for_prefix.first.path.spec.to_s.sub(/\(\.:format\)\z/, "")
            covered = mutated_prefixes.any? { |p| sample_path == p || sample_path.start_with?("#{p}/") }
            expect(covered).to be false
          end
        end
      end

      it "covers dynamically added throwaway routes inside excluded namespaces" do
        throwaway_api_route = "/api/v1/throwaway_probe"
        throwaway_auth_route = "/users/webauthn/sessions/throwaway_callback"
        throwaway_nav_route = "/bills/throwaway_page"

        expect(described_class.excluded_path?(throwaway_api_route)).to be true
        expect(described_class.excluded_path?(throwaway_auth_route)).to be true
        expect(described_class.excluded_path?(throwaway_nav_route)).to be false
      end
    end
  end
end
