# frozen_string_literal: true

require "rails_helper"

# @lat: [[litestream-replica-position-spec-design#Shared stubbing convention]]
RSpec.describe Litestream::ReplicaPosition do
  describe "the object layout being parsed" do
    it "returns the highest number even when level 0 has been pruned and the highest max lives at level 1" do
      service = described_class.new
      allow(service).to receive(:object_names).and_return(
        [
          "litestream/test/ltx/1/0000000000000005-000000000000000a.ltx",
          "litestream/test/ltx/2/0000000000000001-0000000000000003.ltx"
        ]
      )

      reading = service.call

      expect(reading.status).to eq(:ok)
      expect(reading.position).to eq(0xa)
    end

    it "finds the highest number at a higher level even when level 0 holds only small numbers" do
      service = described_class.new
      allow(service).to receive(:object_names).and_return(
        [
          "litestream/test/ltx/0/0000000000000001-0000000000000002.ltx",
          "litestream/test/ltx/0/0000000000000003-0000000000000004.ltx",
          "litestream/test/ltx/2/0000000000000005-00000000000003e8.ltx"
        ]
      )

      reading = service.call

      expect(reading.status).to eq(:ok)
      expect(reading.position).to eq(0x3e8)
    end

    it "ignores a name with no extension that does not match the expected shape, and returns the well-formed name's number" do
      service = described_class.new
      allow(service).to receive(:object_names).and_return(
        [
          "litestream/test/ltx/0/0000000000000001-0000000000000009",
          "litestream/test/ltx/0/0000000000000001-0000000000000009.ltx"
        ]
      )

      reading = nil
      expect { reading = service.call }.not_to raise_error
      expect(reading.status).to eq(:ok)
      expect(reading.position).to eq(9)
    end

    it "reports the empty status, not zero, when nothing in the listing matches the expected shape" do
      service = described_class.new
      allow(service).to receive(:object_names).and_return(
        [
          "litestream/test/ltx/0/", # a folder marker, not a file
          "litestream/test/ltx/0/not-a-segment", # no extension
          "litestream/test/ltx/0/zzzzzzzzzzzzzzzz-zzzzzzzzzzzzzzzz.ltx" # letters where the numbers belong
        ]
      )

      reading = service.call

      expect(reading.status).to eq(:empty)
      expect(reading.position).to be_nil
    end

    it "returns the true highest number even when one level's names use a different padding width than another's" do
      service = described_class.new
      allow(service).to receive(:object_names).and_return(
        [
          # 16-digit padding. A pattern hard-coded to this one width would
          # match this line, silently drop the 8-digit line below, and
          # answer with the wrong (lower) number.
          "litestream/test/ltx/1/0000000000000000-00000000f0000000.ltx",
          # 8-digit padding — the true highest value in this listing.
          "litestream/test/ltx/3/00000000-ffffffff.ltx"
        ]
      )

      reading = service.call

      expect(reading.status).to eq(:ok)
      expect(reading.position).to eq(0xffffffff)
    end
  end

  describe "when the listing itself is empty or fails" do
    it "reports empty, with the bucket and path still on the reading, when the listing comes back with nothing at all" do
      service = described_class.new
      allow(service).to receive(:object_names).and_return([])

      reading = service.call

      expect(reading.status).to eq(:empty)
      expect(reading.position).to be_nil
      expect(reading.bucket_name).to eq(SwayDeployConfig.fetch("SWAY_GCS_BUCKET_DB"))
      expect(reading.path).to eq(SwayDeployConfig.fetch("SWAY_LITESTREAM_PATH"))
    end

    it "carries the raised error, by class and message, when the listing cannot be read at all" do
      service = described_class.new
      error = StandardError.new("could not list the bucket")
      allow(service).to receive(:object_names).and_raise(error)

      reading = service.call

      expect(reading.status).to eq(:unreadable)
      expect(reading.position).to be_nil
      expect(reading.error.class).to eq(error.class)
      expect(reading.error.message).to eq(error.message)
      expect(reading.bucket_name).to eq(SwayDeployConfig.fetch("SWAY_GCS_BUCKET_DB"))
      expect(reading.path).to eq(SwayDeployConfig.fetch("SWAY_LITESTREAM_PATH"))
    end
  end

  describe "the narrow rescue" do
    it "lets an error raised while matching a name escape the reader, rather than reporting it as unreadable" do
      service = described_class.new
      raising_name = double("a name that blows up while being matched")
      allow(raising_name).to receive(:match).and_raise(RuntimeError, "boom inside name matching")
      allow(service).to receive(:object_names).and_return([raising_name])

      expect { service.call }.to raise_error(RuntimeError, "boom inside name matching")
    end
  end

  describe "the path and the bucket name, read fresh on every call" do
    it "answers with a different path after SWAY_LITESTREAM_PATH changes between two calls, proving it is not frozen when the file loaded" do
      service = described_class.new
      allow(service).to receive(:object_names).and_return([])

      first_path = with_env("SWAY_LITESTREAM_PATH" => "litestream/first") { service.call.path }
      second_path = with_env("SWAY_LITESTREAM_PATH" => "litestream/second") { service.call.path }

      expect(first_path).to eq("litestream/first")
      expect(second_path).to eq("litestream/second")
    end

    it "answers with a different bucket name after SWAY_GCS_BUCKET_DB changes between two calls, the same way the path does" do
      service = described_class.new
      allow(service).to receive(:object_names).and_return([])

      first_bucket = with_env("SWAY_GCS_BUCKET_DB" => "bucket-one") { service.call.bucket_name }
      second_bucket = with_env("SWAY_GCS_BUCKET_DB" => "bucket-two") { service.call.bucket_name }

      expect(first_bucket).to eq("bucket-one")
      expect(second_bucket).to eq("bucket-two")
    end

    it "reports on the reading the same path it used to build the listing prefix" do
      service = described_class.new
      captured = {} #: Hash[Symbol, String?]
      allow(service).to receive(:object_names) do |**kwargs|
        captured[:path] = kwargs[:path]
        []
      end

      reading = with_env("SWAY_LITESTREAM_PATH" => "litestream/changed") { service.call }

      # @lat: [[replication-lag-check#Why the two values are asserted together]]
      expect([captured[:path], reading.path]).to eq(["litestream/changed", "litestream/changed"])
    end

    it "raises the named-value error instead of listing under a blank prefix when the path is unset" do
      service = described_class.new
      allow(service).to receive(:object_names)
      # A config file that answers SWAY_GCS_BUCKET_DB but says nothing about
      # SWAY_LITESTREAM_PATH — deploy/config/sway.test.env answers both, so a
      # genuinely unset path needs a stand-in file that only has the other one.
      config_without_path = Rails.root.join("tmp", "sway-deploy-config-no-path-#{SecureRandom.hex(4)}.env").to_s
      begin
        File.write(config_without_path, "SWAY_GCS_BUCKET_DB=#{SwayDeployConfig.fetch("SWAY_GCS_BUCKET_DB")}\n")

        with_env("SWAY_DEPLOY_CONFIG_FILE" => config_without_path, "SWAY_LITESTREAM_PATH" => nil) do
          SwayDeployConfig.reload!

          expect { service.call }.to raise_error(SwayDeployConfig::MissingValue, /SWAY_LITESTREAM_PATH/)
        end

        expect(service).not_to have_received(:object_names)
      ensure
        File.delete(config_without_path) if File.exist?(config_without_path)
        SwayDeployConfig.reload!
      end
    end
  end
end
