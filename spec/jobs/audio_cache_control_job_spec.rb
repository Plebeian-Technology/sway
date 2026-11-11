# frozen_string_literal: true

require "rails_helper"
require "google/cloud/storage"

# @lat: [[sway-google-cloud-storage#What the bucket says about caching audio]]
RSpec.describe AudioCacheControlJob do
  describe "#perform" do
    it "writes the instruction on the objects without it and reports all three counts" do
      without = instance_double(
        Google::Cloud::Storage::File,
        name: "baltimore-maryland-united_states/22-0123.mp3",
        content_type: "audio/mpeg",
        cache_control: nil
      )
      current = instance_double(
        Google::Cloud::Storage::File,
        name: "baltimore-maryland-united_states/22-0456.mp3",
        content_type: "audio/mpeg",
        cache_control: SwayGoogleCloudStorage::AUDIO_CACHE_CONTROL
      )
      icon = instance_double(
        Google::Cloud::Storage::File,
        name: "baltimore-maryland-united_states/an-organization.png",
        content_type: "image/png",
        cache_control: nil
      )
      listing = instance_double(Google::Cloud::Storage::File::List)
      allow(listing).to receive(:all) { |&block| [without, current, icon].each(&block) }
      bucket = instance_double(Google::Cloud::Storage::Bucket, files: listing)
      storage = instance_double(Google::Cloud::Storage::Project)
      allow(storage).to receive(:bucket)
        .with(SwayGoogleCloudStorage::BUCKETS[:ASSETS], skip_lookup: true)
        .and_return(bucket)
      allow(SwayGoogleCloudStorage).to receive(:storage).and_return(storage)

      expect(without).to receive(:cache_control=).with(SwayGoogleCloudStorage::AUDIO_CACHE_CONTROL)
      expect(icon).not_to receive(:cache_control=)
      expect(SwayLogging).to receive(:info)
        .with(a_string_matching(/\[AudioCacheControlJob\] complete seen=2 written=1 already_current=1/))

      expect(described_class.new.perform).to eq(1)
    end

    # The pass exists to be run every week, so a week where nothing was uploaded
    # must cost one listing and no writes.
    it "writes nothing when every audio object already carries the instruction" do
      current = instance_double(
        Google::Cloud::Storage::File,
        name: "locale/already.mp3",
        content_type: "audio/mpeg",
        cache_control: SwayGoogleCloudStorage::AUDIO_CACHE_CONTROL
      )
      listing = instance_double(Google::Cloud::Storage::File::List)
      allow(listing).to receive(:all) { |&block| [current].each(&block) }
      bucket = instance_double(Google::Cloud::Storage::Bucket, files: listing)
      storage = instance_double(Google::Cloud::Storage::Project, bucket: bucket)
      allow(SwayGoogleCloudStorage).to receive(:storage).and_return(storage)

      expect(current).not_to receive(:cache_control=)
      allow(SwayLogging).to receive(:info)

      expect(described_class.new.perform).to eq(0)
    end
  end

  it "runs on the background queue, beside the other weekly sweeps" do
    expect(described_class.new.queue_name).to eq("background")
  end
end
