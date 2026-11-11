# frozen_string_literal: true

module Sway
  # @lat: [[test-shard-database-design#Why copying, not reloading per worker]]
  class TestShardDatabases
    def initialize(template_path)
      @template_path = template_path.to_s
    end

    # @lat: [[test-shard-database-design#Why worker_paths numbers workers the way it does]]
    def worker_paths(count)
      raise ArgumentError, "a lane with no database runs no examples and reports green" if count < 1

      (1..count).map { |worker| (worker == 1) ? @template_path : sibling_path(worker) }
    end

    def prepare(count)
      paths = worker_paths(count)
      checkpoint_and_disconnect!

      paths.drop(1).each { |path| copy_template_to(path) }
      paths
    end

    # @lat: [[test-shard-database-design#What +label+ carries in copy_out]]
    def copy_out(destination, label)
      FileUtils.mkdir_p(destination)

      existing_worker_paths.map do |worker, path|
        dest = File.join(destination.to_s, "#{label}-test#{worker}.sqlite3")
        copy_sqlite_main_and_wal(path, dest)
        dest
      end
    end

    private

    # @lat: [[test-shard-database-design#How spec/tasks/sway_test_shards_spec.rb is built, and what it proves about checkpointing]]
    def checkpoint_and_disconnect!
      ActiveRecord::Base.connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    rescue ActiveRecord::ActiveRecordError, SQLite3::Exception
      nil
    ensure
      ActiveRecord::Base.connection_pool.disconnect!
    end

    def copy_template_to(path)
      copy_sqlite_main_and_wal(@template_path, path)
    end

    # @lat: [[test-shard-database-design#Why copy_sqlite_main_and_wal clears the destination first]]
    def copy_sqlite_main_and_wal(src, dest)
      FileUtils.rm_f([dest, "#{dest}-wal", "#{dest}-shm"])
      FileUtils.cp(src, dest)
      FileUtils.cp("#{src}-wal", "#{dest}-wal") if File.exist?("#{src}-wal")
    end

    def sibling_path(worker)
      File.join(template_dir, "#{template_base}#{worker}.sqlite3")
    end

    def template_dir
      File.dirname(@template_path)
    end

    def template_base
      File.basename(@template_path, ".sqlite3")
    end

    def existing_worker_paths
      pattern = File.join(template_dir, "#{template_base}*.sqlite3")

      Dir.glob(pattern).filter_map do |path|
        suffix = File.basename(path, ".sqlite3").delete_prefix(template_base)
        next if suffix.match?(/\D/)

        [suffix.empty? ? 1 : suffix.to_i, path]
      end.sort.to_h
    end
  end
end
