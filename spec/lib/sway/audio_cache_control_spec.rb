# frozen_string_literal: true

require "rails_helper"
require "google/cloud/storage"

# @lat: [[sway-google-cloud-storage#What the bucket says about caching audio]]
RSpec.describe Sway::AudioCacheControl do
  it "writes the instruction onto an audio object that does not carry it" do
    audio = instance_double(
      Google::Cloud::Storage::File,
      name: "baltimore-maryland-united_states/22-0123.mp3",
      content_type: "audio/mpeg",
      cache_control: nil
    )
    bucket = instance_double(Google::Cloud::Storage::Bucket)
    listing = instance_double(Google::Cloud::Storage::File::List)
    allow(bucket).to receive(:files).and_return(listing)
    allow(listing).to receive(:all) { |&block| [audio].each(&block) }
    expect(audio).to receive(:cache_control=).with(SwayGoogleCloudStorage::AUDIO_CACHE_CONTROL)

    result = described_class.new(bucket).call(apply: true)

    expect(result.examined).to eq(1)
    expect(result.names).to eq(["baltimore-maryland-united_states/22-0123.mp3"])
  end

  # Running it twice must be as cheap as running it once — the second run has
  # nothing to write.
  it "leaves an object that already carries the instruction alone" do
    audio = instance_double(
      Google::Cloud::Storage::File,
      name: "locale/already.mp3",
      content_type: "audio/mpeg",
      cache_control: SwayGoogleCloudStorage::AUDIO_CACHE_CONTROL
    )
    bucket = instance_double(Google::Cloud::Storage::Bucket)
    listing = instance_double(Google::Cloud::Storage::File::List)
    allow(bucket).to receive(:files).and_return(listing)
    allow(listing).to receive(:all) { |&block| [audio].each(&block) }
    expect(audio).not_to receive(:cache_control=)

    result = described_class.new(bucket).call(apply: true)

    expect(result.already_set).to eq(1)
    expect(result.names).to eq([])
  end

  it "reports without writing when it is not told to apply" do
    audio = instance_double(
      Google::Cloud::Storage::File,
      name: "locale/quiet.mp3",
      content_type: "audio/mpeg",
      cache_control: nil
    )
    bucket = instance_double(Google::Cloud::Storage::Bucket)
    listing = instance_double(Google::Cloud::Storage::File::List)
    allow(bucket).to receive(:files).and_return(listing)
    allow(listing).to receive(:all) { |&block| [audio].each(&block) }
    expect(audio).not_to receive(:cache_control=)

    expect(described_class.new(bucket).call.names).to eq(["locale/quiet.mp3"])
  end

  it "passes over an object that is not audio" do
    icon = instance_double(
      Google::Cloud::Storage::File,
      name: "locale/an-organization.png",
      content_type: "image/png",
      cache_control: nil
    )
    bucket = instance_double(Google::Cloud::Storage::Bucket)
    listing = instance_double(Google::Cloud::Storage::File::List)
    allow(bucket).to receive(:files).and_return(listing)
    allow(listing).to receive(:all) { |&block| [icon].each(&block) }
    expect(icon).not_to receive(:cache_control=)

    expect(described_class.new(bucket).call(apply: true).examined).to eq(0)
  end

  # An Active Storage direct upload can land without a content type, so the
  # name has to be able to answer on its own.
  it "recognises audio by its name when the object has no content type" do
    audio = instance_double(
      Google::Cloud::Storage::File,
      name: "locale/summary.M4A",
      content_type: nil,
      cache_control: nil
    )
    bucket = instance_double(Google::Cloud::Storage::Bucket)
    listing = instance_double(Google::Cloud::Storage::File::List)
    allow(bucket).to receive(:files).and_return(listing)
    allow(listing).to receive(:all) { |&block| [audio].each(&block) }
    allow(audio).to receive(:cache_control=)

    expect(described_class.new(bucket).call(apply: true).examined).to eq(1)
  end

  it "asks for a week, and does not call it immutable" do
    # An audio object can be replaced at the same name, so a stale copy has to
    # expire on its own.
    expect(SwayGoogleCloudStorage::AUDIO_CACHE_CONTROL).to eq("public, max-age=604800")
  end
end
