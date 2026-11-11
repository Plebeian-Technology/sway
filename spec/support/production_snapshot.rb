# frozen_string_literal: true

# @lat: [[production-snapshot-deploy-rehearsal-harness#Why ProductionSnapshot.migrate! is built from the pending-migrations primitives, not the rake-task runner]]
module ProductionSnapshot
  PRISTINE_PATH = Rails.root.join("db", "production.pristine.sqlite3")
  WORK_DIR = Rails.root.join("tmp", "production_snapshot")
  RAW_COPY = WORK_DIR.join("raw.sqlite3")
  MIGRATED_TEMPLATE = WORK_DIR.join("migrated_template.sqlite3")
  ACTIVE_COPY = WORK_DIR.join("active.sqlite3")

  class << self
    def available?
      PRISTINE_PATH.exist?
    end

    # Stage a fresh copy of the pristine snapshot at +dest+.
    def stage_pristine_copy!(dest)
      FileUtils.mkdir_p(WORK_DIR)
      remove_sqlite_files(dest)
      FileUtils.cp(PRISTINE_PATH, dest)
      dest
    end

    # Point the whole app at +path+ (ActiveRecord::Base and the in-process
    # Capybara Puma server share the connection pool), run the block, then
    # reconnect to the regular test database.
    def with_connection(path)
      previous_config = ActiveRecord::Base.connection_db_config.configuration_hash
      begin
        connect(path)
        yield
      ensure
        checkpoint_and_disconnect!
        ActiveRecord::Base.establish_connection(previous_config) if previous_config
        reset_model_columns!
      end
    end

    def connect(path)
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      ActiveRecord::Base.establish_connection(config.merge(database: path.to_s))
      reset_model_columns!
    end

    # @lat: [[production-snapshot-deploy-rehearsal-harness#Why ProductionSnapshot.migrate! is built from the pending-migrations primitives, not the rake-task runner]]
    def migrate!
      previous_verbose = ActiveRecord::Migration.verbose
      begin
        ActiveRecord::Migration.verbose = false
        DataMigrate::DataMigrator.create_data_schema_table
        DataMigrate::DatabaseTasks.pending_migrations.each do |migration|
          DataMigrate::DatabaseTasks.run_migration(migration, :up)
        end
        reset_model_columns!
      ensure
        ActiveRecord::Migration.verbose = previous_verbose
      end
    end

    # @lat: [[production-snapshot-deploy-rehearsal-harness#Why ProductionSnapshot.migrate! is built from the pending-migrations primitives, not the rake-task runner]]
    def pending_migrations
      DataMigrate::DataMigrator.create_data_schema_table
      DataMigrate::DatabaseTasks.pending_migrations
    end

    # @lat: [[production-snapshot-deploy-rehearsal-harness#Why production_migration_spec.rb's helper queries come in two shapes]]
    def locale_reached_by
      if ActiveRecord::Base.connection.column_exists?("legislators", "district_id")
        ["d.sway_locale_id", "JOIN districts d ON d.id = l.district_id"]
      else
        ["l.sway_locale_id", ""]
      end
    end

    # Baltimore's locale id on this copy, or nil when the snapshot holds no
    # Baltimore locale.
    def baltimore_locale_id
      region_col = sway_locales_region_column
      ActiveRecord::Base.connection.select_value(<<~SQL)
        SELECT id FROM sway_locales
        WHERE city = 'baltimore' AND #{region_col} = 'maryland' AND country = 'united_states'
        LIMIT 1
      SQL
    end

    # @lat: [[production-snapshot-deploy-rehearsal-harness#Why person_key_sql swaps keys for names only in the Baltimore locale]]
    def person_key_sql(locale_id_sql)
      baltimore_id = baltimore_locale_id
      return "l.external_id" if baltimore_id.nil?

      "CASE WHEN #{locale_id_sql} = #{baltimore_id.to_i} " \
        "THEN LOWER(l.first_name) || ' ' || LOWER(l.last_name) " \
        "ELSE l.external_id END"
    end

    # @lat: [[production-snapshot-deploy-rehearsal-harness#Why wrong_year_cleanup_exclusion returns an empty clause once the cleanup has landed]]
    def wrong_year_cleanup_exclusion
      return "" if wrong_year_cleanup_applied?

      region_col = sway_locales_region_column
      <<~SQL
        WHERE NOT (
          lv.source = 'congress' AND lv.inferred = 0 AND lv.bill_id IN (
            SELECT DISTINCT w.bill_id
            FROM legislator_votes w
            JOIN bills b ON b.id = w.bill_id
            JOIN sway_locales sl ON sl.id = b.sway_locale_id
            WHERE sl.city = 'congress' AND sl.#{region_col} = 'congress'
              AND w.source = 'congress' AND w.inferred = 0
              AND #{BILL_VOTE_YEAR_SQL} != ''
              AND (substr(w.created_at, 1, 4) > #{BILL_VOTE_YEAR_SQL}
                   OR substr(w.updated_at, 1, 4) > #{BILL_VOTE_YEAR_SQL})
          )
        )
      SQL
    end

    # Fully migrate one template copy per process, then hand each example a
    # cheap copy of it. For specs that exercise the app against the migrated
    # data rather than the migration run itself.
    def fresh_migrated_copy!
      build_migrated_template! unless @template_built
      remove_sqlite_files(ACTIVE_COPY)
      copy_sqlite_files(MIGRATED_TEMPLATE, ACTIVE_COPY)
      ACTIVE_COPY
    end

    def wrong_year_cleanup_applied?
      data_migration_applied?(WRONG_YEAR_CLEANUP_VERSION)
    end

    def seat_correction_applied?
      data_migration_applied?(SEAT_CORRECTION_VERSION)
    end

    private

    WRONG_YEAR_CLEANUP_VERSION = "20260804000001"
    SEAT_CORRECTION_VERSION = "20260807000001"

    def sway_locales_region_column
      ActiveRecord::Base.connection.column_exists?("sway_locales", "region_name") ? "region_name" : "state"
    end

    # Whether the copy's data_migrations bookkeeping records the given data
    # migration as applied. False when the table itself is absent — a fresh
    # snapshot copy can predate the data_migrate gem entirely.
    def data_migration_applied?(version)
      table = ActiveRecord::Base.connection.select_value(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'data_migrations'"
      )
      return false if table.nil?

      ActiveRecord::Base.connection.select_value(
        "SELECT 1 FROM data_migrations WHERE version = '#{version}'"
      ).present?
    end

    # The newest chamber-vote year a bill carries, '' when it has neither date.
    BILL_VOTE_YEAR_SQL =
      "MAX(substr(COALESCE(b.house_vote_date_time_utc, ''), 1, 4), " \
      "substr(COALESCE(b.senate_vote_date_time_utc, ''), 1, 4))"

    # @lat: [[production-snapshot-deploy-rehearsal-harness#Why the template is checkpointed and disconnected before copying]]
    def checkpoint_and_disconnect!
      ActiveRecord::Base.connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    rescue ActiveRecord::ActiveRecordError, SQLite3::Exception
      nil
    ensure
      ActiveRecord::Base.connection_pool.disconnect!
    end

    def build_migrated_template!
      stage_pristine_copy!(MIGRATED_TEMPLATE)
      with_connection(MIGRATED_TEMPLATE) { migrate! }
      @template_built = true
    end

    def remove_sqlite_files(path)
      FileUtils.rm_f([path.to_s, "#{path}-wal", "#{path}-shm"])
    end

    # @lat: [[production-snapshot-deploy-rehearsal-harness#Why the template is checkpointed and disconnected before copying]]
    def copy_sqlite_files(src, dest)
      FileUtils.cp(src, dest)
      FileUtils.cp("#{src}-wal", "#{dest}-wal") if File.exist?("#{src}-wal")
    end

    def reset_model_columns!
      ActiveRecord::Base.descendants.each do |model|
        next if model.abstract_class?

        model.reset_column_information
      end
    end
  end
end

# @lat: [[production-snapshot-deploy-rehearsal-harness#Why transactional tests are turned off at the CLASS level, not from a hook]]
RSpec.shared_context "production snapshot (raw)" do
  self.use_transactional_tests = false if respond_to?(:use_transactional_tests=)

  around do |example|
    skip "db/production.pristine.sqlite3 not present" unless ProductionSnapshot.available?

    ProductionSnapshot.with_connection(
      ProductionSnapshot.stage_pristine_copy!(ProductionSnapshot::RAW_COPY)
    ) { example.run }
  end
end

RSpec.shared_context "production snapshot (migrated)" do
  self.use_transactional_tests = false if respond_to?(:use_transactional_tests=)

  around do |example|
    skip "db/production.pristine.sqlite3 not present" unless ProductionSnapshot.available?

    ProductionSnapshot.with_connection(ProductionSnapshot.fresh_migrated_copy!) { example.run }
  end
end

RSpec.configure do |config|
  # Opt in only, the same way RUN_LIVE_LLM_TESTS works: the snapshot lives
  # outside git and outside CI, so the normal suite must neither need it nor
  # touch it.
  config.filter_run_excluding(:production_snapshot) unless ENV["RUN_PROD_DB_TESTS"] == "1"
end
