# frozen_string_literal: true

require "rails_helper"

# Unit spec for the concern. It mounts a throwaway controller that includes
# MobileFormatNegotiation and calls each helper directly. The regression check
# that the concern's source contains no `allow_forgery_protection=` assignment
# lives here too.
RSpec.describe MobileFormatNegotiation, type: :controller do
  controller(ActionController::Base) do
    include MobileFormatNegotiation

    def index
      render_inertia_or_json(page: "TestPage", props: {hello: "world"})
    end

    # steep:ignore:start
    def show
      redirect_or_json("/redirected", flash_message: params[:flash])
    end
    # steep:ignore:end

    def predicates
      render json: {
        mobile_api_request: mobile_api_request?,
        bearer_authorization_header: bearer_authorization_header?
      }
    end
  end

  before do
    routes.draw do
      get "/anonymous", to: "anonymous#index"
      get "/anonymous/show", to: "anonymous#show"
      get "/anonymous/predicates", to: "anonymous#predicates"
    end
  end

  describe "#mobile_api_request?" do
    it "returns true for Authorization: Bearer header" do
      request.headers["Authorization"] = "Bearer abc"
      get :predicates
      expect(JSON.parse(response.body)["mobile_api_request"]).to be(true)
    end

    it "returns true for format: :json" do
      get :predicates, format: :json
      expect(JSON.parse(response.body)["mobile_api_request"]).to be(true)
    end

    it "returns false for plain cookie request (HTML)" do
      get :predicates, format: :html
      # The action renders JSON either way, but what matters here is the
      # predicate: a plain HTML request must not be counted as a mobile one.
      expect(JSON.parse(response.body)["mobile_api_request"]).to be(false)
    end
  end

  describe "#bearer_authorization_header?" do
    it "returns true ONLY for Bearer prefix" do
      request.headers["Authorization"] = "Bearer xyz"
      get :predicates
      expect(JSON.parse(response.body)["bearer_authorization_header"]).to be(true)
    end

    it "returns false for json format alone (no Bearer header)" do
      get :predicates, format: :json
      expect(JSON.parse(response.body)["bearer_authorization_header"]).to be(false)
    end

    it "returns false for empty Authorization header" do
      request.headers["Authorization"] = ""
      get :predicates
      expect(JSON.parse(response.body)["bearer_authorization_header"]).to be(false)
    end
  end

  describe "#render_inertia_or_json" do
    it "renders JSON of props for bearer request" do
      request.headers["Authorization"] = "Bearer test"
      get :index
      expect(response.content_type).to include("application/json")
      expect(JSON.parse(response.body)).to eq("hello" => "world")
    end
  end

  describe "#redirect_or_json" do
    it "compacts nil flash out of payload for bearer request" do
      request.headers["Authorization"] = "Bearer test"
      get :show
      body = JSON.parse(response.body)
      expect(body).to eq("redirect" => "/redirected")
      expect(body).not_to have_key("flash")
    end

    it "includes flash key when flash_message present" do
      request.headers["Authorization"] = "Bearer test"
      get :show, params: {flash: "hello"}
      expect(JSON.parse(response.body)).to eq("redirect" => "/redirected", "flash" => "hello")
    end

    it "performs an HTTP redirect for cookie request" do
      get :show
      expect(response).to have_http_status(:redirect)
      expect(response.location).to end_with("/redirected")
    end
  end

  describe "H1 regression: no class-state mutation in concern source" do
    it "does NOT contain `allow_forgery_protection=` anywhere in the concern file" do
      source = Rails.root.join("app", "controllers", "concerns", "mobile_format_negotiation.rb").read
      expect(source).not_to match(/allow_forgery_protection\s*=/)
    end

    it "does NOT define a skip_csrf_for_bearer_requests helper" do
      source = Rails.root.join("app", "controllers", "concerns", "mobile_format_negotiation.rb").read
      expect(source).not_to include("skip_csrf_for_bearer_requests")
    end
  end
end
