# frozen_string_literal: true

require "rails_helper"
require "open3"
require "shellwords"
require "tmpdir"

# @lat: [[use-your-own-secret-store]]
RSpec.describe "scripts/lib/secrets.sh" do
  let(:helper) { Rails.root.join("scripts", "lib", "secrets.sh").to_s }
  let(:bin_dir) { Dir.mktmpdir("sway-secrets-bin", Rails.root.join("tmp").tap(&:mkpath)) }
  let(:log) { File.join(bin_dir, "calls.log") }

  def write_fake(name, body)
    path = File.join(bin_dir, name)
    File.write(path, "#!/usr/bin/env bash\n#{body}")
    File.chmod(0o755, path)
  end

  before do
    write_fake("kamal", <<~SH)
      printf 'kamal %s\\n' "$*" >> "#{log}"
      case "$1 $2" in
        "secrets fetch") printf '{"ITEM":"fetched"}\\n' ;;
        "secrets extract") printf 'extracted-%s\\n' "$3" ;;
      esac
    SH
    write_fake("bw", <<~SH)
      printf 'bw %s session=%s\\n' "$*" "${BW_SESSION:-}" >> "#{log}"
      case "$1" in
        status) printf '{"status":"%s"}\\n' "${FAKE_BW_STATUS:-locked}" ;;
        unlock) printf 'new-session\\n' ;;
        get) printf 'bw-value-%s\\n' "$3" ;;
      esac
    SH
  end

  after { FileUtils.remove_entry(bin_dir) }

  def run_with_secrets(script, env = {})
    clean = {
      "PATH" => "#{bin_dir}:#{ENV.fetch("PATH")}",
      "SWAY_SECRETS_ADAPTER" => nil,
      "SWAY_SECRETS_ACCOUNT" => nil,
      "SWAY_SECRETS_FROM" => nil,
      "SWAY_BW_ACCOUNT" => nil,
      "BW_SESSION" => nil,
      "FAKE_BW_STATUS" => nil
    }
    stdout, stderr, status = Open3.capture3(clean.merge(env), "bash", "-c", "source #{helper.shellescape}; #{script}",
      chdir: Rails.root.to_s)
    [stdout, stderr, status]
  end

  def calls
    File.exist?(log) ? File.readlines(log, chomp: true) : []
  end

  describe "the default Bitwarden store" do
    it "builds the same fetch the secrets file always ran, from SWAY_BW_ACCOUNT" do
      stdout, = run_with_secrets("sway_secrets_fetch_command", "SWAY_BW_ACCOUNT" => "probe@example.com")

      expect(stdout.strip).to eq("kamal secrets fetch --adapter bitwarden --account probe@example.com")
    end

    it "prefers SWAY_SECRETS_ACCOUNT over SWAY_BW_ACCOUNT" do
      stdout, = run_with_secrets("sway_secrets_fetch_command",
        "SWAY_BW_ACCOUNT" => "old@example.com", "SWAY_SECRETS_ACCOUNT" => "new@example.com")

      expect(stdout.strip).to eq("kamal secrets fetch --adapter bitwarden --account new@example.com")
    end

    # @lat: [[kamal-vault-account-indirection#Why an empty account must fail the same way as a missing one]]
    it "treats an empty account the same as a missing one" do
      answers = {empty: {"SWAY_BW_ACCOUNT" => ""}, unset: {}}.transform_values do |env|
        run_with_secrets("sway_secrets_fetch_command", env).first.strip
      end

      expect(answers[:empty]).to eq(answers[:unset])
      expect(answers[:empty]).to eq("kamal secrets fetch --adapter bitwarden --account SWAY_SECRETS_ACCOUNT-is-not-set")
      expect(answers[:empty]).not_to include("@"), "the fallback must not look like a real account"
    end

    it "unlocks a locked vault, exports the session and syncs" do
      stdout, _, status = run_with_secrets('sway_secrets_unlock --sync && echo "session=$BW_SESSION"')

      expect(status).to be_success
      expect(stdout.strip).to eq("session=new-session")
      expect(calls).to eq(["bw unlock --raw session=", "bw sync session=new-session"])
    end

    it "unlocks again when the session it holds is no longer unlocked" do
      stdout, _, status = run_with_secrets('sway_secrets_unlock && echo "session=$BW_SESSION"', "BW_SESSION" => "stale")

      expect(status).to be_success
      expect(stdout.strip).to eq("session=new-session")
      expect(calls).to eq(["bw status session=stale", "bw unlock --raw session=stale"])
    end

    it "leaves an unlocked session alone and skips the sync unless asked" do
      _, _, status = run_with_secrets("sway_secrets_unlock", "BW_SESSION" => "kept", "FAKE_BW_STATUS" => "unlocked")

      expect(status).to be_success
      expect(calls).to eq(["bw status session=kept"])
    end

    it "reads one item as the password field, as provisioning always did" do
      stdout, = run_with_secrets("sway_secrets_get LITESTREAM_GCS_READER_JSON", "BW_SESSION" => "s")

      expect(stdout.strip).to eq("bw-value-LITESTREAM_GCS_READER_JSON")
      expect(calls).to eq(["bw get password LITESTREAM_GCS_READER_JSON session=s"])
    end
  end

  describe "another Kamal adapter" do
    let(:one_password) do
      {"SWAY_SECRETS_ADAPTER" => "1password", "SWAY_SECRETS_ACCOUNT" => "acct", "SWAY_SECRETS_FROM" => "Vault/Item",
       "SWAY_BW_ACCOUNT" => "ignored@example.com"}
    end

    it "passes the adapter, account and source to kamal, and never borrows the Bitwarden account" do
      stdout, = run_with_secrets("sway_secrets_fetch A B", one_password)

      expect(stdout.strip).to eq('{"ITEM":"fetched"}')
      expect(calls).to eq(["kamal secrets fetch --adapter 1password --account acct --from Vault/Item A B"])
    end

    it "reads one item through a fetch and an extract" do
      stdout, = run_with_secrets("sway_secrets_get A", one_password)

      expect(stdout.strip).to eq("extracted-A")
      expect(calls).to eq([
        "kamal secrets fetch --adapter 1password --account acct --from Vault/Item A",
        "kamal secrets extract A {\"ITEM\":\"fetched\"}"
      ])
    end

    it "does not touch bw to unlock" do
      _, _, status = run_with_secrets("sway_secrets_unlock --sync", one_password)

      expect(status).to be_success
      expect(calls).to be_empty
    end

    it "sends no account to an adapter that needs none" do
      stdout, = run_with_secrets("sway_secrets_fetch_command",
        "SWAY_SECRETS_ADAPTER" => "doppler", "SWAY_SECRETS_FROM" => "sway/prd", "SWAY_BW_ACCOUNT" => "ignored@example.com")

      expect(stdout.strip).to eq("kamal secrets fetch --adapter doppler --from sway/prd")
    end
  end

  describe "the env adapter" do
    let(:env_store) { {"SWAY_SECRETS_ADAPTER" => "env", "ITEM_A" => "a value \"quoted\"", "ITEM_B" => "b"} }

    it "reads same-named environment variables without calling kamal or bw" do
      stdout, _, status = run_with_secrets("sway_secrets_fetch ITEM_A ITEM_B", env_store)

      expect(status).to be_success
      expect(JSON.parse(stdout)).to eq("ITEM_A" => "a value \"quoted\"", "ITEM_B" => "b")
      expect(calls).to be_empty
    end

    it "fails naming every unset or empty variable" do
      _, stderr, status = run_with_secrets("sway_secrets_fetch ITEM_A MISSING_ONE EMPTY_ONE", env_store.merge("EMPTY_ONE" => ""))

      expect(status).not_to be_success
      expect(stderr).to include("MISSING_ONE EMPTY_ONE")
    end

    it "reads one item straight from the environment" do
      stdout, = run_with_secrets("sway_secrets_get ITEM_B", env_store)

      expect(stdout.strip).to eq("b")
    end

    it "points the secrets file at the helper's inline fetch" do
      stdout, = run_with_secrets("sway_secrets_fetch_command", env_store)

      expect(stdout.strip).to eq("bash scripts/lib/secrets.sh fetch-inline")
    end

    it "prints the inline fetch shell-quoted, the way kamal's own inline fetch does" do
      stdout, = Open3.capture3({"SWAY_SECRETS_ADAPTER" => "env", "ITEM_A" => "a b"},
        "bash", helper, "fetch-inline", "ITEM_A", chdir: Rails.root.to_s)

      expect(JSON.parse(Shellwords.split(stdout).sole)).to eq("ITEM_A" => "a b")
    end

    it "prints a word that is not JSON when the fetch fails, so every extract raises" do
      stdout, _, status = Open3.capture3({"SWAY_SECRETS_ADAPTER" => "env", "ITEM_A" => nil},
        "bash", helper, "fetch-inline", "ITEM_A", chdir: Rails.root.to_s)

      expect(status).not_to be_success
      expect { JSON.parse(stdout) }.to raise_error(JSON::ParserError)
    end
  end
end
