# frozen_string_literal: true

require "rails_helper"
require "yaml"

# @lat: [[compose-secrets-root-worktree-indirection#Why compose.yml env_file paths read through SWAY_SECRETS_ROOT]]
RSpec.describe ".dockerdev/compose.yml env_file paths" do
  # [service name, declared env_file path] for every service that reads one.
  let(:compose_env_files) do
    path = Rails.root.join(".dockerdev", "compose.yml")
    services = YAML.safe_load_file(path, aliases: true).fetch("services")
    services.flat_map do |name, service|
      # A service may declare one path or several, and most declare none.
      declared = service["env_file"]
      entries = declared.is_a?(Array) ? declared : [declared].compact
      entries.map { |entry| [name.to_s, entry.to_s] }
    end
  end

  it "finds env_file entries to check" do
    # A scan that read nothing looks exactly like one that found nothing wrong.
    expect(compose_env_files).not_to be_empty
  end

  it "reads every env file through the secrets root" do
    bare = compose_env_files.reject { |_service, entry| entry.include?("SWAY_SECRETS_ROOT") }

    expect(bare).to be_empty,
      "these env_file paths resolve only in the main checkout, so a phase " \
      "worktree cannot run them:\n" + bare.map { |service, entry| "  #{service}: #{entry}" }.join("\n")
  end
end

# @lat: [[run-the-stack#Working in a phase worktree]]
RSpec.describe "deploy/config/sway.env inside the container" do
  let(:compose_services) do
    path = Rails.root.join(".dockerdev", "compose.yml")
    YAML.safe_load_file(path, aliases: true).fetch("services")
  end

  let(:deploy_config_mounts) do
    compose_services.flat_map do |name, service|
      volumes = Array(service["volumes"]) #: Array[untyped]
      volumes.map(&:to_s)
        .select { |entry| entry.include?(":/app/deploy/config/sway.env") }
        .map { |entry| [name.to_s, entry] }
    end
  end

  it "mounts it into every service that boots Rails" do
    mounted = deploy_config_mounts.map(&:first)

    expect(mounted).to include("rails", "rspec", "web", "jobs")
  end

  it "takes the mount source from a variable, so a worktree can point it elsewhere" do
    bare = deploy_config_mounts.reject { |_service, entry| entry.start_with?("${SWAY_DEPLOY_CONFIG_SRC") }

    expect(bare).to be_empty,
      "these mounts resolve only in the main checkout:\n" +
        bare.map { |service, entry| "  #{service}: #{entry}" }.join("\n")
  end

  it "falls back to this checkout's own file, leaving the main checkout as it was" do
    expect(deploy_config_mounts).to all(
      include(a_string_including("${SWAY_DEPLOY_CONFIG_SRC:-../deploy/config/sway.env}"))
    )
  end

  it "mounts it read-only, so nothing in a container can rewrite the operator's values" do
    writable = deploy_config_mounts.reject { |_service, entry| entry.end_with?(":ro") }

    expect(writable).to be_empty
  end

  it "is written by the script that already redirects the env files" do
    script = Rails.root.join("scripts", "dip", "secrets-root.sh").read

    expect(script).to include("SWAY_DEPLOY_CONFIG_SRC=")
    expect(script).to include("deploy/config/sway.env")
  end
end

# @lat: [[run-the-stack#Git inside a worktree's container]]
RSpec.describe "git inside a container" do
  let(:compose_services) do
    path = Rails.root.join(".dockerdev", "compose.yml")
    YAML.safe_load_file(path, aliases: true).fetch("services")
  end

  let(:git_mounts) do
    compose_services.flat_map do |name, service|
      volumes = Array(service["volumes"]) #: Array[untyped]
      volumes.map(&:to_s)
        .select { |entry| entry.include?("SWAY_GIT_COMMON") }
        .map { |entry| [name.to_s, entry] }
    end
  end

  it "mounts the git common directory into every service that boots Rails" do
    expect(git_mounts.map(&:first)).to include("rails", "rspec", "web", "jobs")
  end

  it "mounts it at the same absolute path it came from, which is what the .git pointer names" do
    expect(git_mounts).to all(
      include(a_string_including("${SWAY_GIT_COMMON_SRC:-../.git}:${SWAY_GIT_COMMON_AT:-"))
    )
  end

  it "mounts it read-only, so no container can rewrite the main checkout's object store" do
    writable = git_mounts.reject { |_service, entry| entry.end_with?(":ro") }

    expect(writable).to be_empty
  end

  it "names both halves of the mount in the script that writes them" do
    script = Rails.root.join("scripts", "dip", "secrets-root.sh").read

    expect(script).to include("SWAY_GIT_COMMON_SRC=")
    expect(script).to include("SWAY_GIT_COMMON_AT=")
  end

  it "trusts the repository, since the container runs as root over host-owned files" do
    rspec_env = compose_services.fetch("rspec").fetch("environment")

    expect(rspec_env["GIT_CONFIG_COUNT"]).to eq("1")
    expect(rspec_env["GIT_CONFIG_KEY_0"]).to eq("safe.directory")
    expect(rspec_env["GIT_CONFIG_VALUE_0"]).to eq("*")
  end
end
