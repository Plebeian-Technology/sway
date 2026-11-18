# frozen_string_literal: true

require "rails_helper"
require "erb"
require "yaml"

# @lat: [[release-git-fallback-and-caching#Why config/deploy.yml's release build args are wrapped in single quotes]]
RSpec.describe "config/deploy.yml release build args" do
  it "renders all four SWAY_* args as strings (no YAML Time/nil coercion)" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SWAY_RELEASE_VERSION").and_return("7")
    allow(ENV).to receive(:[]).with("SWAY_RELEASE_SHA").and_return("963d9cebdeadbeef")
    allow(ENV).to receive(:[]).with("SWAY_PREVIOUS_SHA").and_return("4e78f6d4cafef00d")
    allow(ENV).to receive(:[]).with("SWAY_DEPLOYED_AT").and_return("2026-06-03T11:45:26Z")

    args =
      YAML.load(ERB.new(Rails.root.join("config", "deploy.yml").read).result, aliases: true)
        .dig("builder", "args")

    expect(args["SWAY_RELEASE_VERSION"]).to eq("7")
    expect(args["SWAY_RELEASE_SHA"]).to eq("963d9cebdeadbeef")
    expect(args["SWAY_PREVIOUS_SHA"]).to eq("4e78f6d4cafef00d")
    expect(args["SWAY_DEPLOYED_AT"]).to be_a(String)
    expect(Time.iso8601(args["SWAY_DEPLOYED_AT"])).to eq(Time.utc(2026, 6, 3, 11, 45, 26))
  end

  # @lat: [[release-git-fallback-and-caching#Why config/deploy.yml's release build args are wrapped in single quotes]]
  it "carries the uncommitted-changes digest through every link of the chain" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SWAY_UNCOMMITTED_DIGEST").and_return("a1b2c3d4")

    args =
      YAML.load(ERB.new(Rails.root.join("config", "deploy.yml").read).result, aliases: true)
        .dig("builder", "args")
    expect(args["SWAY_UNCOMMITTED_DIGEST"]).to eq("a1b2c3d4")

    dockerfile = Rails.root.join("docker", "dockerfiles", "production.alpine.dockerfile").read

    # @lat: [[release-git-fallback-and-caching#Why the uncommitted-changes digest is checked at every link of its chain]]
    runtime_stage = dockerfile.split(/^FROM .*$/).last.to_s
    expect(runtime_stage).to include("SWAY_UNCOMMITTED_DIGEST=\"\"")
    expect(runtime_stage).to include("SWAY_UNCOMMITTED_DIGEST=${SWAY_UNCOMMITTED_DIGEST}")

    deploy = Rails.root.join("scripts", "deploy.sh").read
    expect(deploy).to match(%r{uncommitted_digest\.sh}), "deploy.sh no longer calls the script that works the value out"
    expect(deploy).to include("export SWAY_UNCOMMITTED_DIGEST")
  end

  it "keeps an empty previous sha as an empty string, not nil" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SWAY_RELEASE_VERSION").and_return("1")
    allow(ENV).to receive(:[]).with("SWAY_RELEASE_SHA").and_return("963d9cebdeadbeef")
    allow(ENV).to receive(:[]).with("SWAY_PREVIOUS_SHA").and_return("")
    allow(ENV).to receive(:[]).with("SWAY_DEPLOYED_AT").and_return("2026-06-03T11:45:26Z")

    args =
      YAML.load(ERB.new(Rails.root.join("config", "deploy.yml").read).result, aliases: true)
        .dig("builder", "args")

    expect(args["SWAY_PREVIOUS_SHA"]).to eq("")
  end

  it "warns before the build when the installation uses Tailscale and it is missing or stopped" do
    deploy_script = Rails.root.join("scripts", "deploy.sh").read
    warning_at = deploy_script.index("TAILSCALE_PROBLEM=\"Tailscale is not active on this machine.\"")

    expect(warning_at).not_to be_nil
    expect(deploy_script).to include("/Applications/Tailscale.app/Contents/MacOS/Tailscale")
    expect(deploy_script).to include('TAILSCALE_PROBLEM="Tailscale is not installed on this machine."')
    expect(warning_at).to be < deploy_script.index("RAILS_ENV=production bundle install")
    expect(deploy_script).to include('if [[ "$SWAY_USES_TAILSCALE" == 1 && -z "$TAILSCALE_CLI" ]]; then')
  end

  # @lat: [[deploy-preflight#What the preflight checks]]
  it "checks that both Dockers reach the image store, and the serving machine, before anything is built" do
    deploy_script = Rails.root.join("scripts", "deploy.sh").read
    preflight_call = deploy_script.index(/^    sway_preflight$/)

    expect(preflight_call).not_to be_nil
    expect(preflight_call).to be < deploy_script.index("RAILS_ENV=production bundle install")
    expect(preflight_call).to be > deploy_script.index("sway_secrets_unlock --sync")
    expect(deploy_script).to include('sway_with_timeout 15 docker pull --quiet "$SWAY_REGISTRY/sway:preflight-probe-absent"')
    expect(deploy_script).to include('timeout 15 docker pull --quiet "$SWAY_PI_REGISTRY/sway:preflight-probe-absent"')
    expect(deploy_script).not_to include("kamal registry login")
    expect(deploy_script).to include("cat scripts/verify-pi.sh")
    expect(deploy_script).to include("sway_with_timeout 30 ssh")
    expect(deploy_script).to include("--preflight-only)")
    expect(deploy_script).to include("--skip-preflight)")
  end

  # @lat: [[deploy-configuration#What the deploy file decides#Why the monitoring accessories are capped and bound to private addresses]]
  it "boots and reboots every configured accessory in scripts/deploy.sh and probes Tailscale dynamically" do
    deploy_config = YAML.load(ERB.new(Rails.root.join("config", "deploy.yml").read).result, aliases: true)
    accessory_names = deploy_config.fetch("accessories").keys

    deploy_script = Rails.root.join("scripts", "deploy.sh").read
    initial_branch, redeploy_branch = deploy_script.split(/^if \[\[ "\$INITIAL_DEPLOY" == 1 \]\]; then$/).last.to_s.split(/^else.*$/)

    accessory_names.each do |name|
      expect(initial_branch).to match(/kamal accessory boot #{Regexp.escape(name)} --verbose/),
        "expected initial deploy branch in scripts/deploy.sh to boot accessory #{name}"
      expect(redeploy_branch).to match(/kamal accessory reboot #{Regexp.escape(name)} --verbose/),
        "expected redeploy branch in scripts/deploy.sh to reboot accessory #{name}"
    end

    expect(deploy_script).to match(/(?:timeout 2|ConnectTimeout=2|alarm 2)/),
      "expected deploy.sh to include a short 2-second timeout probe for Tailscale"
    expect(deploy_script).to include("tailscale status --peers=false")
    expect(deploy_script).to include("tailscale ip -4")
    expect(deploy_script).to match(%r{100\.(?:6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.|100\\\.\(6\[4-9\]|100\.64\.0\.0/10}),
      "expected deploy.sh to validate the 100.64.0.0/10 CGNAT pattern"
    expect(deploy_script).to include("export SWAY_TAILSCALE_IP")
  end

  # @lat: [[deploy-configuration#What the deploy file decides#Why Solid Queue runs in async supervisor mode with single-thread OpenMP]]
  it "renders SOLID_QUEUE_SUPERVISOR_MODE as async and OMP_THREAD_LIMIT as 1 in env.clear" do
    deploy_config = YAML.load(ERB.new(Rails.root.join("config", "deploy.yml").read).result, aliases: true)
    clear_env = deploy_config.dig("env", "clear")

    expect(clear_env["SOLID_QUEUE_SUPERVISOR_MODE"]).to eq("async")
    expect(clear_env["OMP_THREAD_LIMIT"]).to eq("1")
  end

  # @lat: [[development-container-settings#What the container declares about the pipeline's tools#Why OCR is capped to a single OpenMP thread]]
  it "sets OMP_THREAD_LIMIT=1 in the final stage of docker/dockerfiles/production.alpine.dockerfile" do
    dockerfile = Rails.root.join("docker", "dockerfiles", "production.alpine.dockerfile").read
    runtime_stage = dockerfile.split(/^FROM .*$/).last.to_s

    expect(runtime_stage).to match(/^ENV .*OMP_THREAD_LIMIT=1/m)
  end

  # @lat: [[development-container-settings#What the container declares about the pipeline's tools#Why OCR is capped to a single OpenMP thread]]
  it "sets OMP_THREAD_LIMIT=1 in .dockerdev/Dockerfile" do
    dev_dockerfile = Rails.root.join(".dockerdev", "Dockerfile").read

    expect(dev_dockerfile).to match(/^ENV .*OMP_THREAD_LIMIT=1/m)
  end

  # @lat: [[deploy-configuration#What the deploy file decides#Why Solid Queue runs in async supervisor mode with single-thread OpenMP]]
  it "defaults Solid Queue to async supervisor mode in bin/jobs before booting environment" do
    bin_jobs = Rails.root.join("bin", "jobs").read

    expect(bin_jobs).to match(/ENV\[["']SOLID_QUEUE_SUPERVISOR_MODE["']\]\s*\|\|=\s*["']async["']/)
    require_env_index = bin_jobs.index(%r{require_relative ["']\.\./config/environment["']})
    async_mode_index = bin_jobs.index("SOLID_QUEUE_SUPERVISOR_MODE")
    expect(async_mode_index).to be < require_env_index
  end

  # @lat: [[production-image#Why the allocator is replaced, and how that can be undone silently]]
  it "renders MALLOC_CONF with background_thread:true in env.clear" do
    deploy_config = YAML.load(ERB.new(Rails.root.join("config", "deploy.yml").read).result, aliases: true)
    clear_env = deploy_config.dig("env", "clear")

    expect(clear_env["MALLOC_CONF"]).to include("background_thread:true")
  end

  # @lat: [[production-image#Why the allocator is replaced, and how that can be undone silently]]
  it "sets MALLOC_CONF with background_thread:true in the final stage of docker/dockerfiles/production.alpine.dockerfile" do
    dockerfile = Rails.root.join("docker", "dockerfiles", "production.alpine.dockerfile").read
    runtime_stage = dockerfile.split(/^FROM .*$/).last.to_s

    expect(runtime_stage).to match(/MALLOC_CONF=.*background_thread:true/)
  end

  # @lat: [[puma-worker-concurrency-model#Pre-fork VM warmup]]
  it "invokes Process.warmup in before_fork in config/puma.rb" do
    puma_config = Rails.root.join("config", "puma.rb").read

    expect(puma_config).to match(/before_fork do\s+.*ActiveRecord::Base\.connection_pool\.disconnect!.*\s+Process\.warmup if Process\.respond_to\?\(:warmup\)/m)
  end

  # @lat: [[deploy-configuration#What the deploy file decides#Why PDF_EXTRACTOR_URL points at the host extractor port]]
  it "provisions, cross-compiles, atomically uploads, and health-checks sway-pdf-extractor in scripts/deploy.sh before Kamal deploy" do
    deploy_script = Rails.root.join("scripts", "deploy.sh").read

    expect(deploy_script).to include("command -v tesseract >/dev/null 2>&1")
    expect(deploy_script).to include("command -v mutool >/dev/null 2>&1")
    expect(deploy_script).to include("test -f /usr/share/tesseract-ocr/5/tessdata/eng.traineddata")
    expect(deploy_script).to include("test -f /etc/systemd/system/sway-pdf-extractor.service")
    expect(deploy_script).to include("test -f /etc/systemd/system/sway-pdf-extractor.path")
    expect(deploy_script).to include("test -f /etc/systemd/system/sway-pdf-extractor-restart.service")
    expect(deploy_script).to include("grep -q \"^StartLimitIntervalSec=0$\" /etc/systemd/system/sway-pdf-extractor.service")
    expect(deploy_script).to include("systemctl is-active --quiet sway-pdf-extractor.path")
    expect(deploy_script).to include("test -d \"$HOME/bin\"")

    expect(deploy_script).to include("${SWAY_ADMIN_SSH_KEY:-$HOME/.ssh/sway_deploy}")
    expect(deploy_script).to include("< ./scripts/provision-pi.sh")
    expect(deploy_script).to match(%r{< \./scripts/provision-pi\.sh \\\s+&& ssh -t .*sudo .*bash /tmp/sway-provision-pi\.sh pdf-extractor})

    expect(deploy_script).to include("CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build")
    expect(deploy_script).to match(%r{'[^']*\$HOME/bin/sway-pdf-extractor\.tmp[^']*mv -f "\$HOME/bin/sway-pdf-extractor\.tmp" "\$HOME/bin/sway-pdf-extractor"[^']*'})
    expect(deploy_script).to include("if provision_host_pdf_extractor && wait_for_host_pdf_extractor; then")

    health_check_index = deploy_script.index("http://127.0.0.1:8085/up")
    kamal_deploy_index = deploy_script.index("if ! kamal deploy")
    expect(health_check_index).not_to be_nil
    expect(kamal_deploy_index).not_to be_nil
    expect(health_check_index).to be < kamal_deploy_index
  end
end
