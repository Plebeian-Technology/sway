# frozen_string_literal: true

require "rails_helper"
require "support/dockerfile_run_blocks"

# @lat: [[sentry-sourcemap-upload-delete-guard#Why the source-map upload retries on failure]]
RSpec.describe "Sentry source-map upload and deletion guards" do
  let(:vite_config) { Rails.root.join("vite.config.ts").read }
  let(:dockerfile) do
    Rails.root.join("docker", "dockerfiles", "production.alpine.dockerfile").read
  end

  # The line in vite.config.ts that decides whether the Sentry plugin is
  # included at all.
  let(:upload_condition) do
    vite_config[/const uploadsSourceMaps = Boolean\((.*?)\);/m, 1]
  end

  # The `if` in the Dockerfile that decides whether the maps are deleted.
  let(:delete_condition) do
    dockerfile[/^\s*if (\[ -n .*?); then \\$/, 1]
  end

  let(:sentry_variables) { %w[SENTRY_AUTH_TOKEN SENTRY_ORG SENTRY_PROJECT] }

  it "finds both conditions" do
    expect(upload_condition).to be_present,
      "could not find `const uploadsSourceMaps = Boolean(...)` in vite.config.ts"
    expect(delete_condition).to be_present,
      "could not find the `if [ -n ... ]; then` source-map guard in the production Dockerfile"
  end

  it "names all three Sentry variables on the upload side" do
    sentry_variables.each do |name|
      expect(upload_condition).to include(name),
        "vite.config.ts uploads without checking #{name}"
    end
  end

  it "names all three Sentry variables on the deletion side" do
    sentry_variables.each do |name|
      expect(delete_condition).to include(name),
        "the Dockerfile deletes the source maps without checking #{name}, so a build " \
        "missing that value would delete maps that were never uploaded"
    end
  end

  it "tests the same set of variables on both sides" do
    upload = upload_condition or raise "could not find `const uploadsSourceMaps = Boolean(...)` in vite.config.ts"
    delete = delete_condition or raise "could not find the `if [ -n ... ]; then` source-map guard in the production Dockerfile"
    checked_upload = upload #: String
    checked_delete = delete #: String

    uploaded = checked_upload.scan(/SENTRY_[A-Z_]+/).uniq.sort
    deleted = checked_delete.scan(/SENTRY_[A-Z_]+/).uniq.sort

    expect(deleted).to eq(uploaded),
      "the upload condition tests #{uploaded.join(", ")} and the deletion condition " \
      "tests #{deleted.join(", ")}. Whatever is in one list and not the other is a " \
      "build that deletes the source maps after uploading nothing."
  end

  it "requires every variable rather than any one of them" do
    expect(upload_condition).not_to include("||"),
      "vite.config.ts joins the Sentry values with `||`, so a build with only " \
      "one of them would try to half-upload"
    expect(delete_condition).not_to include("-o"),
      "the Dockerfile joins the Sentry values with `-o`, so a build with only one of " \
      "them would delete the source maps"
  end

  # @lat: [[sentry-sourcemap-upload-delete-guard#Why the secrets the asset build reads must be exported]]
  describe "the secrets the asset build reads" do
    let(:asset_build) do
      DockerfileRunBlocks.split(dockerfile).find { |block| block.include?("assets:precompile") }
    end

    let(:secret_reads) do
      asset_build.to_s.scan(%r{^\s*(export\s+)?([A-Z_][A-Z0-9_]*)="\$\(cat /run/secrets/})
    end

    it "finds the block and the secrets it reads" do
      expect(asset_build).to be_present,
        "no RUN block in the production Dockerfile runs assets:precompile, so this checks nothing"
      expect(secret_reads).not_to be_empty,
        "the asset build reads nothing from /run/secrets, so this checks nothing"
    end

    it "exports every one of them" do
      bare = secret_reads.reject { |exported, _name| exported }.map { |_exported, name| name }

      expect(bare).to be_empty,
        "the asset build reads these into a plain shell variable, which no child process " \
        "inherits — so vite cannot see them and uploads nothing: #{bare.join(", ")}"
    end
  end
end
