# frozen_string_literal: true

require "rails_helper"

RSpec.describe Legislation::ArtifactRestoreService do
  let(:artifact_root) { Pathname.new(Dir.mktmpdir("legislation-artifact-live")) }
  let(:restore_root) { Pathname.new(Dir.mktmpdir("legislation-artifact-restore")) }
  let(:restore_destination) { restore_root.join("tree") }
  let(:prefix) { "legislation/spec/" }
  let(:remote_listing) { [] }
  let(:downloads) { [] }

  let(:legislation_settings) do
    {
      legislation_root: artifact_root.to_s,
      legislation_bills_raw_root: nil,
      legislation_bills_text_root: nil,
      legislation_hearings_root: nil,
      legislation_law_root: nil,
      legislation_diffs_root: nil,
      legislation_prompt_dumps_root: nil,
      legislation_attachments_root: nil
    }
  end

  let(:listed_file) do
    lambda do |name, size = 4|
      SwayGoogleCloudStorage::ListedFile.new(name: name, size: size, created_at: nil)
    end
  end

  let(:fake_bucket) do
    bucket_double = instance_double(Legislation::ArtifactBucket)
    allow(bucket_double).to receive(:list).and_return(remote_listing)
    allow(bucket_double).to receive(:download) do |object_name:, local_path:|
      downloads << [object_name, local_path.to_s]
      FileUtils.mkdir_p(File.dirname(local_path.to_s))
      File.write(local_path.to_s, "restored")
      nil
    end
    bucket_double
  end

  let(:service) { described_class.new(destination: restore_destination, bucket: fake_bucket, prefix: prefix) }

  around do |example|
    with_app_config(:legislation, **legislation_settings) { example.run }
  end

  after do
    FileUtils.remove_entry(artifact_root) if artifact_root.exist?
    FileUtils.remove_entry(restore_root) if restore_root.exist?
  end

  describe "naming the destination" do
    it "refuses to be built without one" do
      expect { described_class.new(bucket: fake_bucket, prefix: prefix) }
        .to raise_error(ArgumentError, /destination/)
    end

    it "refuses a blank one" do
      expect { described_class.new(destination: "  ", bucket: fake_bucket, prefix: prefix) }
        .to raise_error(ArgumentError, /destination/)
    end

    it "expands a relative one" do
      expect(described_class.new(destination: "tmp/restored-artifacts", bucket: fake_bucket, prefix: prefix).destination)
        .to eq(Pathname.new("tmp/restored-artifacts").expand_path)
    end
  end

  describe "refusing the live artifact tree" do
    it "refuses a destination inside a root the pipeline writes to, naming it" do
      inside = artifact_root.join("bills/text")

      expect { described_class.new(destination: inside, bucket: fake_bucket, prefix: prefix) }
        .to raise_error(described_class::LiveTreeRefused, /#{Regexp.escape(inside.to_s)}/)
    end

    it "refuses the base root itself" do
      expect { described_class.new(destination: artifact_root, bucket: fake_bucket, prefix: prefix) }
        .to raise_error(described_class::LiveTreeRefused)
    end

    it "refuses a destination that holds the live tree" do
      expect { described_class.new(destination: artifact_root.parent, bucket: fake_bucket, prefix: prefix) }
        .to raise_error(described_class::LiveTreeRefused)
    end

    it "refuses a root that was pointed outside the base tree" do
      elsewhere = restore_root.join("diffs-live")

      with_app_config(:legislation, **legislation_settings.merge(legislation_diffs_root: elsewhere.to_s)) do
        expect { described_class.new(destination: elsewhere, bucket: fake_bucket, prefix: prefix) }
          .to raise_error(described_class::LiveTreeRefused)
      end
    end

    it "refuses a destination that is a symlink into the live tree" do
      FileUtils.mkdir_p(artifact_root.join("bills/text"))
      linked = restore_root.join("looks-harmless")
      File.symlink(artifact_root.to_s, linked.to_s)

      expect { described_class.new(destination: linked.join("bills"), bucket: fake_bucket, prefix: prefix) }
        .to raise_error(described_class::LiveTreeRefused)
    end

    it "refuses when the configured live root itself is a symlink and destination names the real path" do
      real_live = restore_root.join("real-live")
      FileUtils.mkdir_p(real_live.join("bills/text"))
      symlinked_live = restore_root.join("symlinked-live")
      File.symlink(real_live.to_s, symlinked_live.to_s)

      with_app_config(:legislation, **legislation_settings.merge(legislation_root: symlinked_live.to_s)) do
        expect { described_class.new(destination: real_live.join("bills"), bucket: fake_bucket, prefix: prefix) }
          .to raise_error(described_class::LiveTreeRefused)
      end
    end

    it "allows the live tree when the caller says so" do
      expect { described_class.new(destination: artifact_root, bucket: fake_bucket, prefix: prefix, allow_live_tree: true) }
        .not_to raise_error
    end

    it "allows a destination outside the tree without being asked" do
      expect { service }.not_to raise_error
    end
  end

  describe "what a run writes" do
    let(:remote_listing) do
      [
        listed_file.call("legislation/spec/bills/text/baltimore/25-0064.md", 4),
        listed_file.call("legislation/spec/diffs/baltimore/25-0064.md", 6)
      ]
    end

    it "puts each object under the destination at its bucket key" do
      report = service.call

      expect(downloads.map(&:last)).to contain_exactly(
        restore_destination.join("bills/text/baltimore/25-0064.md").to_s,
        restore_destination.join("diffs/baltimore/25-0064.md").to_s
      )
      expect(restore_destination.join("bills/text/baltimore/25-0064.md")).to exist
      expect(report).to be_ok
      expect(report.listed_count).to eq(2)
      expect(report.downloaded_count).to eq(2)
      expect(report.downloaded_bytes).to eq(10)
      expect(report.destination).to eq(restore_destination)
    end
  end

  describe "restoring one part of the tree" do
    let(:remote_listing) { [listed_file.call("legislation/spec/diffs/baltimore/25-0064.md", 6)] }
    let(:service) { described_class.new(destination: restore_destination, bucket: fake_bucket, prefix: prefix, only: "diffs") }

    it "narrows the listing to that root and still writes it at its bucket key" do
      service.call

      expect(fake_bucket).to have_received(:list).with(prefix: "legislation/spec/diffs/")
      expect(downloads.map(&:last)).to eq([restore_destination.join("diffs/baltimore/25-0064.md").to_s])
    end

    it "refuses a part the backup does not write" do
      expect { described_class.new(destination: restore_destination, bucket: fake_bucket, prefix: prefix, only: "secrets") }
        .to raise_error(ArgumentError, /secrets/)
    end
  end

  describe "an object name that would escape the destination" do
    let(:remote_listing) do
      [
        listed_file.call("legislation/spec/../../../etc/passwd", 1),
        listed_file.call("legislation/spec//etc/passwd", 1),
        listed_file.call("legislation/other/law/charter.md", 1),
        listed_file.call("legislation/spec/law/charter.md", 3)
      ]
    end

    it "is refused, as is one carrying another prefix, and the rest is still written" do
      allow(SwayLogging).to receive(:warn)

      report = service.call

      expect(downloads.map(&:last)).to eq([restore_destination.join("law/charter.md").to_s])
      expect(report.skipped_unsafe_count).to eq(3)
      expect(report.downloaded_count).to eq(1)
      expect(downloads.map(&:last)).to all(start_with("#{restore_destination}/"))
      expect(SwayLogging).to have_received(:warn).with(
        "legislation_artifact_restore.unsafe_object_name",
        object_name: "legislation/spec/../../../etc/passwd",
        prefix: "legislation/spec/"
      )
    end
  end

  describe "listing the bucket" do
    it "writes nothing when the listing fails" do
      allow(SwayLogging).to receive(:log_exception)
      allow(fake_bucket).to receive(:list).and_raise(StandardError, "listing refused")

      report = service.call

      expect(report.status).to eq(:listing_failed)
      expect(report).not_to be_ok
      expect(downloads).to be_empty
      expect(restore_destination).not_to exist
      expect(SwayLogging).to have_received(:log_exception).with(
        "legislation_artifact_restore.listing_failed",
        exception: instance_of(StandardError),
        level: :error,
        prefix: "legislation/spec/"
      )
    end
  end

  describe "a download that fails" do
    let(:remote_listing) do
      [
        listed_file.call("legislation/spec/bills/text/baltimore/25-0064.md", 4),
        listed_file.call("legislation/spec/law/charter.md", 3)
      ]
    end

    it "is recorded, and the next object is still written" do
      allow(SwayLogging).to receive(:log_exception)
      allow(fake_bucket).to receive(:download) do |object_name:, local_path:|
        raise IOError, "no such object" if object_name.include?("bills/text")

        downloads << [object_name, local_path.to_s]
        nil
      end

      report = service.call

      expect(downloads.map(&:first)).to eq(["legislation/spec/law/charter.md"])
      expect(report.failed.keys).to eq(["legislation/spec/bills/text/baltimore/25-0064.md"])
      expect(report.failed.values.first).to start_with("IOError: no such object")
      expect(report.downloaded_count).to eq(1)
      expect(report).to be_ok
    end
  end
end
