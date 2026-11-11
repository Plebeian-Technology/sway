# frozen_string_literal: true

require "rails_helper"
require "open3"
require "sqlite3"

# @lat: [[data-migrate-rails-8-1-upgrade#Why data_migrate is pinned to 11.x, not 9.4.2]]
# This spec runs the real rake task in a separate process, in the production
# environment, against a throwaway copy of the snapshot — as close as we get locally to
# what the production server does, initializers included.
RSpec.describe "db:migrate:with_data rake task replay", :production_snapshot do
  it "completes the real rake task against a snapshot copy and backfills every legislator" do
    skip "db/production.pristine.sqlite3 not present" unless ProductionSnapshot.available?
    master_key = Rails.root.join("config", "master.key")
    skip "config/master.key not present" unless master_key.exist?

    db = ProductionSnapshot::WORK_DIR.join("rake_replay.sqlite3")
    queue_db = ProductionSnapshot::WORK_DIR.join("rake_replay_queue.sqlite3")
    FileUtils.mkdir_p(ProductionSnapshot::WORK_DIR)
    [db, queue_db].each { |path| FileUtils.rm_f([path.to_s, "#{path}-wal", "#{path}-shm"]) }
    FileUtils.cp(ProductionSnapshot::PRISTINE_PATH, db)

    env = {
      "RAILS_ENV" => "production",
      "SECRET_KEY_BASE" => "production-snapshot-rake-replay",
      "RAILS_MASTER_KEY" => master_key.read.strip,
      "SWAY_DATABASE_NAME" => db.relative_path_from(Rails.root).to_s,
      "SWAY_QUEUE_DATABASE_NAME" => queue_db.relative_path_from(Rails.root).to_s
    }
    output, status = Open3.capture2e(
      env, "bundle", "exec", "rails", "db:migrate:with_data", chdir: Rails.root.to_s
    )

    expect(status).to be_success,
      "db:migrate:with_data failed:\n#{output.split("\n").last(40).join("\n")}"
    expect(output).not_to include("aborted!")

    # The data conversion has to have run through the rake task as well. This is the
    # same thing migration 20260711000010 checks on the production server: no legislator
    # left without a locale.
    null_locales = SQLite3::Database.open(db.to_s) do |sqlite|
      sqlite.get_first_value("SELECT COUNT(*) FROM legislators WHERE sway_locale_id IS NULL")
    end
    expect(null_locales).to eq(0)
  end
end
