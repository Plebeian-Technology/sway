# frozen_string_literal: true

namespace :sway do
  namespace :test do
    # @lat: [[test-shard-database-design#Why copying, not reloading per worker]]
    desc "Load the schema once per lane and copy it into each parallel_tests worker's own database file"
    task :prepare_shards, [:count] => :environment do |_t, args|
      template = ActiveRecord::Base.connection_db_config.database
      db_config = ActiveRecord::Base.connection_db_config

      unless File.exist?(template) && ActiveRecord::Tasks::DatabaseTasks.schema_up_to_date?(db_config)
        Rake::Task["db:schema:load"].invoke
      end

      paths = Sway::TestShardDatabases.new(template).prepare(args[:count].to_i)
      puts "#{paths.length} worker database(s) ready under #{File.dirname(template)}"
    end

    desc "D-20a: copy a lane's worker databases out of the tmpfs to a durable path before the container exits"
    task :copy_out, [:label, :destination] => :environment do |_t, args|
      template = ActiveRecord::Base.connection_db_config.database
      destination = args[:destination] || Rails.root.join("tmp", "verify", "db").to_s
      label = args[:label] || "lane"

      written = Sway::TestShardDatabases.new(template).copy_out(destination, label)

      if written.empty?
        puts "no worker databases found under #{File.dirname(template)}; nothing to copy"
      else
        puts "copied #{written.length} worker database(s) to #{destination}:"
        written.each { |path| puts "  #{path}" }
      end
    end

    # @lat: [[test-shard-database-design#Why sway:test:lane's spec expects SystemExit, and what its exclude-guard example actually proves]]
    desc "sway:test:lane[name,count]: prepare this lane's worker databases and run it sharded across count workers"
    task :lane, [:name, :count] => :environment do |_t, args|
      name = args[:name].to_s
      count = args[:count].to_i

      where =
        case name
        when "browser" then "spec/system"
        when "nonbrowser" then "spec"
        else
          abort "sway:test:lane needs a lane name of \"browser\" or \"nonbrowser\" — got #{name.inspect}"
        end

      Rake::Task["sway:test:prepare_shards"].invoke(count)

      runtime_log = "tmp/parallel_runtime_rspec.log"

      cmd = [
        "bundle", "exec", "parallel_rspec", where,
        "-n", count.to_s,
        "--runtime-log", runtime_log,
        "-o", "--format progress --format ParallelTests::RSpec::RuntimeLogger --out #{runtime_log}"
      ]

      cmd += ["--exclude-pattern", "spec/system/"] if name == "nonbrowser"

      puts "+ #{cmd.join(" ")}"
      success = Kernel.system(*cmd)
      exit_status = success ? 0 : 1

      # @lat: [[test-shard-database-design#What +label+ carries in copy_out]]
      run_id = ENV["SWAY_VERIFY_RUN_ID"].to_s
      copy_out_label = run_id.empty? ? name : "#{run_id}-#{name}"

      Rake::Task["sway:test:copy_out"].invoke(copy_out_label, Rails.root.join("tmp", "verify", "db").to_s) unless success

      exit(exit_status)
    end
  end
end
