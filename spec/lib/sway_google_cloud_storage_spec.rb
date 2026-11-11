# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "active_storage/service/gcs_service"

# @lat: [[keyfile-write-directory#Why write_keyfile controls its own disk writes]]
RSpec.describe SwayGoogleCloudStorage do
  describe ".credentials (production keyfile write)" do
    it "writes the keyfile with owner-only 0600 permissions" do
      tmp_dir = Dir.mktmpdir
      begin
        tmp_path = File.join(tmp_dir, "sway-bucket-storage.json")
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        allow(described_class).to receive(:keyfile_path).and_return(tmp_path)
        fake_creds = double("credentials")
        allow(fake_creds).to receive(:dig) { |*keys| "stub-#{keys.last}" }
        allow(Rails.application).to receive(:credentials).and_return(fake_creds)

        described_class.credentials

        expect(File.stat(tmp_path).mode & 0o777).to eq(0o600)
      ensure
        FileUtils.rm_rf(tmp_dir)
      end
    end

    it "does not rewrite an up-to-date keyfile" do
      tmp_dir = Dir.mktmpdir
      begin
        tmp_path = File.join(tmp_dir, "sway-bucket-storage.json")
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        allow(described_class).to receive(:keyfile_path).and_return(tmp_path)
        fake_creds = double("credentials")
        allow(fake_creds).to receive(:dig) { |*keys| "stub-#{keys.last}" }
        allow(Rails.application).to receive(:credentials).and_return(fake_creds)
        allow(File).to receive(:open).and_call_original

        described_class.credentials
        described_class.credentials

        # The first call writes. The second sees the same contents and writes nothing.
        expect(File).to have_received(:open).with(tmp_path, "w").once
      ensure
        FileUtils.rm_rf(tmp_dir)
      end
    end

    it "emits no stdout" do
      tmp_dir = Dir.mktmpdir
      begin
        tmp_path = File.join(tmp_dir, "sway-bucket-storage.json")
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        allow(described_class).to receive(:keyfile_path).and_return(tmp_path)
        fake_creds = double("credentials")
        allow(fake_creds).to receive(:dig) { |*keys| "stub-#{keys.last}" }
        allow(Rails.application).to receive(:credentials).and_return(fake_creds)

        expect { described_class.credentials }.not_to output.to_stdout
      ensure
        FileUtils.rm_rf(tmp_dir)
      end
    end

    it "returns the keyfile path (config/storage.yml consumer contract)" do
      tmp_dir = Dir.mktmpdir
      begin
        tmp_path = File.join(tmp_dir, "sway-bucket-storage.json")
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        allow(described_class).to receive(:keyfile_path).and_return(tmp_path)
        fake_creds = double("credentials")
        allow(fake_creds).to receive(:dig) { |*keys| "stub-#{keys.last}" }
        allow(Rails.application).to receive(:credentials).and_return(fake_creds)

        expect(described_class.credentials).to eq(tmp_path)
      ensure
        FileUtils.rm_rf(tmp_dir)
      end
    end

    it "creates a parent directory that does not exist yet" do
      tmp_dir = Dir.mktmpdir
      begin
        tmp_path = File.join(tmp_dir, "nested", "sway-bucket-storage.json")
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        allow(described_class).to receive(:keyfile_path).and_return(tmp_path)
        fake_creds = double("credentials")
        allow(fake_creds).to receive(:dig) { |*keys| "stub-#{keys.last}" }
        allow(Rails.application).to receive(:credentials).and_return(fake_creds)

        described_class.credentials

        expect(File.exist?(tmp_path)).to be(true)
      ensure
        FileUtils.rm_rf(tmp_dir)
      end
    end
  end

  # @lat: [[sway-google-cloud-storage#Browser uploads depend on the live bucket policy]]
  describe ".configure" do
    let(:bucket) { double("bucket") }
    let(:storage) { double("storage", bucket: bucket) }
    let(:cors_builder) { double("cors_builder") }

    before do
      allow(described_class).to receive(:storage).and_return(storage)
      allow(bucket).to receive(:cors).and_yield(cors_builder)
      allow(cors_builder).to receive(:clear)
      allow(cors_builder).to receive(:add_rule)
      allow(SwayLogging).to receive(:info)
    end

    it "sets the CORS policy with approved origins, methods, headers, and max_age" do
      described_class.configure(bucket_name: "test-bucket")

      expect(storage).to have_received(:bucket).with("test-bucket")
      expect(cors_builder).to have_received(:clear)
      expect(cors_builder).to have_received(:add_rule).with(
        described_class.bucket_cors_origins,
        %w[PUT GET],
        headers: %w[
          Content-Type
          Content-MD5
          Content-Disposition
          x-goog-content-length-range
          x-goog-resumable
        ],
        max_age: 3600
      )
      expect(SwayLogging).to have_received(:info).with(
        "SwayGoogleCloudStorage.configure - Set CORS policies for bucket test-bucket"
      )
    end

    it "populates a real Cors builder object with the exact rules" do
      real_cors = Google::Cloud::Storage::Bucket::Cors.new
      allow(bucket).to receive(:cors).and_yield(real_cors)

      described_class.configure(bucket_name: "test-bucket")

      expect(real_cors.size).to eq(1)
      rule = real_cors.first
      expect(rule.origin).to eq(described_class.bucket_cors_origins)
      expect(rule.methods).to eq(%w[PUT GET])
      expect(rule.headers).to eq(%w[Content-Type Content-MD5 Content-Disposition x-goog-content-length-range x-goog-resumable])
      expect(rule.max_age).to eq(3600)
    end

    it "allows every header Active Storage tells a browser to send on a direct upload" do
      real_cors = Google::Cloud::Storage::Bucket::Cors.new
      allow(bucket).to receive(:cors).and_yield(real_cors)
      service = ActiveStorage::Service::GCSService.new(bucket: "test-bucket")
      upload_headers = service.headers_for_direct_upload(
        "key",
        checksum: "checksum",
        content_length: 1,
        content_type: "image/jpeg",
        filename: ActiveStorage::Filename.new("logo.jpg"),
        disposition: :inline
      )

      described_class.configure(bucket_name: "test-bucket")

      allowed = real_cors.first.headers.map(&:downcase)
      expect(allowed).to include(*["Content-Type", *upload_headers.keys].map(&:downcase))
    end
  end

  describe ".bucket_cors_origins" do
    it "is the fixed origin list when no extra origins are configured" do
      with_env("SWAY_GCS_EXTRA_CORS_ORIGINS" => nil) do
        expect(described_class.bucket_cors_origins).to eq(SwayGoogleCloudStorage::BUCKET_CORS_ORIGINS)
      end
    end

    it "appends each comma-separated SWAY_GCS_EXTRA_CORS_ORIGINS entry once" do
      with_env("SWAY_GCS_EXTRA_CORS_ORIGINS" => " https://dev.example.test, ,https://preview.example.test,https://sway.vote") do
        expect(described_class.bucket_cors_origins).to eq(
          SwayGoogleCloudStorage::BUCKET_CORS_ORIGINS + %w[https://dev.example.test https://preview.example.test]
        )
      end
    end
  end

  describe "#list_files" do
    let(:gcs_includer) { Class.new { include SwayGoogleCloudStorage }.new }

    let(:paged_file_list) do
      lambda do |pages|
        walk = Enumerator.new do |yielder|
          pages.each { |page| page.each { |item| yielder << item } }
        end
        double("file_list", all: walk)
      end
    end

    def gcs_fake_file(name:, size:, created_at: Time.zone.now, md5: nil)
      double("file", name: name, size: size, created_at: created_at, md5: md5)
    end

    it "returns each object's name and size" do
      file_a = gcs_fake_file(name: "db/test/a.sqlite3", size: 10)
      file_b = gcs_fake_file(name: "db/test/b.sqlite3", size: 20)
      bucket = double("bucket", files: paged_file_list.call([[file_a, file_b]]))
      allow(gcs_includer).to receive(:storage).and_return(double("storage", bucket: bucket))

      result = gcs_includer.list_files(bucket_name: "my-bucket", prefix: "db/test/")

      expect(result.map(&:name)).to eq(["db/test/a.sqlite3", "db/test/b.sqlite3"])
      expect(result.map(&:size)).to eq([10, 20])
      expect(bucket).to have_received(:files).with(prefix: "db/test/")
    end

    it "carries each object's md5 from the listing" do
      file = gcs_fake_file(name: "db/test/a.sqlite3", size: 10, md5: "CY9rzUYh03PK3k6DJie09g==")
      bucket = double("bucket", files: paged_file_list.call([[file]]))
      allow(gcs_includer).to receive(:storage).and_return(double("storage", bucket: bucket))

      result = gcs_includer.list_files(bucket_name: "my-bucket", prefix: "db/test/")

      expect(result.map(&:md5)).to eq(["CY9rzUYh03PK3k6DJie09g=="])
    end

    it "pages through results spread across more than one page" do
      page_one = Array.new(3) { |i| gcs_fake_file(name: "db/test/page1-#{i}.sqlite3", size: i) }
      page_two = Array.new(2) { |i| gcs_fake_file(name: "db/test/page2-#{i}.sqlite3", size: i) }
      bucket = double("bucket", files: paged_file_list.call([page_one, page_two]))
      allow(gcs_includer).to receive(:storage).and_return(double("storage", bucket: bucket))

      result = gcs_includer.list_files(bucket_name: "my-bucket", prefix: "db/test/")

      expect(result.map(&:name)).to eq((page_one + page_two).map(&:name))
    end

    it "returns an empty array without touching storage when bucket_name is blank" do
      expect(gcs_includer.list_files(bucket_name: nil, prefix: "db/test/")).to eq([])
    end

    it "returns an empty array without touching storage when prefix is blank" do
      expect(gcs_includer.list_files(bucket_name: "my-bucket", prefix: "")).to eq([])
    end
  end

  # @lat: [[sway-google-cloud-storage#Why a download lands through a temporary file]]
  describe "#download_directory" do
    let(:gcs_includer) { Class.new { include SwayGoogleCloudStorage }.new }
    let(:destination) { Dir.mktmpdir }

    after { FileUtils.remove_entry(destination) }

    def gcs_yielding_file_list(files)
      list = double("file_list")
      allow(list).to receive(:all) { |&block| files.each(&block) }
      list
    end

    def gcs_stub_bucket_with(files)
      bucket = double("bucket", files: gcs_yielding_file_list(files))
      allow(gcs_includer).to receive(:storage).and_return(double("storage", bucket: bucket))
    end

    it "downloads to a temporary sibling and renames it into place" do
      written_to = ""
      file = double("file", name: "geojson/city.geojson")
      allow(file).to receive(:download) do |path|
        written_to = path
        File.write(path, "{}")
      end
      gcs_stub_bucket_with([file])

      gcs_includer.download_directory(
        bucket_name: "my-bucket",
        bucket_directory_name: "geojson",
        local_directory_name: destination
      )

      final = File.join(destination, "geojson", "city.geojson")
      expect(written_to).not_to eq(final)
      expect(File.basename(written_to)).to start_with(".city.geojson.download-")
      expect(File.read(final)).to eq("{}")
      expect(Dir.children(File.dirname(final))).to eq(["city.geojson"])
    end

    it "keeps the previous file and leaves no litter when verification fails" do
      final = File.join(destination, "geojson", "city.geojson")
      FileUtils.mkdir_p(File.dirname(final))
      File.write(final, "previous")

      file = double("file", name: "geojson/city.geojson")
      allow(file).to receive(:download) do |path|
        File.write(path, "half a file")
        raise Google::Cloud::Storage::FileVerificationError, "crc32c verification failed"
      end
      gcs_stub_bucket_with([file])

      expect {
        gcs_includer.download_directory(
          bucket_name: "my-bucket",
          bucket_directory_name: "geojson",
          local_directory_name: destination
        )
      }.to raise_error(Google::Cloud::Storage::FileVerificationError)

      expect(File.read(final)).to eq("previous")
      expect(Dir.children(File.dirname(final))).to eq(["city.geojson"])
    end
  end
end
