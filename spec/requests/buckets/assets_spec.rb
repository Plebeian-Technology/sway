# frozen_string_literal: true

require "rails_helper"

# @lat: [[buckets-assets-admin-gate-spec#Why Buckets::AssetsController's admin-gate spec tolerates a downstream error]]
RSpec.describe "Buckets::AssetsController admin gate", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  include_examples "requires sway admin",
    verb: :post,
    path: "/buckets/assets",
    params: {name: "test.png", mime_type: "image/png"}

  describe "POST /buckets/assets filename sanitization" do
    let!(:sway_locale) { setup.first }

    it "strips path traversal segments with File.basename before signing" do
      allow_any_instance_of(Buckets::AssetsController) # rubocop:disable RSpec/AnyInstance
        .to receive(:generate_put_signed_url_v4)
        .with(
          bucket_name: SwayGoogleCloudStorage::BUCKETS[:ASSETS],
          file_name: "#{sway_locale.name}/malicious.png",
          content_type: "image/png"
        )
        .and_return("https://storage.googleapis.com/signed-url")

      post "/buckets/assets", params: {asset: {name: "../other-prefix/malicious.png", mime_type: "image/png"}}

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["bucket_file_path"]).to eq("#{sway_locale.name}/malicious.png")
      expect(response.parsed_body["url"]).to eq("https://storage.googleapis.com/signed-url")
    end

    it "rejects blank, '.', '..', or '/' filenames with 422 without signing" do
      expect_any_instance_of(Buckets::AssetsController) # rubocop:disable RSpec/AnyInstance
        .not_to receive(:generate_put_signed_url_v4)

      ["", "   ", ".", "..", "/", "///"].each do |bad_name|
        post "/buckets/assets", params: {asset: {name: bad_name, mime_type: "image/png"}}
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
