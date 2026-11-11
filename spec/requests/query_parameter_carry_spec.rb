# frozen_string_literal: true

require "rails_helper"
require "navigation_route_exclusions"
require_relative "../../lib/query_parameter_check"

# @lat: [[query-parameter-navigation-carry#Excluded route constants and security boundaries]]
# @lat: [[query-parameter-navigation-carry#Centralized interception mechanism]]
RSpec.describe "Query parameter carry route exclusions and registry integrity", type: :request do
  describe "redirect location carry" do
    # @lat: [[query-parameter-navigation-carry#Query parameter navigation carry#Centralized interception mechanism#Server redirect carry follows real form writes]]
    def post_redirect(path, query: nil, referer: nil, body: {})
      request_path = query.nil? ? path : "#{path}?#{query}"
      headers = {}
      headers["HTTP_REFERER"] = "http://www.example.com#{referer}" if referer
      post request_path, params: body, headers: headers
    end

    def decoded_response_redirect_query_pairs
      URI.decode_www_form(URI.parse(response.location).query.to_s)
    end

    it "carries only request-URL ambient state across features and lets target families win" do
      post_redirect(
        "/__query_parameter_carry/organizations",
        query: "org_tab=members&tab=members&sway_locale_id=42&unknown=drop",
        referer: "/organizations?org_tab=positions"
      )

      expect(response).to have_http_status(:found)
      expect(response.location).to end_with("?org_tab=changes&sway_locale_id=42")
    end

    it "classifies GET navigation from its requested page rather than a conflicting Referer" do
      get "/organizations/__query_parameter_carry_get_redirect?org_tab=members",
        headers: {"HTTP_REFERER" => "http://www.example.com/bills?bills_search=unrelated"}

      expect(response.location).to end_with("?org_tab=members")
    end

    it "classifies HEAD navigation from its requested page rather than a conflicting Referer" do
      head "/organizations/__query_parameter_carry_get_redirect?org_tab=members",
        headers: {"HTTP_REFERER" => "http://www.example.com/bills?bills_search=unrelated"}

      expect(response.location).to end_with("?org_tab=members")
    end

    it "preserves repeated bracketed and plain list values as raw URL pairs" do
      post_redirect(
        "/__query_parameter_carry/creator/12",
        query: "selected_stages%5B%5D=assets&selected_stages%5B%5D=summary&selected_stages=plain-a&selected_stages=plain-b&stages=",
        referer: "/admin/bill_creator/12/pipeline"
      )

      expect(decoded_response_redirect_query_pairs).to include(
        ["selected_stages[]", "assets"], ["selected_stages[]", "summary"],
        ["selected_stages", "plain-a"], ["selected_stages", "plain-b"], ["stages", ""]
      )
    end

    it "does not copy source family values over an explicitly cleared destination family" do
      post_redirect(
        "/__query_parameter_carry/bills_clear",
        query: "bills_search=old&bills_page=4&sway_locale_id=42",
        referer: "/bills?bills_search=old",
        body: {ignored: "body-only"}
      )

      expect(response.location).to end_with("?sway_locale_id=42")
      expect(response.location).not_to include("bills_search", "bills_page", "search=")
    end

    it "ignores request bodies and Referer query values and carries only ambient state from unknown sources" do
      post_redirect(
        "/__query_parameter_carry/organizations",
        query: "org_tab=from-url&sway_locale_id=42",
        referer: "/unregistered/path?org_tab=from-referer",
        body: {org_tab: "from-body"}
      )

      expect(decoded_response_redirect_query_pairs).to contain_exactly(["org_tab", "changes"], ["sway_locale_id", "42"])
      follow_redirect!
      expect(response.body).to end_with("org_tab=changes&sway_locale_id=42")

      post_redirect(
        "/__query_parameter_carry/organizations_plain",
        referer: "/organizations?org_tab=from-referer",
        body: {org_tab: "from-body"}
      )
      expect(URI.parse(response.location).query).to be_nil

      post_redirect(
        "/__query_parameter_carry/bills",
        query: "tab=members&sway_locale_id=42",
        referer: "/organizations?tab=members"
      )
      expect(decoded_response_redirect_query_pairs).to contain_exactly(["sway_locale_id", "42"])
    end

    it "keeps a numeric run pin only when the redirect stays on the same creator bill" do
      post_redirect(
        "/__query_parameter_carry/creator/12",
        query: "run_id=345",
        referer: "/admin/bill_creator/12/pipeline"
      )
      expect(decoded_response_redirect_query_pairs).to include(["run_id", "345"])

      post_redirect(
        "/__query_parameter_carry/creator/13",
        query: "run_id=345",
        referer: "/admin/bill_creator/12/pipeline"
      )
      expect(decoded_response_redirect_query_pairs).not_to include(["run_id", "345"])
    end

    it "uses the requested GET URL when validating its same-bill run pin" do
      get "/admin/bill_creator/12/__query_parameter_carry_get_redirect?run_id=345",
        headers: {"HTTP_REFERER" => "http://www.example.com/admin/bill_creator/13/pipeline"}

      expect(decoded_response_redirect_query_pairs).to include(["run_id", "345"])

      get "/admin/bill_creator/12/__query_parameter_carry_get_redirect?run_id=12%2F34",
        headers: {"HTTP_REFERER" => "http://www.example.com/admin/bill_creator/12/pipeline"}

      expect(decoded_response_redirect_query_pairs).not_to include(["run_id", "12/34"])
    end

    it "uses the requested HEAD URL when validating its same-bill run pin" do
      head "/admin/bill_creator/12/__query_parameter_carry_get_redirect?run_id=345",
        headers: {"HTTP_REFERER" => "http://www.example.com/admin/bill_creator/13/pipeline"}

      expect(decoded_response_redirect_query_pairs).to include(["run_id", "345"])
    end

    it "does not carry a run pin from an external Referer or array-shaped run id" do
      post "/__query_parameter_carry/creator/12?run_id=345",
        headers: {"HTTP_REFERER" => "https://elsewhere.example/admin/bill_creator/12/pipeline"}
      expect(decoded_response_redirect_query_pairs).not_to include(["run_id", "345"])

      post "/__query_parameter_carry/creator/12?run_id%5B%5D=345",
        headers: {"HTTP_REFERER" => "http://www.example.com/admin/bill_creator/12/pipeline"}
      expect(decoded_response_redirect_query_pairs).not_to include(["run_id", "345"])

      post "/__query_parameter_carry/creator/12?run_id=three45",
        headers: {"HTTP_REFERER" => "http://www.example.com/admin/bill_creator/12/pipeline"}
      expect(decoded_response_redirect_query_pairs).not_to include(["run_id", "three45"])
    end

    it "preserves an intentional empty list family and a redirect fragment" do
      post "/__query_parameter_carry/creator/12/empty_list?selected_stages=assets",
        headers: {"HTTP_REFERER" => "http://www.example.com/admin/bill_creator/12/pipeline"}
      expect(decoded_response_redirect_query_pairs).to include(["selected_stages[]", ""])
      expect(response.location).to end_with("#summary")
    end

    it "treats the first empty value as clearing every repeated ordinary value" do
      post_redirect(
        "/__query_parameter_carry/bills",
        query: "bills_search=&bills_search=later&sway_locale_id=42",
        referer: "/bills"
      )
      expect(decoded_response_redirect_query_pairs).to contain_exactly(["sway_locale_id", "42"])

      post "/__query_parameter_carry/bills_repeated_clear?bills_search=source",
        headers: {"HTTP_REFERER" => "http://www.example.com/bills"}
      expect(URI.parse(response.location).query).to be_nil
    end

    it "does not carry query state through any excluded route when the redirect is followed" do
      NavigationRouteExclusions::EXCLUDED_PREFIXES.each do |prefix|
        get "#{prefix}/__query_parameter_carry_probe?sway_locale_id=42&run_id=999"

        expect(response).to have_http_status(:found), prefix
        follow_redirect!
        expect(response.body).to eq("/__query_parameter_carry_target?fixed=target"), prefix
      end

      post "/__query_parameter_carry/excluded_target?sway_locale_id=42",
        headers: {"HTTP_REFERER" => "http://www.example.com/organizations"}
      expect(response.location).to end_with("/sessions/__query_parameter_carry_target?fixed=target")
      follow_redirect!
      expect(response.body).to eq("/sessions/__query_parameter_carry_target?fixed=target")
    end

    it "leaves external, protocol-relative, different-port and non-redirect locations untouched" do
      locations = [
        "https://elsewhere.example/path",
        "//elsewhere.example/path",
        "http://www.example.com:444/path"
      ]
      locations.each do |location|
        post "/__query_parameter_carry/unsafe_location?sway_locale_id=42",
          params: {location: location},
          headers: {"HTTP_REFERER" => "http://www.example.com/organizations"}
        expect(response.location).to eq(location)
      end

      post "/__query_parameter_carry/non_redirect?sway_locale_id=42",
        headers: {"HTTP_REFERER" => "http://www.example.com/organizations"}
      expect(response).to have_http_status(:conflict)
      expect(response.headers["X-Inertia-Location"]).to eq("https://elsewhere.example/path")
    end
  end

  describe "route exclusions boundary" do
    let(:sample_ambient_params) do
      {
        "sway_locale_id" => "42",
        "run_id" => "999",
        "highlight_bill_id" => "123"
      }
    end

    it "ensures every prefix in NavigationRouteExclusions::EXCLUDED_PREFIXES is identified as excluded" do
      NavigationRouteExclusions::EXCLUDED_PREFIXES.each do |prefix|
        expect(NavigationRouteExclusions.excluded_path?(prefix)).to be(true), "Expected #{prefix} to be excluded"
        expect(NavigationRouteExclusions.excluded_path?("#{prefix}/subpath")).to be(true), "Expected #{prefix}/subpath to be excluded"
      end
    end

    it "proves no carried parameter reaches routes in the exclusion constant" do
      test_excluded_endpoints = [
        "/api/v1/bills",
        "/api/health",
        "/sessions/new",
        "/test/sessions",
        "/passkeys",
        "/registrations",
        "/phone_verification",
        "/sway_registration",
        "/users/webauthn/login",
        "/users/passkeys/create"
      ]

      test_excluded_endpoints.each do |path|
        expect(NavigationRouteExclusions.excluded_path?(path)).to be(true)
      end
    end

    it "confirms the frontend navigation.ts exclusion list matches NavigationRouteExclusions::EXCLUDED_PREFIXES" do
      frontend_file = Rails.root.join("app", "frontend", "sway_constants", "navigation.ts")
      expect(frontend_file.exist?).to be true

      content = frontend_file.read
      match = content.match(/export const NAVIGATION_EXCLUDED_ROUTE_PREFIXES = \[(.*?)\] as const;/m)
      expect(match).not_to be_nil
      verified_match = match #: MatchData

      frontend_prefixes = verified_match[1].to_s.scan(/"([^"]+)"/).flatten
      expect(NavigationRouteExclusions::EXCLUDED_PREFIXES).to eq(frontend_prefixes)
    end
  end

  describe "frontend and backend query parameter registry parity" do
    let(:check) { QueryParameterCheck.new(Rails.root.to_s) }
    let(:frontend_registry_content) do
      Rails.root.join("app", "frontend", "sway_constants", "queryParameters.ts").read
    end

    it "ensures all backend global ambient parameters exist in frontend registry" do
      backend_ambient = check.global_ambient
      expect(backend_ambient).to contain_exactly("sway_locale_id", "run_id", "highlight_bill_id")

      backend_ambient.each do |param|
        expect(frontend_registry_content).to include("\"#{param}\"")
      end
    end

    it "ensures all backend canonical feature parameters exist in frontend registry" do
      check.canonical_parameters.each do |feature, params|
        expect(frontend_registry_content).to include("#{feature}:")
        params.each do |param|
          expect(frontend_registry_content).to include("\"#{param}\"")
        end
      end
    end
  end
end
