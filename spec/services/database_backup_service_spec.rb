# frozen_string_literal: true

require "rails_helper"

# Tests for SwayTask#backup_db — copies a live SQLite database
# safely, uploads to GCS, prunes old backups. Cloud calls are faked; the
# copy runs against a real throwaway file.
RSpec.describe DatabaseBackupService do
  let(:backup_db_name) { "backup_spec_#{SecureRandom.hex(4)}" }
  let(:backup_source_path) { Rails.root.join("storage", "#{backup_db_name}.sqlite3").to_s }

  it "returns :skipped when the source DB file does not exist" do
    service = described_class.new(db_name: "does_not_exist_#{SecureRandom.hex(4)}")

    expect(service.call).to eq(:skipped)
  end

  it "performs an online backup and uploads a non-empty file to the env-scoped GCS path" do
    db = SQLite3::Database.new(backup_source_path)
    db.execute("CREATE TABLE widgets (id INTEGER PRIMARY KEY, name TEXT)")
    db.execute("INSERT INTO widgets (name) VALUES ('alpha')")
    db.close

    service = described_class.new(db_name: backup_db_name)
    no_backups = [] #: Array[untyped]
    allow(service).to receive(:existing_backups).and_return(no_backups) # no prune work

    captured = {} #: Hash[Symbol, untyped]
    allow(service).to receive(:upload_file) do |**kwargs|
      captured[:bucket_name] = kwargs[:bucket_name]
      captured[:bucket_file_path] = kwargs[:bucket_file_path]
      captured[:size] = File.size(kwargs[:local_file_path])
    end

    expect(service.call).to eq(:ok)
    # @lat: [[deploy-values-boot-check#Keeping one installation's values out of the tracked repository]]
    expect(captured[:bucket_name]).to eq(DatabaseBackupService::BUCKET_NAME)
    expect(captured[:bucket_name]).to be_present
    expect(captured[:bucket_file_path]).to match(
      %r{\Adb/test/#{backup_db_name}_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_\w+\.sqlite3\z}
    )
    expect(captured[:size]).to be > 0
  ensure
    File.delete(backup_source_path) if File.exist?(backup_source_path)
  end

  # @lat: [[auxiliary-databases#A backup that shrank is refused rather than uploaded]]
  it "refuses to upload, and does not prune, when the backup shrank past the floor" do
    db = SQLite3::Database.new(backup_source_path)
    db.execute("CREATE TABLE widgets (id INTEGER PRIMARY KEY, name TEXT)")
    db.close

    service = described_class.new(db_name: backup_db_name)
    # Old enough that pruning WOULD delete it, so checking that nothing was
    # deleted really proves the prune was skipped, not that it found no work.
    previous = double(
      "file",
      name: "db/test/#{backup_db_name}_2020-01-01_00-00-00_UTC.sqlite3",
      created_at: 100.days.ago,
      size: 11_051_008
    )
    allow(service).to receive(:existing_backups).and_return([previous])

    uploaded = false
    allow(service).to receive(:upload_file) { uploaded = true }
    deleted = [] #: Array[untyped]
    allow(service).to receive(:delete_file) do |**kwargs|
      deleted << kwargs[:file_name]
    end

    expect(service.call).to eq(:refused)
    expect(uploaded).to be(false)
    expect(deleted).to be_empty
  ensure
    File.delete(backup_source_path) if File.exist?(backup_source_path)
  end

  it "uploads when the backup is comfortably above the size floor" do
    db = SQLite3::Database.new(backup_source_path)
    db.execute("CREATE TABLE widgets (id INTEGER PRIMARY KEY, name TEXT)")
    db.execute("INSERT INTO widgets (name) VALUES ('alpha')")
    db.close

    service = described_class.new(db_name: backup_db_name)
    previous = double(
      "file",
      name: "db/test/#{backup_db_name}_2026-07-28_12-00-00_UTC.sqlite3",
      created_at: 1.day.ago,
      size: 1_024
    )
    allow(service).to receive(:existing_backups).and_return([previous])

    uploaded = false
    allow(service).to receive(:upload_file) { uploaded = true }

    expect(service.call).to eq(:ok)
    expect(uploaded).to be(true)
  ensure
    File.delete(backup_source_path) if File.exist?(backup_source_path)
  end

  it "ignores another database's backups when sizing the floor" do
    db = SQLite3::Database.new(backup_source_path)
    db.execute("CREATE TABLE widgets (id INTEGER PRIMARY KEY, name TEXT)")
    db.close

    service = described_class.new(db_name: backup_db_name)
    # A much larger backup of a different database under the same db/<env>/
    # path must not be used as the size to compare against, or backing up a
    # small database would be refused forever.
    sibling = double(
      "file",
      name: "db/test/#{backup_db_name}_queue_2026-07-28_12-00-00_UTC.sqlite3",
      created_at: 1.day.ago,
      size: 11_051_008
    )
    allow(service).to receive(:existing_backups).and_return([sibling])

    uploaded = false
    allow(service).to receive(:upload_file) { uploaded = true }

    expect(service.call).to eq(:ok)
    expect(uploaded).to be(true)
  ensure
    File.delete(backup_source_path) if File.exist?(backup_source_path)
  end

  it "prunes only this DB's backups older than the retention window" do
    service = described_class.new(db_name: "production", retention_days: 14)

    old_main = double("file", name: "db/test/production_2020-01-01_00-00-00_UTC.sqlite3", created_at: 100.days.ago)
    recent_main = double("file", name: "db/test/production_2026-05-30_00-00-00_UTC.sqlite3", created_at: 1.day.ago)
    # production_queue_* sits under the same db/test/ path but must NOT be
    # pruned by the "production" run — the name pattern is anchored on the
    # timestamp digits.
    old_queue = double("file", name: "db/test/production_queue_2020-01-01_00-00-00_UTC.sqlite3", created_at: 100.days.ago)
    allow(service).to receive(:existing_backups).and_return([old_main, recent_main, old_queue])

    deleted = [] #: Array[untyped]
    allow(service).to receive(:delete_file) do |**kwargs|
      deleted << kwargs[:file_name]
    end

    service.send(:prune_old_backups)

    expect(deleted).to contain_exactly("db/test/production_2020-01-01_00-00-00_UTC.sqlite3")
  end

  describe "#existing_backups" do
    it "lists through the shared storage module, scoped to this env's db prefix" do
      service = described_class.new(db_name: "production")
      listed = [] #: Array[untyped]
      allow(service).to receive(:list_files).and_return(listed)

      expect(service.send(:existing_backups)).to eq(listed)
      expect(service).to have_received(:list_files).with(
        bucket_name: DatabaseBackupService::BUCKET_NAME,
        prefix: "db/test/"
      )
    end

    it "rescues a listing failure, logs a warning, and returns an empty array" do
      service = described_class.new(db_name: "production")
      allow(service).to receive(:list_files).and_raise(StandardError, "boom")
      allow(SwayLogging).to receive(:log_exception)

      expect(service.send(:existing_backups)).to eq([])
      expect(SwayLogging).to have_received(:log_exception).with(
        "database_backup.prune_list_failed",
        exception: an_instance_of(StandardError),
        level: :warn
      )
    end
  end

  describe "SwayTask#run_task" do
    before do
      require Rails.root.join("lib", "tasks", "sway_task")
      allow(SwayTask).to receive(:download_email_blocklist)
    end

    it "does not call backup_db outside production" do
      task = SwayTask.new
      allow(task).to receive(:backup_db)

      task.run_task

      expect(task).not_to have_received(:backup_db)
    end

    it "calls backup_db in production" do
      allow(Rails.env).to receive(:production?).and_return(true)
      task = SwayTask.new
      allow(task).to receive(:download_directory)
      allow(task).to receive(:backup_db)

      task.run_task

      expect(task).to have_received(:backup_db)
    end
  end

  describe "SwayTask.download_email_blocklist" do
    before do
      require Rails.root.join("lib", "tasks", "sway_task")
    end

    # @lat: [[sway-task-deploy-backup-design#Why SwayTask.backup_db retries#Why download_email_blocklist bounds its network wait and keeps the existing file]]
    it "passes open and read timeouts and keeps the existing file when download fails" do
      Dir.mktmpdir do |dir|
        target = Pathname.new(dir).join("blocklist.conf")
        target.write("existing.example\n")
        stub_const("Constants::DISPOSABLE_EMAIL_BLOCKLIST_FILE_PATH", target)

        expect(OpenURI).to receive(:open_uri).with(
          Constants::DISPOSABLE_EMAIL_BLOCKLIST_URL,
          open_timeout: SwayTask::EMAIL_BLOCKLIST_TIMEOUT_SECONDS,
          read_timeout: SwayTask::EMAIL_BLOCKLIST_TIMEOUT_SECONDS
        ).and_raise(SocketError.new("getaddrinfo(3): Try again"))

        expect(SwayLogging).to receive(:log_exception).with(
          "sway.rake -> Failed to download email blocklist, keeping existing blocklist.",
          exception: an_instance_of(SocketError),
          level: :warn
        )

        expect { SwayTask.download_email_blocklist }.not_to raise_error
        expect(target.read).to eq("existing.example\n")
      end
    end
  end
end
