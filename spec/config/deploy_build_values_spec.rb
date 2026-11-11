# frozen_string_literal: true

require "rails_helper"
require "erb"
require "yaml"

# @lat: [[deploy-build-value-propagation#Why the build cannot read the deployment file]]
RSpec.describe "deploy values reaching the build and the container" do
  # Where a value can be asked for while production starts. Host-side files
  # (config/deploy*.yml, config/litestream/*) are left out on purpose: they run
  # on the machine doing the deploying, which has the file.
  def boot_paths
    (
      Dir.glob("app/**/*.rb") +
      Dir.glob("lib/**/*.rb") +
      Dir.glob("config/initializers/**/*.rb") +
      ["config/environments/production.rb"]
    ) - ["lib/sway_deploy_config.rb"]
  end

  # Matches a call written across several lines as well as one on a single line.
  # production.rb writes it as `SwayDeployConfig\n  .fetch("RAILS_ALLOWED_HOSTS")`,
  # and a pattern without the \s* silently missed it — which would have made
  # this guard pass while one of the four values was still unhandled.
  def names_asked_for(body)
    body.scan(/SwayDeployConfig\s*\.\s*fetch\(\s*"([A-Z0-9_]+)"/m).flatten +
      body
        .scan(/SwayDeployConfig\s*\.\s*require_values!\(([^)]*)\)/m)
        .flatten
        .flat_map { |args| args.scan(/"([A-Z0-9_]+)"/).flatten }
  end

  def required_at_boot
    Dir.chdir(Rails.root) do
      boot_paths.flat_map { |path| names_asked_for(File.read(path)) }.uniq.sort
    end
  end

  def deploy_config
    YAML.load(ERB.new(Rails.root.join("config", "deploy.yml").read).result, aliases: true)
  end

  # @lat: [[deploy-build-value-propagation#How the spec parses the Dockerfile]]
  def build_stage_instructions
    body = Rails.root.join("docker", "dockerfiles", "production.alpine.dockerfile").read
    stage = body[/^FROM\s+\S+\s+AS\s+build$(.*?)(?=^FROM\s)/mi, 1] ||
      raise("could not find a `FROM ... AS build` stage in the production dockerfile")

    stage.gsub("\\\n", " ").lines.map(&:strip)
  end

  # @lat: [[deploy-build-value-propagation#How the spec parses the Dockerfile]]
  def build_stage_names(instruction)
    build_stage_instructions
      .select { |line| line.start_with?("#{instruction} ") }
      .flat_map { |line| line.scan(/([A-Z0-9_]+)=/).flatten }
      .uniq
  end

  it "declares an ARG and an ENV in the build stage for every value production asks for at boot" do
    args = build_stage_names("ARG")
    envs = build_stage_names("ENV")

    missing_args = required_at_boot - args
    missing_envs = required_at_boot - envs

    expect([missing_args, missing_envs]).to eq([[], []]), <<~MESSAGE
      The build stage of docker/dockerfiles/production.alpine.dockerfile does not
      handle values the application asks for while it starts.

      No ARG: #{missing_args.empty? ? "none" : missing_args.join(", ")}
      No ENV: #{missing_envs.empty? ? "none" : missing_envs.join(", ")}

      Building the assets starts the whole application in production mode, so a
      missing one stops the image build with a Ruby backtrace about four minutes
      in. Each needs BOTH — an ARG with an empty default to accept the value, and
      an ENV to put it where Ruby reads it — plus a matching entry under
      `builder.args` in config/deploy.yml.
    MESSAGE
  end

  it "passes every one of them from config/deploy.yml builder.args" do
    args = deploy_config.dig("builder", "args") || {}

    missing = required_at_boot.reject { |name| args[name].to_s.strip.present? }

    expect(missing).to eq([]), <<~MESSAGE
      config/deploy.yml `builder.args` does not carry a usable value for:

      #{missing.join("\n")}

      An ARG in the Dockerfile with nothing passed to it is an empty string, and
      an empty string reads as absent — so the build fails exactly as it would
      with no ARG at all, one step further along.
    MESSAGE
  end

  it "gives the running container its own copy through env.clear" do
    clear = deploy_config.dig("env", "clear") || {}

    missing = required_at_boot.reject { |name| clear[name].to_s.strip.present? }

    expect(missing).to eq([]), <<~MESSAGE
      config/deploy.yml `env: clear:` does not carry a usable value for:

      #{missing.join("\n")}

      The build settings above stay in the build stage and never reach the final
      image, so the container asks for these again every time it starts. Without
      them the deploy waits out its full timeout and reports only that the
      container never became healthy — the real error sits in the log of a
      container that keeps restarting.
    MESSAGE
  end

  # A value carried as a build setting must not be a credential: build settings
  # are readable by anyone who can read the image, and they show up in
  # `docker history`.
  it "carries no credential as a build setting" do
    args = deploy_config.dig("builder", "args") || {}
    secrets = Array(deploy_config.dig("env", "secret")) + Array(deploy_config.dig("builder", "secrets"))

    overlap = args.keys & secrets

    expect(overlap).to eq([]), <<~MESSAGE
      These are passed as plain build settings AND named as secrets:

      #{overlap.join("\n")}

      A build setting is baked into the image's history and is readable by
      anyone who can read the image. Pass a credential through
      `builder.secrets`, which mounts it for one command and leaves no layer.
    MESSAGE
  end
end
