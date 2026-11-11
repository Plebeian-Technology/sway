# frozen_string_literal: true

require "rails_helper"

# @lat: [[boot-failure-reporting#Boot failure reporting]]
RSpec.describe BootStep do
  it "hands back what the step returned when nothing goes wrong" do
    expect(described_class.run("db:seed") { :seeded }).to eq(:seeded)
  end

  it "reports a failure and still stops the boot" do
    boom = RuntimeError.new("a seed stopped being idempotent")
    allow(Sentry).to receive(:capture_exception)

    expect { described_class.run("db:seed") { raise boom } }.to raise_error(boom)

    expect(Sentry).to have_received(:capture_exception)
      .with(boom, extra: {boot_step: "db:seed"})
  end

  it "writes the failure to the log as well, for a machine with no error service" do
    allow(Sentry).to receive(:capture_exception)
    allow(SwayLogging).to receive(:log_exception)

    expect { described_class.run("db:prepare") { raise "no such table" } }.to raise_error(/no such table/)

    expect(SwayLogging).to have_received(:log_exception)
      .with("boot_step.failed", hash_including(step: "db:prepare"))
  end

  # A missing constant or a bad require does not descend from StandardError,
  # and those are exactly the failures that stop a boot dead.
  it "reports a failure that is not a StandardError" do
    allow(Sentry).to receive(:capture_exception)

    expect { described_class.run("db:migrate") { raise NotImplementedError, "gone" } }
      .to raise_error(NotImplementedError)

    expect(Sentry).to have_received(:capture_exception)
      .with(instance_of(NotImplementedError), extra: {boot_step: "db:migrate"})
  end

  # The reporting must never replace the failure it was called about — that
  # would swap a readable error for a confusing one at the worst moment.
  it "still raises the original failure when the reporting itself breaks" do
    allow(Sentry).to receive(:capture_exception).and_raise("the collector is unreachable")

    expect { described_class.run("db:seed") { raise "the real failure" } }
      .to raise_error(/the real failure/)
  end
end
