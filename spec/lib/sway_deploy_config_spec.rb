# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "fileutils"
require "open3"

# @lat: [[deploy-config-lookup-order#Why there is no fourth step]]
RSpec.describe SwayDeployConfig do
  let(:deploy_config_dir) { Dir.mktmpdir("sway-deploy-config") }
  let(:deploy_config_path) { File.join(deploy_config_dir, "sway.env") }

  def write_deploy_config(contents)
    File.write(deploy_config_path, contents)
    ENV[described_class::FILE_VARIABLE] = deploy_config_path
    described_class.reload!
  end

  # Every NAME= appearing in one of the tracked files, comments excluded.
  def names_defined_in(relative_path)
    Rails.root.join(relative_path).readlines(chomp: true).filter_map do |line|
      stripped = line.strip
      next if stripped.empty? || stripped.start_with?("#")

      stripped.split("=").first
    end
  end

  around do |example|
    original = ENV.to_h
    begin
      example.run
    ensure
      ENV.replace(original)
      described_class.reload!
      FileUtils.remove_entry(deploy_config_dir) if File.directory?(deploy_config_dir)
    end
  end

  describe "where a value comes from" do
    it "takes an environment variable over the file" do
      write_deploy_config("SWAY_HOST=from-the-file\n")
      ENV["SWAY_HOST"] = "from-the-environment"

      expect(described_class.fetch("SWAY_HOST")).to eq("from-the-environment")
    end

    it "falls back to the file when the environment says nothing" do
      write_deploy_config("SWAY_HOST=from-the-file\n")
      ENV.delete("SWAY_HOST")

      expect(described_class.fetch("SWAY_HOST")).to eq("from-the-file")
    end

    it "treats an empty environment variable as absent, not as an answer" do
      # An exported-but-empty variable is the shape a half-written script
      # leaves behind. Reading it as a real value would point a deploy at "".
      write_deploy_config("SWAY_HOST=from-the-file\n")
      ENV["SWAY_HOST"] = ""

      expect(described_class.fetch("SWAY_HOST")).to eq("from-the-file")
    end

    it "reads no file at all without complaining" do
      ENV[described_class::FILE_VARIABLE] = File.join(deploy_config_dir, "absent.env")
      described_class.reload!
      ENV["SWAY_HOST"] = "only-in-the-environment"

      expect(described_class.fetch("SWAY_HOST")).to eq("only-in-the-environment")
      expect(described_class.file).to be_nil
    end
  end

  describe "refusing to guess" do
    it "stops rather than inventing a value" do
      write_deploy_config("")
      ENV.delete("SWAY_HOST")

      expect { described_class.fetch("SWAY_HOST") }
        .to raise_error(described_class::MissingValue, /SWAY_HOST/)
    end

    it "names the file to write and the command that fixes it" do
      write_deploy_config("")
      ENV.delete("SWAY_GCS_BUCKET_DB")

      expect { described_class.fetch("SWAY_GCS_BUCKET_DB") }
        .to raise_error(described_class::MissingValue, /sway\.env\.example/)
    end

    it "names every missing value at once, not only the first" do
      # A half-filled file otherwise costs one round trip per missing line.
      write_deploy_config("SWAY_HOST=present\n")
      ENV.delete("SWAY_STORAGE_DIR")
      ENV.delete("SWAY_GCS_BUCKET_DB")

      expect { described_class.require_values!("SWAY_HOST", "SWAY_STORAGE_DIR", "SWAY_GCS_BUCKET_DB") }
        .to raise_error(described_class::MissingValue, /SWAY_STORAGE_DIR.*SWAY_GCS_BUCKET_DB/m)
    end

    it "passes silently when the whole set is present" do
      write_deploy_config("SWAY_HOST=a\nSWAY_STORAGE_DIR=b\n")

      expect(described_class.require_values!("SWAY_HOST", "SWAY_STORAGE_DIR")).to eq(true)
    end

    it "hands back nil from [] instead of raising, where absence is a real answer" do
      write_deploy_config("")
      ENV.delete("SWAY_STANDBY_HOST")

      expect(described_class["SWAY_STANDBY_HOST"]).to be_nil
    end
  end

  describe "reading the file" do
    it "ignores blank lines and comments" do
      write_deploy_config(<<~FILE)
        # a comment

           # an indented comment
        SWAY_HOST=kept
      FILE
      ENV.delete("SWAY_HOST")

      expect(described_class.fetch("SWAY_HOST")).to eq("kept")
    end

    it "accepts a leading export, which is what a sourced file looks like" do
      write_deploy_config("export SWAY_HOST=exported\n")
      ENV.delete("SWAY_HOST")

      expect(described_class.fetch("SWAY_HOST")).to eq("exported")
    end

    it "strips one wrapping pair of quotes, so a path may contain a space" do
      write_deploy_config(%(SWAY_STORAGE_DIR="/mnt/my disk/sway"\n))
      ENV.delete("SWAY_STORAGE_DIR")

      expect(described_class.fetch("SWAY_STORAGE_DIR")).to eq("/mnt/my disk/sway")
    end

    it "keeps an equals sign that appears inside the value" do
      write_deploy_config("SWAY_LITESTREAM_PATH=litestream/a=b\n")
      ENV.delete("SWAY_LITESTREAM_PATH")

      expect(described_class.fetch("SWAY_LITESTREAM_PATH")).to eq("litestream/a=b")
    end

    it "ignores a line with no equals sign rather than dying on it" do
      write_deploy_config("this line is nonsense\nSWAY_HOST=still-read\n")
      ENV.delete("SWAY_HOST")

      expect(described_class.fetch("SWAY_HOST")).to eq("still-read")
    end
  end

  describe "the test environment" do
    it "reads the tracked fake values, so the suite behaves the same everywhere" do
      # RAILS_ENV is already "test" here. Clearing the override sends the
      # reader to its own default, which must be the tracked file and never
      # the operator's private one.
      ENV.delete(described_class::FILE_VARIABLE)
      described_class.reload!

      expect(described_class.file).to end_with(described_class::TEST_FILE)
    end

    it "never reads the operator's private file during a test run" do
      ENV.delete(described_class::FILE_VARIABLE)
      described_class.reload!

      expect(described_class.file).not_to end_with(described_class::REAL_FILE)
    end

    it "reads SWAY_TAILSCALE_IP from the tracked test values" do
      ENV.delete(described_class::FILE_VARIABLE)
      ENV.delete("SWAY_TAILSCALE_IP")
      described_class.reload!

      expect(described_class["SWAY_TAILSCALE_IP"]).to eq("sway-tailscale-test.invalid")
    end
  end

  describe "the tracked files themselves" do
    it "ships an example holding every name the test values define" do
      # The example file is the only instruction a new contributor gets. A name
      # missing from it is a value they find out about from a failed deploy.
      example_names = names_defined_in(described_class::EXAMPLE_FILE)
      test_names = names_defined_in(described_class::TEST_FILE)

      expect(example_names).to match_array(test_names)
    end

    it "keeps the operator's real file out of git" do
      stdout, _stderr, status = Open3.capture3("git", "check-ignore", described_class::REAL_FILE)

      expect(status).to be_success, "deploy/config/sway.env is committable. It holds a real address."
      expect(stdout.strip).to eq(described_class::REAL_FILE)
    end

    it "keeps the example and the test values IN git, despite the blanket .env rule" do
      [described_class::EXAMPLE_FILE, described_class::TEST_FILE].each do |tracked|
        _stdout, _stderr, status = Open3.capture3("git", "check-ignore", tracked)

        expect(status).not_to be_success, "#{tracked} is ignored, so nobody who clones Sway will receive it."
      end
    end
  end
end
