# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::BaseController, type: :controller do
  controller(Api::V1::BaseController) do
    # steep:ignore:start
    def missing_with_message
      raise ActiveRecord::RecordNotFound, "Record 42 not found"
    end

    def missing_blank_message
      raise ActiveRecord::RecordNotFound, ""
    end

    def public_endpoint?
      true
    end
    # steep:ignore:end
  end

  before do
    routes.draw do
      get :missing_with_message, to: "api/v1/base#missing_with_message"
      get :missing_blank_message, to: "api/v1/base#missing_blank_message"
    end
  end

  describe "RecordNotFound handling" do
    it "renders 404 JSON with the exception message when present" do
      get :missing_with_message

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq(
        "error" => {"code" => "not_found", "message" => "Record 42 not found"}
      )
    end

    it "falls back to a generic not found message when the exception message is blank" do
      get :missing_blank_message

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq(
        "error" => {"code" => "not_found", "message" => "Resource not found"}
      )
    end
  end

  describe "#credential_for_verify" do
    it "returns an empty hash when credential is blank" do
      expect(controller.send(:credential_for_verify, nil)).to eq({})
      expect(controller.send(:credential_for_verify, "")).to eq({})
    end

    it "returns an unsafe hash when given ActionController::Parameters" do
      params = ActionController::Parameters.new(id: "cred-1", type: "public-key")
      expect(controller.send(:credential_for_verify, params)).to eq(
        "id" => "cred-1",
        "type" => "public-key"
      )
    end

    it "returns plain hash credentials unchanged" do
      raw = {id: "cred-1", type: "public-key"}
      expect(controller.send(:credential_for_verify, raw)).to eq(raw)
    end
  end
end
