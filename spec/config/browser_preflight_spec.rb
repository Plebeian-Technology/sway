# frozen_string_literal: true

require "rails_helper"

# Under verify a browser shard that loses its browser must fail, not skip
# quietly — a shard arrangement that drops its examples still reports green
# otherwise. Everywhere else the skip stays: it is a kindness for
# focused runs and for machines that legitimately have no browser.
RSpec.describe "the browser preflight guard" do
  let(:system_driver_source) { Rails.root.join("spec", "support", "system_driver.rb").read }

  # Comments stripped: the file's own prose about assert_available! or
  # required? would otherwise satisfy a check that looks for the real call.
  let(:system_driver_runnable_lines) { system_driver_source.lines.grep_v(/\A\s*#/).join }

  def stub_require_browser(value)
    original = ENV["SWAY_REQUIRE_BROWSER"]
    begin
      ENV["SWAY_REQUIRE_BROWSER"] = value
      yield
    ensure
      ENV["SWAY_REQUIRE_BROWSER"] = original
    end
  end

  it "is readable and non-empty, so a rename is a red gate rather than a silent pass" do
    expect(system_driver_source).not_to be_empty,
      "spec/support/system_driver.rb could not be read — every example below is asserting against nothing"
  end

  it "SystemBrowserPreflight.required? is true when SWAY_REQUIRE_BROWSER is 1" do
    stub_require_browser("1") do
      expect(SystemBrowserPreflight.required?).to be(true),
        "verify sets SWAY_REQUIRE_BROWSER=1 to turn a missing browser into a hard failure; required? did not see it"
    end
  end

  it "SystemBrowserPreflight.required? is false when unset, empty, or 0" do
    [nil, "", "0"].each do |value|
      stub_require_browser(value) do
        expect(SystemBrowserPreflight.required?).to be(false),
          "an exported variable left over from an earlier run turns focused browser runs into hard failures " \
          "on a machine that legitimately has no browser (value: #{value.inspect})"
      end
    end
  end

  it "leaves SWAY_REQUIRE_BROWSER unset after the examples above have run" do
    expect(ENV["SWAY_REQUIRE_BROWSER"]).to be_nil,
      "an earlier example did not restore SWAY_REQUIRE_BROWSER in its ensure block, so it would turn the hard " \
      "failure on for every later browser example in this same process"
  end

  it "assert_available! raises, naming the missing browser, when available? is false" do
    allow(SystemBrowserPreflight).to receive(:available?).and_return(false)
    expected_message = SystemBrowserPreflight.missing_requirements_message

    expect { SystemBrowserPreflight.assert_available! }.to raise_error(expected_message),
      "assert_available! must raise with the same message skip already produces, or the refusal becomes a bare exception class"
  end

  it "assert_available! returns without raising when available? is true" do
    allow(SystemBrowserPreflight).to receive(:available?).and_return(true)

    expect { SystemBrowserPreflight.assert_available! }.not_to raise_error
  end

  # Measured 2026-08-13: deleting the assert_available! call from the hook's
  # required? branch (replacing it with nil) made this example fail with the
  # "reports green having tested about 152 fewer things" message; restoring
  # the call passed it again.
  it "wires both directions into the js: true before-hook, so neither is dead code" do
    hook_body = system_driver_runnable_lines[
      /config\.before\(:each,\s*type:\s*:system,\s*js:\s*true\)\s*do(.*?)^\s{2}end\s*$/m, 1
    ]

    expect(hook_body).not_to be_nil,
      "no config.before(:each, type: :system, js: true) hook found in spec/support/system_driver.rb"
    expect(hook_body).to match(/required\?/),
      "the before-hook never calls required?, so SWAY_REQUIRE_BROWSER can never turn on the hard failure"
    expect(hook_body).to match(/assert_available!/),
      "a browser shard with no browser skips its examples and the run reports green having tested about 152 fewer things"
    expect(hook_body).to match(/skip\(/),
      "the hook no longer skips at all, so a focused run with no browser now hard-fails instead of the kindness skip"
  end

  # Measured 2026-08-13: moving the required?/assert_available! branch into a
  # config.before(:suite) hook (leaving only the skip half in before(:each))
  # made this example fail with the "runs once per process" message;
  # restoring the branch to before(:each) passed it again.
  it "fires in a before(:each) hook, not a before(:suite) hook that only runs once per process" do
    expect(system_driver_runnable_lines).not_to match(/before\(:suite/),
      "the assertion moved into a before(:suite) hook, which runs once per process — one shard with a browser " \
      "would satisfy it for every shard, even ones that lost theirs"

    hook_body = system_driver_runnable_lines[
      /config\.before\(:each,\s*type:\s*:system,\s*js:\s*true\)\s*do(.*?)^\s{2}end\s*$/m, 1
    ]

    expect(hook_body).not_to be_nil,
      "no config.before(:each, type: :system, js: true) hook found in spec/support/system_driver.rb"
    expect(hook_body).to match(/assert_available!/),
      "assert_available! is not inside the per-example before(:each) hook — a once-per-process check in one " \
      "shard proves nothing about a sibling shard that lost its browser"
  end
end
