# frozen_string_literal: true

require "rails_helper"
require "support/env_credential_scanner"

# @lat: [[env-credential-scanner-full-repo-sweep#What this scanner does instead]]
# This file pins COVERAGE (no read escapes the shared helper); env_secret_call_sites_spec.rb pins BEHAVIOR. Neither implies the other.
RSpec.describe "ENV credential read coverage" do
  let(:scanner) { EnvCredentialScanner.new }

  it "routes every credential-shaped ENV read through EnvSecret or an inline strip" do
    # Compared as one string joined by newlines rather than as an array, so the
    # whole list survives RSpec's habit of cutting long diffs short. A check
    # whose failure output ends in "..." leaves the next reader to work the
    # finding out again by hand.
    report = scanner.unstripped.join("\n")

    expect(report).to eq(""), <<~MESSAGE
      Credential-shaped ENV reads that neither go through EnvSecret nor strip inline:

      #{report}

      Fix each by routing it through EnvSecret.read / EnvSecret.fetch! (autoloaded
      code) or `.to_s.strip.presence` (boot-time config, which runs before Zeitwerk
      sets up the main autoloader). If a site genuinely cannot be either, add it to
      EnvCredentialScanner::EXEMPT_PATHS WITH THE EVIDENCE -- not to a filter that
      makes it invisible.
    MESSAGE
  end

  # A scan that quietly matches nothing is how a broadened filter slips back to a
  # narrow one, and looking only at .rb files was the exact blind spot that let
  # the newrelic.yml read hide.
  it "reaches file types the original --include='*.rb' sweep could not see" do
    scanned = scanner.reads.map(&:path).uniq
    extensions = scanned.map { |path| File.extname(path) }.uniq

    expect(scanned).to include("config/newrelic.yml")
    expect(extensions).to include(".yml")
    expect(extensions).to include(".erb")
    expect(extensions).to include(".rb")
  end

  # The list of credentials comes from .kamal/secrets-common, so a newly added secret
  # falls under this check without anyone remembering to list it here. Pin that
  # the list is read live and is not a frozen copy.
  it "derives its credential set from the provisioning source of truth" do
    expect(scanner.credential_names).to include("NEW_RELIC_LICENSE_KEY")
    expect(scanner.credential_names).to include("ANTHROPIC_API_KEY")
    expect(scanner.credential_names).to include("OPENROUTER_API_KEY")
    expect(scanner.credential_names).to include("BRAVE_SEARCH_API_KEY")
    expect(scanner.credential_names).to include("API_KEY_HMAC_SECRET_KEY")
    expect(scanner.credential_names).not_to include("KAMAL_REGISTRY_PASSWORD")

    secrets_common = Rails.root.join(".kamal", "secrets-common").read
    expect(secrets_common[/^SECRETS=.*$/].to_s).to include("SWAY_BESZEL_AGENT_KEY")
    expect(secrets_common).to include("BESZEL_AGENT_KEY=$(kamal secrets extract SWAY_BESZEL_AGENT_KEY $SECRETS)")
    expect(EnvCredentialScanner::NON_APP_CREDENTIALS).to have_key("BESZEL_AGENT_KEY")
    expect(scanner.credential_names).not_to include("BESZEL_AGENT_KEY")
  end

  # API_USER_PHONES decides who may mint an API key and was on
  # neither list, so production ran with an empty one and nothing said so.
  # @lat: [[settings-and-secrets#Phone lists that decide access]]
  it "keeps config/deploy.yml's secret list and .kamal/secrets-common in step" do
    lines = Rails.root.join("config", "deploy.yml").readlines
      .drop_while { |line| !line.match?(/^ {4}secret:\s*$/) }
      .drop(1)
      .take_while { |line| line.strip.empty? || line.start_with?(" " * 8) }
    delivered = lines.filter_map { |line| line[/^\s*-\s*([A-Z0-9_]+)\s*$/, 1] }
    provisioned = Rails.root.join(".kamal", "secrets-common").readlines
      .filter_map { |line| line[/\A([A-Z0-9_]+)=/, 1] }

    # A parse that matched nothing would satisfy every check below.
    expect(delivered.size).to be > 20

    expect(delivered - provisioned).to eq([]),
      "config/deploy.yml names these under env.secret and .kamal/secrets-common " \
      "fetches none of them, so Kamal aborts the deploy: #{(delivered - provisioned).join(", ")}"

    unlisted = provisioned - delivered - EnvCredentialScanner::NON_APP_CREDENTIALS.keys
    expect(unlisted).to eq([]),
      "these are fetched from the vault and handed to nobody. Add each to " \
      "env.secret in config/deploy.yml, or to NON_APP_CREDENTIALS with the " \
      "reason it is not the app's: #{unlisted.join(", ")}"

    expect(delivered).to include("ADMIN_PHONES", "API_USER_PHONES")
  end

  # Deciding what counts as merely passing a variable along is the scanner's one
  # judgment call, so pin both sides: handing a variable to a child process is
  # not a read, while dropping the same variable into a command IS.
  it "distinguishes shell pass-through from shell consumption" do
    scanner_reads = scanner.reads.map(&:to_s)

    expect(scanner_reads).not_to include(a_string_matching(/compose\.yml.*TWILIO_ACCOUNT_SID/))
    expect(scanner_reads).not_to include(a_string_matching(%r{scripts/dip/provision\.sh.*RAILS_MASTER_KEY}))
  end

  # @lat: [[env-credential-scanner-full-repo-sweep#Why an ENV assignment does not count as a read]]
  it "does not count an ENV assignment as a read" do
    boot_sources = scanner.reads.select { |read| read.path == "config/boot.rb" }.map(&:source)

    # The write is not reported at all...
    expect(boot_sources).not_to include(a_string_matching(/ENV\["NEW_RELIC_LICENSE_KEY"\]\s*=[^=]/))
    # ...while the read one line above it still is, and passes on its own.
    expect(boot_sources).to include(a_string_matching(/ENV\["NEW_RELIC_LICENSE_KEY"\]\.to_s\.strip/))
  end
end
