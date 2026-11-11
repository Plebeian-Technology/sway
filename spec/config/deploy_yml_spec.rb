# frozen_string_literal: true

require "rails_helper"
require "erb"
require "yaml"
require "support/env_credential_scanner"

# @lat: [[deploy-yml-single-source-and-claude-wiring#Why the Claude API routing wiring is checked directly]]
RSpec.describe "config/deploy.yml" do
  let(:deploy_path) { Rails.root.join("config", "deploy.yml") }

  # Read the file the way Kamal reads it: ERB first, then YAML.
  # @lat: [[deploy-yml-erb-then-yaml-reading#Why it needs checking]]
  let(:deploy_config) do
    YAML.load(ERB.new(deploy_path.read).result, aliases: true)
  end

  # @lat: [[deploy-yml-single-source-and-claude-wiring#Why the machine's address may appear only once, in the top block]]
  it "names no machine anywhere except the block at the top" do
    body = deploy_path.read.sub(/\A(?:#.*\n)+\n?/, "")

    offenders = body.lines.filter_map do |line|
      next if line.strip.start_with?("#")
      next unless line.match?(/\b\d{1,3}(\.\d{1,3}){3}\b/) || line.match?(%r{\s/(media|mnt)/})
      line.strip
    end

    expect(offenders).to eq([]), <<~MESSAGE
      These lines name a machine or one of its disks directly:

      #{offenders.join("\n")}

      Both facts live in the Ruby block at the top of config/deploy.yml, and
      everything else reads them from there. Moving Sway to another Pi has to stay
      a change in one place — it was six places once, and the notes written for
      the switch-over only found four of them.
    MESSAGE
  end

  describe "env.clear" do
    it "sets LLM_PROVIDER to 'claude' (R9 + iter-2 Q7)" do
      expect(deploy_config.dig("env", "clear", "LLM_PROVIDER")).to eq("claude"),
        "expected env.clear.LLM_PROVIDER == 'claude' in config/deploy.yml; " \
        "actual env.clear: #{deploy_config.dig("env", "clear").inspect}. " \
        "Without this line, prod boots with LLM_PROVIDER unset, defaults " \
        "to llamacpp, and every GenerateBillSummaryJob#perform fails on " \
        "the Pi (no llama.cpp running in prod)."
    end

    it "sets WEB_CONCURRENCY to 2" do
      expect(deploy_config.dig("env", "clear", "WEB_CONCURRENCY")).to eq(2)
    end

    it "sets MALLOC_CONF for jemalloc arena and decay tuning" do
      expect(deploy_config.dig("env", "clear", "MALLOC_CONF"))
        .to eq("dirty_decay_ms:1000,muzzy_decay_ms:1000,narenas:2,background_thread:true")
    end

    # @lat: [[deploy-configuration#What the deploy file decides#Why PDF_EXTRACTOR_URL points at the host extractor port]]
    it "sets PDF_EXTRACTOR_URL to the host sway-pdf-extractor port" do
      expect(deploy_config.dig("env", "clear", "PDF_EXTRACTOR_URL"))
        .to eq("http://#{SwayDeployConfig.fetch("SWAY_HOST")}:8085")
    end
  end

  # @lat: [[well-known-controller-notes#Why the served hosts are configuration]]
  describe "the hosts that serve the .well-known files" do
    it "renders both lists from RAILS_ALLOWED_HOSTS, leaving out addresses and ports" do
      allow(SwayDeployConfig).to receive(:fetch).and_call_original
      allow(SwayDeployConfig).to receive(:fetch).with("RAILS_ALLOWED_HOSTS")
        .and_return("example.test, app.example.test,10.0.0.10,::1,app.example.test:3000")

      clear = deploy_config.dig("env", "clear")

      expect(clear["APP_ASSOCIATION_HOSTS"]).to eq("example.test,app.example.test")
      expect(clear["WEBAUTHN_RELATED_HOSTS"]).to eq("example.test,app.example.test")
    end
  end

  # @lat: [[webauthn-settings-consolidation#Why production names its origins and domain in the deploy file]]
  describe "the passkey origins and domain production is given" do
    it "renders the allowed origins from the same public host names, each as an https origin" do
      allow(SwayDeployConfig).to receive(:fetch).and_call_original
      allow(SwayDeployConfig).to receive(:fetch).with("RAILS_ALLOWED_HOSTS")
        .and_return("example.test, app.example.test,10.0.0.10,app.example.test:3000")

      clear = deploy_config.dig("env", "clear")

      expect(clear["WEBAUTHN_ALLOWED_ORIGINS"]).to eq("https://example.test,https://app.example.test")
    end

    it "names the passkey domain explicitly, because the production boot refuses to start without it" do
      expect(deploy_config.dig("env", "clear", "WEBAUTHN_RP_ID")).to be_present
    end

    # @lat: [[android-app-links#Why the fingerprints are per-installation configuration]]
    it "reads the Android signing fingerprints from the installation's own values" do
      expect(deploy_config.dig("env", "clear", "ANDROID_CERT_SHA256_FINGERPRINTS"))
        .to eq(SwayDeployConfig["SWAY_ANDROID_CERT_SHA256_FINGERPRINTS"])
    end

    # @lat: [[public-marketing-and-meta-pages#Why the Apple App Store id is a placeholder]]
    it "reads the Apple App Store id from the installation's own values" do
      expect(deploy_config.dig("env", "clear", "APPLE_APP_STORE_ID"))
        .to eq(SwayDeployConfig["SWAY_APPLE_APP_STORE_ID"])
    end

    it "publishes an empty fingerprint list when the installation names none" do
      allow(SwayDeployConfig).to receive(:[]).and_call_original
      allow(SwayDeployConfig).to receive(:[]).with("SWAY_ANDROID_CERT_SHA256_FINGERPRINTS").and_return(nil)

      expect(deploy_config.dig("env", "clear", "ANDROID_CERT_SHA256_FINGERPRINTS")).to eq("")
    end
  end

  # @lat: [[admin-hub-index#Who sees the monitoring link]]
  it "lists the email domain whose admins see the monitoring link" do
    expect(deploy_config.dig("env", "clear", "BESZEL_ADMIN_EMAIL_DOMAINS")).to be_present
  end

  describe "env.secret" do
    it "includes ANTHROPIC_API_KEY (R9)" do
      expect(deploy_config.dig("env", "secret")).to include("ANTHROPIC_API_KEY"),
        "expected env.secret to list 'ANTHROPIC_API_KEY' in config/deploy.yml; " \
        "actual env.secret: #{deploy_config.dig("env", "secret").inspect}. " \
        "Kamal pulls the secret from .kamal/secrets-common (Bitwarden) at deploy " \
        "time only if it is listed here."
    end

    it "includes BRAVE_SEARCH_API_KEY" do
      expect(deploy_config.dig("env", "secret")).to include("BRAVE_SEARCH_API_KEY"),
        "expected env.secret to list 'BRAVE_SEARCH_API_KEY' in config/deploy.yml; " \
        "actual env.secret: #{deploy_config.dig("env", "secret").inspect}. " \
        "Kamal pulls the secret from .kamal/secrets-common (Bitwarden) at deploy " \
        "time only if it is listed here."
    end
  end

  # @lat: [[deploy-credential-delivery-gap#The fix]]
  describe "credential delivery" do
    # The reasons live beside the scanner's other annotated credential lists,
    # rather than here, so every "why this name is treated specially" fact sits
    # in one file.
    let(:undelivered) { EnvCredentialScanner::UNDELIVERED_CREDENTIALS }
    let(:scanner) { EnvCredentialScanner.new }

    let(:delivered) do
      (deploy_config.dig("env", "secret").to_a + deploy_config.dig("env", "clear").to_h.keys).map(&:to_s).to_set
    end

    it "hands production every credential the app reads, or says why not" do
      missing = scanner.credential_names.reject { |name| delivered.include?(name) || undelivered.key?(name) }

      expect(missing.join("\n")).to eq(""), <<~MESSAGE
        Credentials the app reads that production is never given:

        #{missing.join("\n")}

        Add each to env.secret in config/deploy.yml AND to .kamal/secrets-common —
        Kamal fails the deploy if a listed name has no secret behind it, so both
        halves are needed. If the app genuinely works without the value, add it to
        EnvCredentialScanner::UNDELIVERED_CREDENTIALS WITH THE REASON.
      MESSAGE
    end

    # The reasons rot the moment one is wired up, and a stale "we do without this"
    # note is worse than none: it tells the next reader a live credential is
    # optional.
    it "claims nothing is undelivered that production is in fact given" do
      stale = undelivered.keys.select { |name| delivered.include?(name) }

      expect(stale.join(", ")).to eq(""),
        "these are listed as undelivered but config/deploy.yml now delivers them — " \
        "remove them from UNDELIVERED_CREDENTIALS: #{stale.join(", ")}"
    end

    it "claims nothing is undelivered that the app no longer reads" do
      unknown = undelivered.keys - scanner.credential_names

      expect(unknown.join(", ")).to eq(""),
        "these are listed as undelivered but EnvCredentialScanner no longer counts " \
        "them as credentials the app reads, so the entry is dead: #{unknown.join(", ")}"
    end
  end

  describe "accessories.beszel and accessories.beszel_agent" do
    it "configures beszel hub with pinned image, LAN and Tailscale host publish, and SSD persistence" do
      beszel = deploy_config.dig("accessories", "beszel")

      expect(beszel).to be_a(Hash)
      expect(beszel["service"]).to eq("beszel")
      expect(beszel["image"]).to eq("henrygd/beszel:0.21.0")
      expect(beszel["host"]).to eq(SwayDeployConfig.fetch("SWAY_HOST"))
      expect(beszel["volumes"]).to eq(["#{SwayDeployConfig.fetch("SWAY_STORAGE_DIR")}/beszel:/beszel_data"])
      expect(beszel).not_to have_key("port")
      expect(beszel).not_to have_key("proxy")

      expected_publish = [
        "#{SwayDeployConfig.fetch("SWAY_HOST")}:8090:8090",
        "#{SwayDeployConfig["SWAY_TAILSCALE_IP"]}:8090:8090"
      ]
      expect(beszel.dig("options", "publish")).to eq(expected_publish)
    end

    it "binds beszel hub strictly to SWAY_HOST when SWAY_TAILSCALE_IP is omitted" do
      allow(SwayDeployConfig).to receive(:[]).and_call_original
      [nil, "", "   ", SwayDeployConfig.fetch("SWAY_HOST")].each do |value|
        allow(SwayDeployConfig).to receive(:[]).with("SWAY_TAILSCALE_IP").and_return(value)

        rendered = YAML.load(ERB.new(deploy_path.read).result, aliases: true)
        beszel = rendered.dig("accessories", "beszel")

        expect(beszel.dig("options", "publish")).to eq(["#{SwayDeployConfig.fetch("SWAY_HOST")}:8090:8090"])
      end
    end

    it "enforces CPU and memory caps on beszel hub" do
      beszel = deploy_config.dig("accessories", "beszel")
      options = beszel.dig("options")

      expect(options["cpus"]).to eq("0.25")
      expect(options["memory"]).to eq("128m")
    end

    it "configures beszel_agent with pinned image, internal bridge listening, and read-only mounts" do
      agent = deploy_config.dig("accessories", "beszel_agent")

      expect(agent).to be_a(Hash)
      expect(agent["service"]).to eq("beszel-agent")
      expect(agent["image"]).to eq("henrygd/beszel-agent:0.21.0")
      expect(agent["host"]).to eq(SwayDeployConfig.fetch("SWAY_HOST"))
      expect(agent["volumes"]).to eq([
        "/var/run/docker.sock:/var/run/docker.sock:ro",
        "#{SwayDeployConfig.fetch("SWAY_STORAGE_DIR")}:/extra-filesystems/sda1:ro"
      ])
      expect(agent["volumes"].all? { |vol| vol.end_with?(":ro") }).to be true
      expect(agent.dig("env", "clear", "LISTEN")).to eq("45876")
    end

    it "exposes no published host ports or proxies on beszel_agent" do
      agent = deploy_config.dig("accessories", "beszel_agent")

      expect(agent).not_to have_key("port")
      expect(agent).not_to have_key("proxy")
      expect(agent.dig("options") || {}).not_to have_key("publish")
    end

    it "delivers BESZEL_AGENT_KEY only to the agent accessory" do
      agent = deploy_config.dig("accessories", "beszel_agent")

      expect(agent.dig("env", "secret")).to eq(["BESZEL_AGENT_KEY"])
      expect(deploy_config.dig("env", "secret")).not_to include("BESZEL_AGENT_KEY")
    end

    it "enforces CPU, memory, and capability restrictions on beszel_agent" do
      agent = deploy_config.dig("accessories", "beszel_agent")
      options = agent.dig("options")

      expect(options["cpus"]).to eq("0.25")
      expect(options["memory"]).to eq("64m")
      expect(options["cap-drop"]).to eq(["ALL"])
      expect(options["security-opt"]).to eq(["no-new-privileges:true"])
    end

    it "drops all capabilities and prevents privilege escalation on cloudflare_tunnel, litestream, and beszel" do
      %w[cloudflare_tunnel litestream beszel].each do |accessory_name|
        options = deploy_config.dig("accessories", accessory_name, "options")

        expect(options).to be_a(Hash), "expected options hash on accessories.#{accessory_name}"
        expect(options["cap-drop"]).to eq(["ALL"])
        expect(options["security-opt"]).to eq(["no-new-privileges:true"])
      end
    end
  end

  # @lat: [[deploy-configuration#What the deploy file decides#Why application containers drop all capabilities]]
  describe "servers.web.options and servers.job.options" do
    it "configures web role with CPU cap, dropped capabilities, and no privilege escalation" do
      web_options = deploy_config.dig("servers", "web", "options")

      expect(web_options).to be_a(Hash)
      expect(web_options).to include(
        "cpus" => "2.0",
        "cap-drop" => ["ALL"],
        "security-opt" => ["no-new-privileges:true"]
      )
    end

    it "configures job role with CPU cap, dropped capabilities, and no privilege escalation" do
      job_options = deploy_config.dig("servers", "job", "options")

      expect(job_options).to be_a(Hash)
      expect(job_options).to include(
        "cpus" => "1.0",
        "cap-drop" => ["ALL"],
        "security-opt" => ["no-new-privileges:true"]
      )
    end
  end

  # @lat: [[deploy-configuration#What the deploy file decides#Why the auditd accessory audits the app user and never blocks]]
  describe "accessories.auditd" do
    it "configures auditd accessory with pinned alpine image, host network and PID, security options, and caps" do
      auditd = deploy_config.dig("accessories", "auditd")

      expect(auditd).to be_a(Hash)
      expect(auditd["service"]).to eq("sway-auditd")
      expect(auditd["image"]).to eq("alpine:3.21")
      expect(auditd["host"]).to eq(SwayDeployConfig.fetch("SWAY_HOST"))
      expect(auditd["network"]).to eq("host")
      expect(auditd).not_to have_key("port")
      expect(auditd).not_to have_key("proxy")
      expect(auditd.dig("options") || {}).not_to have_key("publish")

      options = auditd["options"]
      expect(options).to be_a(Hash)
      expect(options).not_to have_key("network")
      expect(options).to include(
        "cpus" => "0.10",
        "memory" => "32m",
        "cap-add" => ["AUDIT_CONTROL", "AUDIT_READ"],
        "pid" => "host",
        "security-opt" => ["no-new-privileges:true"]
      )
    end

    it "configures clear and secret environment variables for auditd" do
      auditd = deploy_config.dig("accessories", "auditd")

      clear_env = auditd.dig("env", "clear")
      expect(clear_env).to be_a(Hash)
      expect(clear_env["SWAY_AUDIT_STORAGE_DIR"]).to eq(SwayDeployConfig.fetch("SWAY_STORAGE_DIR"))
      expect(clear_env["SWAY_AUDIT_KEYFILE_PATH"]).to eq(SwayDeployConfig.fetch("SWAY_KEYFILE_PATH"))
      expect(clear_env["SWAY_AUDIT_DEPLOY_HOME"]).to eq("/home/#{SwayDeployConfig.fetch("SWAY_DEPLOY_USER")}")

      secret_env = auditd.dig("env", "secret")
      expect(secret_env).to eq(["SENTRY_DSN"])
    end

    it "configures non-blocking kernel audit rules and exfiltration watches that audit the app user too" do
      auditd = deploy_config.dig("accessories", "auditd")
      cmd = auditd["cmd"]

      expect(cmd).to be_a(String)
      expect(cmd).to include("--backlog_wait_time 0")
      expect(cmd).to include("-f 1")
      expect(cmd).not_to include("-f 2")
      expect(cmd).to include("-e 1")
      expect(cmd).to include("-w \"$SWAY_AUDIT_STORAGE_DIR\"")
      expect(cmd).to include("-w \"$SWAY_AUDIT_KEYFILE_PATH\"")
      expect(cmd).to include("-w /var/run/docker.sock")
      expect(cmd).to include("-w \"$SWAY_AUDIT_DEPLOY_HOME/.kamal\"")
      expect(cmd).to include("-w \"$SWAY_AUDIT_DEPLOY_HOME/.ssh\"")
      expect(cmd).not_to include("uid!=")
      expect(cmd).to include("auditctl -a never,exit -F path=\"$SWAY_AUDIT_STORAGE_DIR/$db.sqlite3$suffix\" -F uid=100")
      expect(cmd).to include("auditctl -a never,exit -F dir=\"$SWAY_AUDIT_STORAGE_DIR/legislation\" -F uid=100")
      expect(cmd.index("-a never,exit")).to be < cmd.index("-w \"$SWAY_AUDIT_STORAGE_DIR\"")
      expect(cmd).to include("sway_secrets_access")
      expect(cmd).to include("sway_storage_access")
      expect(cmd).to include("sway_keyfile_access")
      expect(cmd).to include("sway_docker_sock_access")
      expect(cmd).to include("|| true); fi")
      expect(cmd).not_to match(/\)\s*&\s*fi\b/)
    end
  end

  # @lat: [[deploy-configuration#What the deploy file decides#Why Docker logging uses the local driver with rotation caps]]
  describe "logging" do
    it "configures the local logging driver with rotation size and file caps" do
      logging = deploy_config["logging"]

      expect(logging).to be_a(Hash)
      expect(logging["driver"]).to eq("local")
      expect(logging.dig("options", "max-size")).to eq("10m")
      expect(logging.dig("options", "max-file")).to eq("3")
    end
  end
end
