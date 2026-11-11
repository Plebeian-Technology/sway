# frozen_string_literal: true

require "rails_helper"

# The three statuses never collapse into each other. Steep
# enforces the union wherever it can see the call site; this spec covers the
# runtime guard for a caller that bypasses it.
RSpec.describe Litestream::ReplicaReading do
  it "accepts each of the three recognized statuses" do
    Litestream::ReplicaReading::STATUSES.each do |status|
      reading = described_class.new(status: status, position: nil, bucket_name: "bucket", path: "path", error: nil)

      expect(reading.status).to eq(status)
    end
  end

  # Only a caller bypassing Steep's union reaches this. The type checker cannot
  # enforce it, so the raise is all that stands between a bad symbol and a
  # reading that lies about what happened.
  it "refuses an unrecognized status" do
    bad_status = :nonsense #: untyped

    expect {
      described_class.new(status: bad_status, position: nil, bucket_name: "bucket", path: "path", error: nil)
    }.to raise_error(ArgumentError, /status must be one of/)
  end
end
