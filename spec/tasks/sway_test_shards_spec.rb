# frozen_string_literal: true

require "rails_helper"
require "sqlite3"

# @lat: [[test-shard-database-design#How spec/tasks/sway_test_shards_spec.rb is built, and what it proves about checkpointing]]
RSpec.describe "Sway::TestShardDatabases" do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:template_path) { File.join(tmp_dir, "test.sqlite3") }
  let(:described_klass) { Object.const_get("Sway::TestShardDatabases") }

  after { FileUtils.remove_entry(tmp_dir) }

  # A zero-length file would make the byte-identical example pass for the
  # wrong reason, so every fixture is a real SQLite file with a row in it.
  def create_fixture_db(path, seed: "hello")
    SQLite3::Database.new(path) do |db|
      db.execute("CREATE TABLE marker (value TEXT)")
      db.execute("INSERT INTO marker (value) VALUES (?)", [seed])
    end
  end

  it "is defined, so every example below fails for its own reason rather than one shared load-time error" do
    expect(Object.const_defined?("Sway::TestShardDatabases")).to be(true),
      "Sway::TestShardDatabases does not exist yet — task 2 creates it"
  end

  describe "#prepare" do
    let(:preparer) { described_klass.new(template_path) }

    before { create_fixture_db(template_path) }

    # @lat: [[test-shard-database-design#How spec/tasks/sway_test_shards_spec.rb is built, and what it proves about checkpointing]]
    it "checkpoints and disconnects before the first copy, so a copy never misses the WAL's latest writes" do
      expect(preparer).to receive(:checkpoint_and_disconnect!).ordered
      expect(FileUtils).to receive(:cp).at_least(:once).ordered.and_call_original

      preparer.prepare(2)
    end

    context "with the checkpoint stubbed out (file behaviour only, no real AR connection)" do
      before { allow(preparer).to receive(:checkpoint_and_disconnect!) }

      it "creates test2/test3/test4.sqlite3 for 4 workers and leaves the template in place" do
        paths = preparer.prepare(4)

        expect(paths).to eq(
          [
            template_path,
            File.join(tmp_dir, "test2.sqlite3"),
            File.join(tmp_dir, "test3.sqlite3"),
            File.join(tmp_dir, "test4.sqlite3")
          ]
        )
        expect(File.exist?(template_path)).to be(true)
        paths.drop(1).each do |path|
          expect(File.exist?(path)).to be(true), "worker database #{path} was never created"
        end
      end

      it "makes every created worker file byte-identical to the template" do
        paths = preparer.prepare(3)

        paths.drop(1).each do |path|
          expect(FileUtils.compare_file(path, template_path)).to be(true),
            "worker database #{path} diverges from the template it was copied from"
        end
      end

      # A file-exists check would pass just as happily against a truncated or
      # empty database, so this proves the copy is readable by actually
      # reading the seeded row back out through SQLite, not by comparing files.
      it "leaves the seeded row readable through SQLite in every worker copy, not just present as a file" do
        paths = preparer.prepare(3)

        paths.drop(1).each do |path|
          rows = SQLite3::Database.new(path).execute("SELECT value FROM marker")
          expect(rows).to eq([["hello"]]), "worker database #{path} does not read back the row it was copied with"
        end
      end

      it "returns worker paths that are all distinct and in the template's own directory" do
        paths = preparer.prepare(3)

        expect(paths.uniq.length).to eq(paths.length), "two workers were handed the same file to write"
        expect(paths.map { |path| File.dirname(path) }.uniq).to eq([File.dirname(template_path)]),
          "a worker database landed outside the template's own directory"
      end

      it "creates no additional file when preparing 1 worker, and does not raise" do
        before_files = Dir.children(tmp_dir).sort

        expect { preparer.prepare(1) }.not_to raise_error
        expect(Dir.children(tmp_dir).sort).to eq(before_files),
          "preparing a single worker wrote a file nobody asked for"
      end

      it "raises ArgumentError for 0 or a negative worker count, so a lane with no database is a defect, not an empty success" do
        expect { preparer.prepare(0) }.to raise_error(
          ArgumentError, "a lane with no database runs no examples and reports green"
        )
        expect { preparer.prepare(-1) }.to raise_error(ArgumentError)
      end

      it "copies the -wal sibling beside each worker file and never copies the -shm sibling" do
        File.write("#{template_path}-wal", "wal-bytes")
        File.write("#{template_path}-shm", "shm-bytes")

        worker_path = preparer.prepare(2).last

        expect(File.exist?("#{worker_path}-wal")).to be(true), "the committed writes in -wal never reached the worker"
        expect(File.read("#{worker_path}-wal")).to eq("wal-bytes")
        expect(File.exist?("#{worker_path}-shm")).to be(false),
          "a stale -shm index rebuilt by a new reader would corrupt what gets read"
      end
    end
  end

  describe "#copy_out" do
    let(:preparer) { described_klass.new(template_path) }
    let(:destination) { File.join(tmp_dir, "out") }

    before do
      create_fixture_db(template_path)
      allow(preparer).to receive(:checkpoint_and_disconnect!)
    end

    it "writes each existing worker database under the destination, named by lane and worker number" do
      preparer.prepare(3)

      written = preparer.copy_out(destination, "redlane")

      expect(written.sort).to eq(
        [
          File.join(destination, "redlane-test1.sqlite3"),
          File.join(destination, "redlane-test2.sqlite3"),
          File.join(destination, "redlane-test3.sqlite3")
        ].sort
      )
      written.each { |path| expect(File.exist?(path)).to be(true) }
    end

    it "removes a stale -wal already sitting at the destination when the fresh copy has none of its own" do
      FileUtils.mkdir_p(destination)
      stale_dest = File.join(destination, "redlane-test1.sqlite3")
      File.write(stale_dest, "leftover main file from an earlier run")
      File.write("#{stale_dest}-wal", "leftover wal from an earlier run")

      preparer.copy_out(destination, "redlane")

      expect(File.exist?("#{stale_dest}-wal")).to be(false),
        "a stale -wal beside a freshly overwritten main file would corrupt what the copy reads back"
    end

    it "creates the destination directory when it does not exist" do
      expect(File.directory?(destination)).to be(false)

      preparer.copy_out(destination, "redlane")

      expect(File.directory?(destination)).to be(true)
    end

    it "returns an empty list and does not raise when no worker databases exist yet" do
      empty_dir = Dir.mktmpdir
      begin
        empty_preparer = described_klass.new(File.join(empty_dir, "test.sqlite3"))

        expect(empty_preparer.copy_out(File.join(empty_dir, "out"), "redlane")).to eq([]),
          "a lane with zero databases runs zero examples and reports green"
      ensure
        FileUtils.remove_entry(empty_dir)
      end
    end
  end
end

# @lat: [[test-shard-database-design#Why sway:test:lane's spec expects SystemExit, and what its exclude-guard example actually proves]]
RSpec.describe "sway:test:lane" do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("sway:test:lane") }

  before { Rake::Task["sway:test:lane"].reenable }

  it "is defined" do
    expect(Rake::Task.task_defined?("sway:test:lane")).to be(true),
      "sway:test:lane does not exist — dip run verify's rspec-browser/rspec-nonbrowser lanes have nothing to call"
  end

  it "rejects an unknown lane name with a message naming both valid lanes, rather than silently running nothing" do
    expect { Rake::Task["sway:test:lane"].invoke("nosuchlane", 2) }
      .to raise_error(SystemExit)
      .and output(/"browser".*"nonbrowser"/).to_stderr
  end

  %w[browser nonbrowser].each do |lane|
    it "recognizes #{lane.inspect} as a known lane name, rather than falling through to the rejection branch" do
      Rake::Task["sway:test:prepare_shards"].reenable
      allow(Rake::Task["sway:test:prepare_shards"]).to receive(:invoke)
      allow(Kernel).to receive(:system).and_return(true)

      status = nil
      begin
        Rake::Task["sway:test:lane"].invoke(lane, 1)
      rescue SystemExit => e
        status = e.status
      end

      expect(status).to eq(0),
        "sway:test:lane[#{lane},1] exited #{status.inspect} against a stubbed-successful Kernel.system, " \
        "which only happens by falling through to the \"unknown lane\" rejection branch"
    end

    # @lat: [[test-shard-database-design#Why sway:test:lane's spec expects SystemExit, and what its exclude-guard example actually proves]]
    it "runs #{lane.inspect} against its own directory, and excludes spec/system from the non-browser lane only" do
      Rake::Task["sway:test:prepare_shards"].reenable
      allow(Rake::Task["sway:test:prepare_shards"]).to receive(:invoke)
      captured = nil #: Array[untyped]?
      allow(Kernel).to receive(:system) { |*args|
        captured = args
        true
      }

      begin
        Rake::Task["sway:test:lane"].invoke(lane, 3)
      rescue SystemExit
        nil
      end

      expect(captured).not_to be_nil, "sway:test:lane[#{lane},3] never called Kernel.system"
      expect(captured).to include((lane == "browser") ? "spec/system" : "spec"),
        "the #{lane} lane does not point at its own directory: #{captured.inspect}"
      expect(captured).to include("-n", "3"),
        "the shard count did not reach parallel_rspec, so the lane runs a different number of workers than it " \
        "was asked for: #{captured.inspect}"
      expect(captured.to_a.join(" ")).to include("ParallelTests::RSpec::RuntimeLogger"),
        "the runtime-logger format is gone, so this lane records nothing for the next run to balance against"

      if lane == "nonbrowser"
        expect(captured).to include("--exclude-pattern", "spec/system/"),
          "the non-browser lane does not exclude spec/system, so it runs every browser spec without " \
          "SWAY_REQUIRE_BROWSER — those examples skip silently and the lane still reports a healthy count"
      else
        expect(captured).not_to include("--exclude-pattern"),
          "the browser lane excludes a pattern, which can only subtract from the directory it exists to run"
      end
    end
  end

  # D-20a rescues a red lane's worker databases out of the RAM filesystem
  # before the container exits, so someone can open them. They land under one
  # shared tmp/verify/db, named by the label this task passes.
  describe "the label it rescues a red lane's databases under" do
    before do
      Rake::Task["sway:test:prepare_shards"].reenable
      allow(Rake::Task["sway:test:prepare_shards"]).to receive(:invoke)
      # False is a lane that failed, which is the only case that copies.
      allow(Kernel).to receive(:system).and_return(false)
      Rake::Task["sway:test:copy_out"].reenable
    end

    it "leads with the verify run id, so a second red run does not write over the first's" do
      captured = nil #: Array[untyped]?
      allow(Rake::Task["sway:test:copy_out"]).to receive(:invoke) { |*args| captured = args }

      with_env("SWAY_VERIFY_RUN_ID" => "93316-1786630424") do
        Rake::Task["sway:test:lane"].invoke("browser", 1)
      rescue SystemExit
        nil
      end

      expect(captured).not_to be_nil, "a failing lane never asked for its databases to be copied out"
      expect(captured.to_a.first).to eq("93316-1786630424-browser"),
        "the rescued databases are named by lane alone, so the next red run writes over them — and D-20a exists " \
        "precisely because that copy is the only chance to look at what a red lane was holding"
    end

    it "falls back to the bare lane name when nothing set a run id" do
      captured = nil #: Array[untyped]?
      allow(Rake::Task["sway:test:copy_out"]).to receive(:invoke) { |*args| captured = args }

      with_env("SWAY_VERIFY_RUN_ID" => nil) do
        Rake::Task["sway:test:lane"].invoke("nonbrowser", 1)
      rescue SystemExit
        nil
      end

      expect(captured.to_a.first).to eq("nonbrowser"),
        "running this task by hand, outside the gate, now produces a label with an empty run id stuck to the front"
    end
  end
end
