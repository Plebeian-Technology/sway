# frozen_string_literal: true

# @lat: [[boot-backup-guard-design#What the guard does instead]]
class BootBackupGuard
  MARKER_FILENAME = ".boot_backup_release"

  def initialize(release_sha: Sway::Release.sha, deployed_at: Sway::Settings.ops.sway_deployed_at, storage_dir: Rails.root.join("storage").to_s)
    @release_id = [release_sha, deployed_at].map { |part| part.to_s.strip }.reject(&:empty?).join("@")
    @storage_dir = storage_dir
  end

  # @lat: [[boot-backup-guard-design#Why missing, blank, and unreadable SWAY_SKIP_DB_BACKUP all mean "back up"]]
  def backup_needed?
    return false if Sway::Settings.ops.sway_skip_db_backup
    return true if release_id.empty?

    recorded_release != release_id
  end

  # @lat: [[boot-backup-guard-design#Why record_backup must only be called after a real upload]]
  def record_backup
    return if release_id.empty?

    File.write(marker_path, release_id)
  rescue SystemCallError => e
    SwayLogging.error("boot_backup_guard.marker_write_failed", error: e.message)
  end

  private

  attr_reader :release_id, :storage_dir

  def recorded_release
    File.read(marker_path).strip
  rescue SystemCallError
    ""
  end

  def marker_path
    File.join(storage_dir, MARKER_FILENAME)
  end
end
