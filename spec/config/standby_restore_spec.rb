# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"

# @lat: [[litestream-restore#The standby copy]]
RSpec.describe "scripts/standby-restore.sh" do
  let(:standby_script) { Rails.root.join("scripts", "standby-restore.sh").read }

  it "is executable, so systemd can run it without a wrapper" do
    expect(Rails.root.join("scripts", "standby-restore.sh").executable?).to eq(true)
  end

  describe "holding no value of its own" do
    it "names no address" do
      # Both shapes: a numeric address, and a name on a private network.
      expect(standby_script).not_to match(/\b\d{1,3}(\.\d{1,3}){3}\b/)
      expect(standby_script).not_to match(/\b[\w-]+\.local\b/)
    end

    it "names no cloud folder" do
      expect(standby_script).not_to match(%r{\bgs://\S+}),
        "a baked replica URL goes on quietly fetching a folder nobody writes to " \
        "any more, and every run still reports success"
    end

    it "names no folder on anybody's disk" do
      # @lat: [[litestream-restore#Verify the restore path by hand]]
      allowed = %r{\A/(usr/local/sbin|etc/(default|systemd)|usr/bin/env|dev/null|etc/litestream|standby|data)(/|\z)}
      paths = standby_script.scan(%r{(?<![\w$"'/])/(?:[\w.-]+/)+[\w.-]+}).uniq #: Array[String]

      offenders = paths.reject { |path| path.match?(allowed) }

      expect(offenders).to eq([]),
        "these describe somebody's own machine and must come from the settings " \
        "file instead: #{offenders.inspect}"
    end

    it "stops and names what is missing rather than guessing" do
      expect(standby_script).to include("need SWAY_STANDBY_DIR SWAY_STANDBY_MOUNT SWAY_REPLICA_URL SWAY_GCS_KEY")
    end

    it "lets the environment beat the settings file, so one run can go elsewhere" do
      expect(standby_script).to include('[[ -z "${!name:-}" ]] && export "$name=${line#*=}"')
    end
  end

  describe "handing the values to the timer" do
    it "writes them into the file the timer reads" do
      # The timer runs with an empty environment. Without this the installed job
      # knows nothing, and the first anyone hears of it is a fetch that never
      # happened.
      %w[SWAY_STANDBY_DIR SWAY_STANDBY_MOUNT SWAY_REPLICA_URL SWAY_GCS_KEY].each do |name|
        expect(standby_script).to match(/^#{name}=\$\{[A-Z_]+\}$/),
          "install must write #{name} into /etc/default/sway-standby-restore"
      end
    end

    it "points the unit at that file" do
      expect(standby_script).to include("EnvironmentFile=-${DEFAULTS_FILE}")
    end

    it "does not overwrite a settings file somebody has already edited" do
      expect(standby_script).to include('if [[ -e "$DEFAULTS_FILE" ]]; then')
    end
  end

  describe "the safety properties that make a failed fetch harmless" do
    it "fetches into a scratch name, never straight over the copy it already has" do
      expect(standby_script).to match(/restore -o "\/standby\/\$\(basename "\$SCRATCH"\)"/),
        "the fetch must write to the scratch path. Writing straight to the real path means a " \
        "fetch that dies halfway destroys the good copy it was meant to replace."
    end

    it "puts the new copy in place only after the checks have run" do
      integrity_at = standby_script.index("PRAGMA integrity_check")
      promote_at = standby_script.index('mv -f "$SCRATCH" "$LIVE"')

      expect(integrity_at).to be_present
      expect(promote_at).to be_present
      expect(integrity_at).to be < promote_at
    end

    it "refuses to run when the removable disk is missing" do
      # @lat: [[standby-restore#Why the fetch refuses to run without its disk]]
      expect(standby_script).to include("mountpoint -q \"$STANDBY_MOUNT\"")
      expect(standby_script).to include("RequiresMountsFor=${STANDBY_MOUNT}")
    end

    it "hands the fetched file to the account that runs it, not to root" do
      # A root-owned companion file beside a database locks its own owner out
      # afterwards, which is a trap already paid for when the standby moved to new hardware.
      expect(standby_script).to include('--user "$(id -u):$(id -g)"')
    end

    it "records how long the fetch took, because that is the real recovery time" do
      expect(standby_script).to include("\"restore_seconds\":")
    end
  end

  describe "check, run for real" do
    # Runs `check` with a throwaway settings set and returns its stdout.
    # @lat: [[standby-restore#What check has to try, and for whom]]
    def standby_check_output(standby_dir, tmp, run_user)
      stdout, _stderr, status = Open3.capture3(
        {
          "SWAY_STANDBY_USER" => run_user,
          "SWAY_STANDBY_DIR" => standby_dir,
          "SWAY_STANDBY_MOUNT" => tmp,
          "SWAY_REPLICA_URL" => "gs://example-bucket/none",
          "SWAY_GCS_KEY" => File.join(tmp, "key.json")
        },
        "bash", Rails.root.join("scripts", "standby-restore.sh").to_s, "check"
      )

      expect(status.exitstatus).to eq(0)
      stdout
    end

    it "reports NO when nothing can be created where the copy would go" do
      Dir.mktmpdir("standby-check") do |tmp|
        File.write(File.join(tmp, "key.json"), "")
        # A plain file, so the folder beneath it cannot be written to by any
        # account, root included.
        File.write(File.join(tmp, "blocked"), "")

        output = standby_check_output(File.join(tmp, "blocked", "sway"), tmp, `id -un`.strip)

        expect(output).to include("can write there:  NO")
      end
    end

    it "reports NO when the folder exists and the run account may not create in it" do
      skip "root can create a file in any folder" if Process.uid.zero?

      Dir.mktmpdir("standby-check") do |tmp|
        File.write(File.join(tmp, "key.json"), "")
        standby_dir = File.join(tmp, "standby")
        FileUtils.mkdir_p(standby_dir)
        File.chmod(0o500, standby_dir)

        output = standby_check_output(standby_dir, tmp, `id -un`.strip)

        expect(output).to include("can write there:  NO")
      end
    end

    it "reports yes on a folder it can write, and leaves nothing behind" do
      Dir.mktmpdir("standby-check") do |tmp|
        File.write(File.join(tmp, "key.json"), "")
        standby_dir = File.join(tmp, "standby")
        FileUtils.mkdir_p(standby_dir)

        output = standby_check_output(standby_dir, tmp, `id -un`.strip)

        expect(output).to include("can write there:  yes")
        expect(Dir.children(standby_dir)).to eq([])
      end
    end

    it "says which account it is reporting on when that is not the caller" do
      Dir.mktmpdir("standby-check") do |tmp|
        File.write(File.join(tmp, "key.json"), "")
        standby_dir = File.join(tmp, "standby")
        FileUtils.mkdir_p(standby_dir)

        output = standby_check_output(standby_dir, tmp, "sway-standby-account-that-does-not-exist")

        expect(output).to include("runs as:          sway-standby-account-that-does-not-exist")
        expect(output).to include("Every line below reports on sway-standby-account-that-does-not-exist")
        expect(output).to include("can write there:  unknown")
      end
    end
  end

  describe "the install command it tells people to run" do
    it "names the values inline rather than relying on sudo carrying them" do
      expect(standby_script).not_to include("sudo -E"),
        "sudo -E drops every value unless sudoers allows it, and the documented " \
        "invocation was the one that fails"
      expect(standby_script).to include("SWAY_STANDBY_DIR=... SWAY_STANDBY_MOUNT=...")
    end

    it "gives sudo the full path, which root can read even where the caller cannot" do
      expect(standby_script).to include("sudo $(this_file) install")
    end
  end

  it "does not pin the row counts it checks, which would rot within a week" do
    # It must reject an empty copy and warn on a fall, without asserting today's
    # figures. 18 users and 218 bills were true at the cutover and will not be
    # true next month.
    counted = standby_script[/^COUNTED_TABLES=\(([^)]+)\)/, 1].to_s.split
    expect(counted).to match_array(%w[users user_votes bills])
    expect(standby_script).not_to match(/-(eq|ne) (18|26|27|218)\b/)
  end
end
