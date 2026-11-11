# frozen_string_literal: true

require "rails_helper"

RSpec.describe Legislation::ArtifactBackupService do
  let(:artifact_root) { Pathname.new(Dir.mktmpdir("legislation-artifact-backup")) }
  let(:outside_root) { Pathname.new(Dir.mktmpdir("legislation-artifact-elsewhere")) }
  let(:prefix) { "legislation/spec/" }
  let(:remote_listing) { [] }
  let(:uploads) { [] }

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

  let(:write_artifact_file) do
    lambda do |path, contents = "x"|
      full = Pathname.new(path)
      FileUtils.mkdir_p(full.dirname)
      full.write(contents)
      full
    end
  end

  let(:fake_bucket) do
    bucket_double = instance_double(Legislation::ArtifactBucket)
    allow(bucket_double).to receive(:list).and_return(remote_listing)
    allow(bucket_double).to receive(:upload) do |object_name:, local_path:|
      uploads << [object_name, local_path.to_s]
      nil
    end
    bucket_double
  end

  let(:service) { described_class.new(bucket: fake_bucket, prefix: prefix) }

  around do |example|
    with_app_config(:legislation, **legislation_settings) { example.run }
  end

  after do
    FileUtils.remove_entry(artifact_root) if artifact_root.exist?
    FileUtils.remove_entry(outside_root) if outside_root.exist?
  end

  describe "what a run copies" do
    it "copies a file the bucket does not hold" do
      local = write_artifact_file.call(artifact_root.join("bills/text/baltimore/25-0064.md"), "text")

      report = service.call

      expect(uploads).to eq([["legislation/spec/bills/text/baltimore/25-0064.md", local.to_s]])
      expect(report).to be_ok
      expect(report.uploaded_count).to eq(1)
      expect(report.uploaded_bytes).to eq(4)
      expect(report.files_found_by_root).to eq({"bills/text" => 1})
    end

    it "copies every root the pipeline writes to" do
      write_artifact_file.call(artifact_root.join("bills/raw/baltimore/25-0064/metadata.json"), "{}")
      write_artifact_file.call(artifact_root.join("bills/text/baltimore/25-0064.md"), "t")
      write_artifact_file.call(artifact_root.join("hearings/baltimore/25-0064.json"), "{}")
      write_artifact_file.call(artifact_root.join("law/section_index.json"), "{}")
      write_artifact_file.call(artifact_root.join("diffs/baltimore/25-0064.md"), "d")
      write_artifact_file.call(artifact_root.join("prompt_dumps/baltimore/25-0064/summary.user.txt"), "p")
      write_artifact_file.call(artifact_root.join("attachments/baltimore/attachment-1.txt"), "a")

      report = service.call

      expect(uploads.map(&:first)).to contain_exactly(
        "legislation/spec/bills/raw/baltimore/25-0064/metadata.json",
        "legislation/spec/bills/text/baltimore/25-0064.md",
        "legislation/spec/hearings/baltimore/25-0064.json",
        "legislation/spec/law/section_index.json",
        "legislation/spec/diffs/baltimore/25-0064.md",
        "legislation/spec/prompt_dumps/baltimore/25-0064/summary.user.txt",
        "legislation/spec/attachments/baltimore/attachment-1.txt"
      )
      expect(report.files_found).to eq(7)
    end

    it "copies nothing when there is nothing on disk" do
      report = service.call

      expect(uploads).to be_empty
      expect(report).to be_ok
      expect(report.files_found).to eq(0)
    end
  end

  describe "comparing a local file against the stored object" do
    let(:object_name) { "legislation/spec/bills/text/baltimore/25-0064.md" }

    it "leaves a file the bucket holds at the same size and no older" do
      write_artifact_file.call(artifact_root.join("bills/text/baltimore/25-0064.md"), "text")
      allow(fake_bucket).to receive(:list).and_return(
        [SwayGoogleCloudStorage::ListedFile.new(name: object_name, size: 4, created_at: 1.hour.from_now.to_time)]
      )

      report = service.call

      expect(uploads).to be_empty
      expect(report.skipped_present_count).to eq(1)
      expect(report.files_found).to eq(1)
    end

    it "copies a file whose stored size differs" do
      write_artifact_file.call(artifact_root.join("bills/text/baltimore/25-0064.md"), "text")
      allow(fake_bucket).to receive(:list).and_return(
        [SwayGoogleCloudStorage::ListedFile.new(name: object_name, size: 9, created_at: 1.hour.from_now.to_time)]
      )

      report = service.call

      expect(uploads.map(&:first)).to eq([object_name])
      expect(report.skipped_present_count).to eq(0)
    end

    it "copies a same-size file the pipeline rewrote after the stored version was created" do
      write_artifact_file.call(artifact_root.join("bills/text/baltimore/25-0064.md"), "text")
      allow(fake_bucket).to receive(:list).and_return(
        [SwayGoogleCloudStorage::ListedFile.new(name: object_name, size: 4, created_at: 1.hour.ago.to_time)]
      )

      report = service.call

      expect(uploads.map(&:first)).to eq([object_name])
      expect(report.uploaded_count).to eq(1)
    end

    it "copies a same-size file whose stored version has no creation time" do
      write_artifact_file.call(artifact_root.join("bills/text/baltimore/25-0064.md"), "text")
      allow(fake_bucket).to receive(:list).and_return(
        [SwayGoogleCloudStorage::ListedFile.new(name: object_name, size: 4, created_at: nil)]
      )

      service.call

      expect(uploads.map(&:first)).to eq([object_name])
    end

    # @lat: [[legislation-artifact-backup#Why a rewrite with identical bytes is not copied again]]
    it "leaves a file the pipeline rewrote with identical bytes, and counts it" do
      write_artifact_file.call(artifact_root.join("bills/text/baltimore/25-0064.md"), "text")
      allow(fake_bucket).to receive(:list).and_return(
        [SwayGoogleCloudStorage::ListedFile.new(
          name: object_name, size: 4, created_at: 1.hour.ago.to_time, md5: Digest::MD5.base64digest("text")
        )]
      )

      report = service.call

      expect(uploads).to be_empty
      expect(report.skipped_identical_count).to eq(1)
      expect(report.skipped_present_count).to eq(0)
    end

    it "copies a same-size rewrite whose bytes differ from the stored ones" do
      write_artifact_file.call(artifact_root.join("bills/text/baltimore/25-0064.md"), "text")
      allow(fake_bucket).to receive(:list).and_return(
        [SwayGoogleCloudStorage::ListedFile.new(
          name: object_name, size: 4, created_at: 1.hour.ago.to_time, md5: Digest::MD5.base64digest("test")
        )]
      )

      report = service.call

      expect(uploads.map(&:first)).to eq([object_name])
      expect(report.skipped_identical_count).to eq(0)
    end

    it "leaves a same-size file with no stored creation time when the bytes match" do
      write_artifact_file.call(artifact_root.join("bills/text/baltimore/25-0064.md"), "text")
      allow(fake_bucket).to receive(:list).and_return(
        [SwayGoogleCloudStorage::ListedFile.new(
          name: object_name, size: 4, created_at: nil, md5: Digest::MD5.base64digest("text")
        )]
      )

      report = service.call

      expect(uploads).to be_empty
      expect(report.skipped_identical_count).to eq(1)
    end

    # @lat: [[legislation-artifact-backup#Why a file whose size matches is copied again when the local one is newer]]
    it "copies a same-size file whose bytes differ even when its mtime predates the stored version" do
      write_artifact_file.call(artifact_root.join("bills/text/baltimore/25-0064.md"), "text")
      allow(fake_bucket).to receive(:list).and_return(
        [SwayGoogleCloudStorage::ListedFile.new(
          name: object_name, size: 4, created_at: 1.hour.from_now.to_time, md5: Digest::MD5.base64digest("test")
        )]
      )

      report = service.call

      expect(uploads.map(&:first)).to eq([object_name])
      expect(report.skipped_present_count).to eq(0)
    end

    it "counts a content match as identical, not as present, when the mtime predates the stored version" do
      write_artifact_file.call(artifact_root.join("bills/text/baltimore/25-0064.md"), "text")
      allow(fake_bucket).to receive(:list).and_return(
        [SwayGoogleCloudStorage::ListedFile.new(
          name: object_name, size: 4, created_at: 1.hour.from_now.to_time, md5: Digest::MD5.base64digest("text")
        )]
      )

      report = service.call

      expect(uploads).to be_empty
      expect(report.skipped_identical_count).to eq(1)
      expect(report.skipped_present_count).to eq(0)
    end
  end

  describe "where the walk looks" do
    let(:legislation_settings) do
      {
        legislation_root: artifact_root.to_s,
        legislation_bills_raw_root: nil,
        legislation_bills_text_root: nil,
        legislation_hearings_root: nil,
        legislation_law_root: nil,
        legislation_diffs_root: outside_root.to_s,
        legislation_prompt_dumps_root: nil,
        legislation_attachments_root: nil
      }
    end

    it "asks the paths helper for a root that was pointed outside the base" do
      local = write_artifact_file.call(outside_root.join("baltimore/25-0064.json"), "{}")
      write_artifact_file.call(artifact_root.join("diffs/baltimore/never-written.json"), "{}")

      report = service.call

      expect(uploads).to eq([["legislation/spec/diffs/baltimore/25-0064.json", local.to_s]])
      expect(report.files_found_by_root).to eq({"diffs" => 1})
    end
  end

  describe "two roots resolving to one directory" do
    let(:legislation_settings) do
      {
        legislation_root: artifact_root.to_s,
        legislation_bills_raw_root: outside_root.to_s,
        legislation_bills_text_root: nil,
        legislation_hearings_root: nil,
        legislation_law_root: nil,
        legislation_diffs_root: outside_root.to_s,
        legislation_prompt_dumps_root: nil,
        legislation_attachments_root: nil
      }
    end

    it "copies each file once" do
      write_artifact_file.call(outside_root.join("baltimore/25-0064.json"), "{}")

      report = service.call

      expect(uploads.map(&:first)).to eq(["legislation/spec/bills/raw/baltimore/25-0064.json"])
      expect(report.files_found).to eq(1)
    end
  end

  describe "atomic-write temporary files" do
    it "never copies one, and counts it" do
      write_artifact_file.call(artifact_root.join("bills/text/baltimore/.25-0064.md.tmp-1234-deadbeef"), "half")

      report = service.call

      expect(uploads).to be_empty
      expect(report.skipped_temp_count).to eq(1)
      expect(report.files_found).to eq(0)
    end

    it "still copies the artifact sitting beside one" do
      write_artifact_file.call(artifact_root.join("bills/text/baltimore/.25-0064.md.tmp-9-abc123ef"), "half")
      write_artifact_file.call(artifact_root.join("bills/text/baltimore/25-0064.md"), "text")

      report = service.call

      expect(uploads.map(&:first)).to eq(["legislation/spec/bills/text/baltimore/25-0064.md"])
      expect(report.skipped_temp_count).to eq(1)
    end
  end

  describe "a file that disappears while the walk is running" do
    it "counts it, copies everything else, and does not stop the pass" do
      vanishing = write_artifact_file.call(artifact_root.join("bills/text/baltimore/25-0064.md"), "gone soon")
      write_artifact_file.call(artifact_root.join("law/charter.md"), "still here")

      allow_any_instance_of(Pathname).to receive(:size).and_wrap_original do |original|
        raise Errno::ENOENT, original.receiver.to_s if original.receiver == vanishing

        original.call
      end

      report = service.call

      expect(report.status).to eq(:ok)
      expect(report.skipped_vanished_count).to eq(1)
      expect(uploads.map(&:first)).to eq(["legislation/spec/law/charter.md"])
    end
  end

  describe "the floor a run checks what it found against" do
    let(:sway_locale) { create(:sway_locale) }

    it "refuses to upload when the walk found less under bills/text than the database implies" do
      create(:bill, sway_locale: sway_locale, extracted_text: "Text one.")
      write_artifact_file.call(artifact_root.join("law/charter.md"), "l")

      report = service.call

      expect(report.status).to eq(:floor_not_met)
      expect(report.floor).to eq(1)
      expect(report.files_found_by_root.fetch("bills/text", 0)).to eq(0)
      expect(uploads).to be_empty
    end

    it "completes when the walk found as many as the database implies" do
      create(:bill, sway_locale: sway_locale, extracted_text: "Text one.")
      write_artifact_file.call(artifact_root.join("bills/text/baltimore/25-0064.md"), "t")

      report = service.call

      expect(report.status).to eq(:ok)
      expect(uploads.map(&:first)).to eq(["legislation/spec/bills/text/baltimore/25-0064.md"])
    end

    it "asserts nothing when the database holds no extracted text, so an empty tree still completes" do
      report = service.call

      expect(report.status).to eq(:ok)
      expect(report.floor).to eq(0)
      expect(report.files_found).to eq(0)
    end
  end

  describe "listing the bucket" do
    it "lists once however many roots hold files" do
      write_artifact_file.call(artifact_root.join("bills/text/baltimore/25-0064.md"), "t")
      write_artifact_file.call(artifact_root.join("law/charter.md"), "l")
      write_artifact_file.call(artifact_root.join("diffs/baltimore/25-0064.md"), "d")

      report = service.call

      expect(fake_bucket).to have_received(:list).once
      expect(report.files_found).to eq(3)
    end

    it "counts what the listing returned" do
      allow(fake_bucket).to receive(:list).and_return(
        [
          SwayGoogleCloudStorage::ListedFile.new(name: "legislation/spec/law/a.md", size: 1, created_at: nil),
          SwayGoogleCloudStorage::ListedFile.new(name: "legislation/spec/law/b.md", size: 1, created_at: nil)
        ]
      )

      expect(service.call.listed_count).to eq(2)
    end

    it "stops the run instead of treating a failed listing as an empty bucket" do
      write_artifact_file.call(artifact_root.join("law/charter.md"), "l")
      allow(SwayLogging).to receive(:log_exception)
      allow(fake_bucket).to receive(:list).and_raise(StandardError, "listing refused")

      report = service.call

      expect(report.status).to eq(:listing_failed)
      expect(report).not_to be_ok
      expect(uploads).to be_empty
      expect(report.files_found).to eq(0)
      expect(SwayLogging).to have_received(:log_exception).with(
        "legislation_artifact_backup.listing_failed",
        exception: instance_of(StandardError),
        level: :error,
        prefix: "legislation/spec/"
      )
    end
  end

  describe "an upload that fails" do
    it "is recorded, and the next file is still copied" do
      write_artifact_file.call(artifact_root.join("bills/raw/baltimore/25-0064/metadata.json"), "{}")
      write_artifact_file.call(artifact_root.join("bills/text/baltimore/25-0064.md"), "text")
      allow(SwayLogging).to receive(:log_exception)
      allow(fake_bucket).to receive(:upload) do |object_name:, local_path:|
        raise IOError, "unreadable" if object_name.include?("bills/raw")

        uploads << [object_name, local_path.to_s]
        nil
      end

      report = service.call

      expect(uploads.map(&:first)).to eq(["legislation/spec/bills/text/baltimore/25-0064.md"])
      expect(report.failed.keys).to eq(["legislation/spec/bills/raw/baltimore/25-0064/metadata.json"])
      expect(report.failed.values.first).to start_with("IOError: unreadable")
      expect(report.uploaded_count).to eq(1)
      expect(report).to be_ok
    end
  end

  describe ".default_prefix" do
    it "names the environment the run belongs to" do
      expect(described_class.default_prefix).to eq("legislation/#{Rails.env}/")
    end
  end
end
