# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# @lat: [[standby-restore#Why a deploy makes at most one backup copy]]
RSpec.describe BootBackupGuard do
  it "allows the backup when no release has been recorded" do
    Dir.mktmpdir do |dir|
      guard = described_class.new(release_sha: "abc123", deployed_at: "2026-07-30T09:00:00Z", storage_dir: dir)

      expect(guard.backup_needed?).to be(true)
    end
  end

  it "refuses a second backup for the same deploy" do
    Dir.mktmpdir do |dir|
      described_class.new(release_sha: "abc123", deployed_at: "2026-07-30T09:00:00Z", storage_dir: dir).record_backup

      expect(
        described_class.new(release_sha: "abc123", deployed_at: "2026-07-30T09:00:00Z", storage_dir: dir).backup_needed?
      ).to be(false)
    end
  end

  # This is the case the guard exists to protect. A new deploy must still get its
  # copy taken before the migrations run, no matter how recently the deploy
  # before it made one.
  it "allows the backup again once the commit changes" do
    Dir.mktmpdir do |dir|
      described_class.new(release_sha: "abc123", deployed_at: "2026-07-30T09:00:00Z", storage_dir: dir).record_backup

      expect(
        described_class.new(release_sha: "def456", deployed_at: "2026-07-30T10:00:00Z", storage_dir: dir).backup_needed?
      ).to be(true)
    end
  end

  # Deploying the same commit twice (scripts/deploy.sh, after a failure) used
  # to skip the backup when keyed on the commit alone — the one moment you
  # most want a copy, before migrations run again.
  it "allows the backup again when the same commit is deployed a second time" do
    Dir.mktmpdir do |dir|
      described_class.new(release_sha: "abc123", deployed_at: "2026-07-30T09:00:00Z", storage_dir: dir).record_backup

      expect(
        described_class.new(release_sha: "abc123", deployed_at: "2026-07-30T11:30:00Z", storage_dir: dir).backup_needed?
      ).to be(true)
    end
  end

  # Saying yes when we cannot tell which deploy this is, is deliberate. One extra
  # copy costs a little storage; quietly skipping the copy could cost data.
  it "never throttles when nothing identifies the deploy" do
    Dir.mktmpdir do |dir|
      expect(described_class.new(release_sha: nil, deployed_at: nil, storage_dir: dir).backup_needed?).to be(true)
      expect(described_class.new(release_sha: "  ", deployed_at: " ", storage_dir: dir).backup_needed?).to be(true)
    end
  end

  it "writes no marker when nothing identifies the deploy" do
    Dir.mktmpdir do |dir|
      described_class.new(release_sha: nil, deployed_at: nil, storage_dir: dir).record_backup

      expect(File.exist?(File.join(dir, described_class::MARKER_FILENAME))).to be(false)
    end
  end

  # Only the commit is known: still better than nothing, so it still throttles a
  # crash loop. It cannot separate two deploys of one commit, which is why
  # scripts/deploy.sh supplies the time as well.
  it "throttles on the commit alone when no deploy time is available" do
    Dir.mktmpdir do |dir|
      described_class.new(release_sha: "abc123", deployed_at: nil, storage_dir: dir).record_backup

      expect(
        described_class.new(release_sha: "abc123", deployed_at: nil, storage_dir: dir).backup_needed?
      ).to be(false)
    end
  end

  # @lat: [[auxiliary-databases#A machine not serving the public writes no backups at all]]
  it "refuses entirely when SWAY_SKIP_DB_BACKUP is set" do
    Dir.mktmpdir do |dir|
      with_app_config(:ops, sway_skip_db_backup: true) do
        expect(
          described_class.new(release_sha: "abc123", deployed_at: "2026-07-30T09:00:00Z", storage_dir: dir).backup_needed?
        ).to be(false)
        # Even with nothing identifying the deploy, where it otherwise always says yes.
        expect(described_class.new(release_sha: nil, deployed_at: nil, storage_dir: dir).backup_needed?).to be(false)
      end
    end
  end

  it "backs up normally once SWAY_SKIP_DB_BACKUP is absent" do
    Dir.mktmpdir do |dir|
      with_app_config(:ops, sway_skip_db_backup: false) do
        expect(
          described_class.new(release_sha: "abc123", deployed_at: "2026-07-30T09:00:00Z", storage_dir: dir).backup_needed?
        ).to be(true)
      end
    end
  end

  # @lat: [[boot-backup-guard-design#Why missing, blank, and unreadable SWAY_SKIP_DB_BACKUP all mean "back up"]]
  it "backs up normally when SWAY_SKIP_DB_BACKUP is blank or unreadable text" do
    Dir.mktmpdir do |dir|
      ["", "   ", "banana"].each do |raw|
        with_app_config(:ops, sway_skip_db_backup: raw) do
          expect(
            described_class.new(release_sha: "abc123", deployed_at: "2026-07-30T09:00:00Z", storage_dir: dir).backup_needed?
          ).to be(true), "SWAY_SKIP_DB_BACKUP=#{raw.inspect} turned backups off"
        end
      end
    end
  end

  # The constructor keyword's DEFAULT changed (not the keyword itself, so
  # every example above that passes deployed_at: explicitly keeps working).
  it "reads deployed_at from Sway::Settings.ops when the keyword is not given" do
    Dir.mktmpdir do |dir|
      with_app_config(:ops, sway_deployed_at: "2026-07-30T09:00:00Z") do
        described_class.new(release_sha: "abc123", storage_dir: dir).record_backup

        expect(
          described_class.new(release_sha: "abc123", storage_dir: dir).backup_needed?
        ).to be(false)
      end
    end
  end

  # A marker file with stray spaces or a newline around the id must still
  # match — easy to leave by hand or from the shell, and a mismatch means
  # backing up on every start.
  it "matches a marker that carries surrounding whitespace" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, described_class::MARKER_FILENAME), "  abc123@2026-07-30T09:00:00Z\n")

      expect(
        described_class.new(release_sha: "abc123", deployed_at: "2026-07-30T09:00:00Z", storage_dir: dir).backup_needed?
      ).to be(false)
    end
  end

  # Padding on values coming IN, not the file: Kamal supplies env values
  # with a trailing newline — without trimming, nothing matches next time,
  # backing up every restart.
  it "matches when the deploy values themselves arrive padded" do
    Dir.mktmpdir do |dir|
      described_class.new(
        release_sha: " abc123\n", deployed_at: " 2026-07-30T09:00:00Z ", storage_dir: dir
      ).record_backup

      expect(
        described_class.new(release_sha: "abc123", deployed_at: "2026-07-30T09:00:00Z", storage_dir: dir).backup_needed?
      ).to be(false)
    end
  end
end
