# frozen_string_literal: true

require "rails_helper"

# @lat: [[boot-failure-reporting#A missing setting is reported before it stops the boot]]
RSpec.describe "the sway.settings initializer" do
  def run_sway_settings_initializer
    initializer = Rails.application.initializers.find { |i| i.name == "sway.settings" }
    raise "no initializer named sway.settings was found" if initializer.nil?

    initializer.run(Rails.application)
  end

  it "reports a missing required setting and still stops the boot" do
    failure = Sway::Settings::MissingValues.new("upstream: SWAY_SOMETHING is required")
    allow(Sway::Settings).to receive(:build!).and_raise(failure)
    allow(SwayLogging).to receive(:log_exception)
    allow(Sentry).to receive(:capture_exception)

    expect { run_sway_settings_initializer }.to raise_error(Sway::Settings::MissingValues)

    expect(SwayLogging).to have_received(:log_exception).with(
      "boot_step.failed",
      exception: failure,
      step: "sway.settings"
    )
    expect(Sentry).to have_received(:capture_exception).with(
      failure,
      extra: {boot_step: "sway.settings"}
    )
  end

  it "reports nothing when every group builds" do
    allow(Sway::Settings).to receive(:build!).and_return(Sway::Settings)
    allow(SwayLogging).to receive(:log_exception)
    allow(Sentry).to receive(:capture_exception)

    run_sway_settings_initializer

    expect(SwayLogging).not_to have_received(:log_exception)
    expect(Sentry).not_to have_received(:capture_exception)
  end
end
