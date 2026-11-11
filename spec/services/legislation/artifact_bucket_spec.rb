# frozen_string_literal: true

require "rails_helper"

RSpec.describe Legislation::ArtifactBucket do
  # @lat: [[legislation-artifact-backup#Why the bucket name is resolved on use rather than on load]]
  let(:bucket) { described_class.new(bucket_name: "artifact-bucket-under-test") }

  describe "#bucket_name" do
    it "keeps the name it was built with" do
      expect(bucket.bucket_name).to eq("artifact-bucket-under-test")
    end

    it "falls back to deploy config" do
      allow(SwayDeployConfig).to receive(:fetch).with("SWAY_GCS_BUCKET_LEGISLATION").and_return("bucket-from-deploy-config")

      expect(described_class.new.bucket_name).to eq("bucket-from-deploy-config")
    end

    it "does not reach deploy config until a caller needs the name" do
      allow(SwayDeployConfig).to receive(:fetch).with("SWAY_GCS_BUCKET_LEGISLATION").and_raise(SwayDeployConfig::MissingValue)

      expect { described_class.new }.not_to raise_error
      expect { described_class.new.bucket_name }.to raise_error(SwayDeployConfig::MissingValue)
    end
  end

  describe "#upload" do
    it "sends the local file to the object name it was given" do
      captured = {} #: Hash[Symbol, untyped]
      allow(bucket).to receive(:upload_file) { |**kwargs| captured.merge!(kwargs) }

      result = bucket.upload(object_name: "legislation/test/bills/text/x.md", local_path: Pathname.new("/tmp/x.md"))

      expect(result).to be_nil
      expect(captured[:bucket_name]).to eq("artifact-bucket-under-test")
      expect(captured[:bucket_file_path]).to eq("legislation/test/bills/text/x.md")
      expect(captured[:local_file_path]).to eq("/tmp/x.md")
    end
  end

  describe "#download" do
    it "fetches the object into the local path it was given" do
      captured = {} #: Hash[Symbol, untyped]
      allow(bucket).to receive(:download_file) { |**kwargs| captured.merge!(kwargs) }

      result = bucket.download(object_name: "legislation/test/bills/text/x.md", local_path: Pathname.new("/tmp/restored/x.md"))

      expect(result).to be_nil
      expect(captured[:bucket_name]).to eq("artifact-bucket-under-test")
      expect(captured[:bucket_file_path]).to eq("legislation/test/bills/text/x.md")
      expect(captured[:local_file_path]).to eq("/tmp/restored/x.md")
    end
  end

  describe "#list" do
    it "returns the listing for the prefix it was given" do
      listed = SwayGoogleCloudStorage::ListedFile.new(
        name: "legislation/test/diffs/a.diff",
        size: 12,
        created_at: Time.current.to_time
      )
      allow(bucket).to receive(:list_files)
        .with(bucket_name: "artifact-bucket-under-test", prefix: "legislation/test/")
        .and_return([listed])

      expect(bucket.list(prefix: "legislation/test/")).to eq([listed])
    end
  end

  describe "deletion" do
    it "is not part of the adapter" do
      expect(bucket).not_to respond_to(:delete)
      expect(described_class.instance_methods(false)).not_to include(:delete, :delete_file)
    end

    it "is left alone in the shared storage module for its other callers" do
      expect(SwayGoogleCloudStorage.instance_methods).to include(:delete_file)
    end
  end
end
