# frozen_string_literal: true

require "rails_helper"
require "support/local_error_collector"

# @lat: [[run-browser-error-reporting-spec#Why the precondition check reads the built assets, not the source]]
RSpec.describe "an error reported from the browser", type: :system do
  # Assembled, not written out: gitleaks reads this file.
  let(:planted_key) { ["sk", "ant", "api03NOTREAL0000deadbeefTESTKEY"].join("-") }
  let(:planted_email) { "planted.person@example-not-real.org" }
  let(:planted_phone) { "410-555-0142" }

  # A spec that skips forever is worse than one that fails, so say exactly which
  # of the two preconditions is missing.
  before do
    reason = LocalErrorCollector.unavailable_reason
    skip("The local error collector is not usable here: #{reason}") if reason
    skip(<<~WHY.squish) unless built_bundle_reports_errors?
      The built test bundle carries no collector address, so the browser SDK
      never starts. Under `dip run rspec` this cannot happen. Running alone,
      rebuild with VITE_RUSTRAK_DSN set — see the header of this file.
    WHY
  end

  # @lat: [[run-browser-error-reporting-spec#Why the precondition check reads the built assets, not the source]]
  def built_bundle_reports_errors?
    port = URI.parse(LocalErrorCollector.dsn).port
    Rails.public_path.glob("#{RailsVite.config.build_dir}/assets/*.js").any? { |path| path.read.include?(":#{port}") }
  rescue URI::InvalidURIError, Errno::ENOENT
    false
  end

  it "arrives at the collector, with nothing planted in it", js: true do
    marker = "planted-browser-report-#{SecureRandom.hex(4)}"
    message = "#{marker} for #{planted_email} / #{planted_phone} / #{planted_key}"

    visit root_path
    expect(page).to have_button("Continue with Phone", wait: 10)

    # From a timer, so it escapes execute_script and is genuinely uncaught —
    # the case the SDK's own handler is there for.
    page.execute_script("setTimeout(function () { throw new Error(#{message.to_json}); }, 0)")

    stored = LocalErrorCollector.new.wait_for_issue(marker)

    expect(stored).not_to be_nil,
      "The collector never received #{marker}. Check the page's connect rule names " \
      "the collector, and that the browser console holds no refusal."

    # The prize. Every other check for this reads an event in memory; this one
    # reads what is really kept, on disk, on this machine.
    payload = stored.to_json
    expect(payload).not_to include(planted_key)
    expect(payload).not_to include(planted_email)
    expect(payload).not_to include(planted_phone)
  end
end
