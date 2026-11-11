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
end
