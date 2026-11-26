# frozen_string_literal: true

require "rails_helper"

# @lat: [[admin-only-direct-uploads-design#Why the request spec checks blob count, not just status]]
RSpec.describe "Active Storage direct uploads", type: :request do
  include_context "SessionDouble"

  let(:blob_params) do
    {
      blob: {
        filename: "probe.png",
        byte_size: 68,
        checksum: "H7ESx6hNuUxcG4rdsUWb4g==",
        content_type: "image/png"
      }
    }
  end

  it "refuses a caller with no session and writes nothing" do
    expect {
      post "/rails/active_storage/direct_uploads", params: blob_params
    }.not_to change(ActiveStorage::Blob, :count)

    expect(response).to have_http_status(:forbidden)
  end

  it "refuses a signed-in reader who is not an admin" do
    sign_in(create(:user))

    expect {
      post "/rails/active_storage/direct_uploads", params: blob_params
    }.not_to change(ActiveStorage::Blob, :count)

    expect(response).to have_http_status(:forbidden)
  end

  it "lets a signed-in admin through, and answers with the address the browser uploads to" do
    sign_in(create(:user, :sway_admin))

    expect {
      post "/rails/active_storage/direct_uploads", params: blob_params
    }.to change(ActiveStorage::Blob, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("direct_upload", "signed_id")
  end

  # The two files that prompted this could not be traced to anyone, so the log
  # line is the feature, not decoration — assert it is really emitted.
  it "names the admin who uploaded, so a later reader can trace the file" do
    admin = create(:user, :sway_admin)
    sign_in(admin)

    expect(SwayLogging).to receive(:info).with(
      "direct_upload.allowed",
      hash_including(user_id: admin.id, filename: "probe.png")
    )

    post "/rails/active_storage/direct_uploads", params: blob_params
  end

  it "records a refused attempt, since a refusal is the thing worth noticing" do
    expect(SwayLogging).to receive(:warn).with(
      "direct_upload.refused",
      hash_including(:user_id, :filename, :remote_ip)
    )

    post "/rails/active_storage/direct_uploads", params: blob_params
  end

  it "refuses an admin session whose auth_identity does not match user.created_at.to_i" do
    admin = create(:user, :sway_admin)
    sign_in(admin)
    session_hash[:auth_identity] = admin.created_at.to_i - 60

    expect(SwayLogging).to receive(:warn).with(
      "direct_upload.refused",
      hash_including(:user_id, :filename, :remote_ip)
    )

    expect {
      post "/rails/active_storage/direct_uploads", params: blob_params
    }.not_to change(ActiveStorage::Blob, :count)

    expect(response).to have_http_status(:forbidden)
    expect(session_hash[:user_id]).to be_nil
    expect(session_hash[:auth_identity]).to be_nil
  end

  describe "with a bearer token" do
    def bearer_headers(raw_token)
      {"Authorization" => "Bearer #{raw_token}"}
    end

    def api_key_for(bearer, **attributes)
      raw_token = "direct-upload-#{SecureRandom.hex(8)}"
      ApiKey.create!(bearer:, token: raw_token, **attributes)
      raw_token
    end

    context "with forgery protection enabled" do
      around do |example|
        original = ActionController::Base.allow_forgery_protection
        ActionController::Base.allow_forgery_protection = true
        example.run
      ensure
        ActionController::Base.allow_forgery_protection = original
      end

      it "lets a bearer admin through without a CSRF token" do
        admin = create(:user, :sway_admin)
        raw_token = api_key_for(admin)

        expect(SwayLogging).to receive(:info).with(
          "direct_upload.allowed",
          hash_including(user_id: admin.id, filename: "probe.png")
        )

        expect {
          post "/rails/active_storage/direct_uploads", params: blob_params, headers: bearer_headers(raw_token)
        }.to change(ActiveStorage::Blob, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to include("direct_upload", "signed_id")
      end

      it "still enforces CSRF for a cookie-session admin with no Authorization header" do
        sign_in(create(:user, :sway_admin))

        expect {
          post "/rails/active_storage/direct_uploads", params: blob_params
        }.not_to change(ActiveStorage::Blob, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "still enforces CSRF for a cookie-session admin who sends a non-admin bearer token" do
        sign_in(create(:user, :sway_admin))
        raw_token = api_key_for(create(:user))

        expect {
          post "/rails/active_storage/direct_uploads", params: blob_params, headers: bearer_headers(raw_token)
        }.not_to change(ActiveStorage::Blob, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it "refuses a bearer who is not an admin" do
      raw_token = api_key_for(create(:user))

      expect(SwayLogging).to receive(:warn).with(
        "direct_upload.refused",
        hash_including(:user_id, :filename, :remote_ip)
      )

      expect {
        post "/rails/active_storage/direct_uploads", params: blob_params, headers: bearer_headers(raw_token)
      }.not_to change(ActiveStorage::Blob, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses an expired admin token" do
      raw_token = api_key_for(create(:user, :sway_admin), expires_at: 1.hour.ago)

      expect {
        post "/rails/active_storage/direct_uploads", params: blob_params, headers: bearer_headers(raw_token)
      }.not_to change(ActiveStorage::Blob, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses an invalid token" do
      expect {
        post "/rails/active_storage/direct_uploads", params: blob_params, headers: bearer_headers("not-a-real-token")
      }.not_to change(ActiveStorage::Blob, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses an invalid token even when an admin session cookie is present" do
      sign_in(create(:user, :sway_admin))

      expect {
        post "/rails/active_storage/direct_uploads", params: blob_params, headers: bearer_headers("not-a-real-token")
      }.not_to change(ActiveStorage::Blob, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses a valid non-admin token even when an admin session cookie is present" do
      sign_in(create(:user, :sway_admin))
      raw_token = api_key_for(create(:user))

      expect {
        post "/rails/active_storage/direct_uploads", params: blob_params, headers: bearer_headers(raw_token)
      }.not_to change(ActiveStorage::Blob, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses a token whose bearer is not a User" do
      raw_token = api_key_for(create(:organization))

      expect {
        post "/rails/active_storage/direct_uploads", params: blob_params, headers: bearer_headers(raw_token)
      }.not_to change(ActiveStorage::Blob, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
