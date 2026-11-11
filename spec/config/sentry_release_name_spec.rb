# frozen_string_literal: true

require "rails_helper"

# @lat: [[sentry-release-name-dockerfile-duplication#Why sentryReleaseName.test.ts cares most about the no-value case]]
RSpec.describe "Sentry release name" do
  let(:dockerfile) do
    Rails.root.join("docker", "dockerfiles", "production.alpine.dockerfile").read
  end

  let(:vite_config) { Rails.root.join("vite.config.ts").read }

  # @lat: [[sentry-release-name-dockerfile-duplication#Why the frontend build stage's end marker is the whole command, not just the task name]]
  let(:frontend_build_stage) do
    dockerfile[%r{^FROM gems AS build$.*?\./bin/rails assets:precompile}m]
  end

  it "finds the stage that builds the frontend" do
    expect(frontend_build_stage).to be_present,
      "could not find `FROM gems AS build` and its `./bin/rails assets:precompile` command " \
      "in the production Dockerfile. If the stage was renamed, this whole check stopped running."
  end

  it "hands the commit to the stage that builds the frontend" do
    expect(frontend_build_stage).to include("SWAY_RELEASE_SHA"),
      "the stage that builds the frontend never declares SWAY_RELEASE_SHA, so vite cannot " \
      "read it and every build is filed in Sentry under the name \"undefined\""
  end

  it "reads that same name in the frontend build config" do
    expect(vite_config).to include("sentryReleaseName"),
      "vite.config.ts no longer asks for a release name, so the Dockerfile is passing a " \
      "value nothing reads"
  end

  it "reads the commit from one setting, not two spellings of it" do
    expect(Rails.root.join("vite", "sentryReleaseName.ts").read).to include("SWAY_RELEASE_SHA"),
      "the frontend reads a different setting than the Dockerfile passes"
  end
end
