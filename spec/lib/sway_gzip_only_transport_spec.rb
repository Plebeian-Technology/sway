# frozen_string_literal: true

require "rails_helper"

# @lat: [[local-error-reporting-design#Why SwayGzipOnlyTransport always compresses]]
# @lat: [[steep-typed-spec-helpers#Why spec/jobs/backup_database_job_spec.rb writes its instance_double stub inside each example, not in a let]]
RSpec.describe SwayGzipOnlyTransport do
  # send, because the gem keeps this private and the override matches it.
  it "compresses a payload far below the gem's 30KB threshold" do
    config = Sentry::Configuration.new
    SwayLocalErrorReporting.apply(config, dsn: "http://dsnpublicid@localhost:8482/1")

    expect(described_class.new(config).send(:should_compress?, "tiny")).to be(true)
  end

  # The discriminating half. Without it the example above would pass against
  # the stock transport and prove nothing.
  it "differs from the stock transport, which leaves a small payload uncompressed" do
    config = Sentry::Configuration.new
    SwayLocalErrorReporting.apply(config, dsn: "http://dsnpublicid@localhost:8482/1")

    expect(Sentry::HTTPTransport.new(config).send(:should_compress?, "tiny")).to be(false)
  end

  it "is the transport the local settings install" do
    config = Sentry::Configuration.new
    SwayLocalErrorReporting.apply(config, dsn: "http://dsnpublicid@localhost:8482/1")

    expect(config.transport.transport_class).to eq(described_class)
  end
end
