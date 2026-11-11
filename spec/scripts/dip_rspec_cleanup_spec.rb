# frozen_string_literal: true

require "rails_helper"

# @lat: [[testing-the-toolchain#Cleanup has to survive an interrupt]]
RSpec.describe "the cleanup in dip run rspec" do
  let(:script) { Rails.root.join("scripts", "dip", "rspec.sh").read }

  # Comments stripped: the script's own prose about `exec` would otherwise
  # satisfy the check that looks for it.
  let(:runnable_lines) { script.lines.grep_v(/\A\s*#/).join }

  # Line continuations joined: the run spans several lines, and what these
  # examples are about is the whole command, not how it happens to be wrapped.
  let(:joined_lines) { runnable_lines.gsub(/\\\n\s*/, " ") }

  it "registers cleanup for a normal end and for an interrupt" do
    expect(runnable_lines).to match(/^\s*trap\s+\w+\s+EXIT\s+INT\s+TERM\s*$/),
      "no trap on EXIT INT TERM, so an interrupted run leaves its container holding the test database"
  end

  it "never hands the shell away with exec" do
    expect(runnable_lines).not_to match(/^\s*exec\s/),
      "exec replaces this shell, so the trap cannot fire and no exit code can be read"
  end

  # @lat: [[dip-rspec-cleanup-container-trap#Why the spec matches on the property, not on which command spells it]]
  it "waits on the run instead of holding it in the foreground" do
    expect(joined_lines).to match(/compose\b.*\brun\b.*&\s*$/),
      "the compose run is in the foreground, so bash holds the trap until it returns"
    expect(runnable_lines).to match(/^\s*wait\s+\$!/),
      "nothing waits on the backgrounded run, so the script would exit before the suite finishes"
  end

  it "gives the container a name for cleanup to find" do
    expect(runnable_lines).to match(/--name\s+"\$container"/),
      "without a name there is nothing for cleanup to remove"
  end

  it "reports the suite's own exit code" do
    expect(runnable_lines).to match(/status=\$\?/),
      "cleanup must capture $? first, or a failing suite reports as a pass"
    expect(runnable_lines).to match(/exit\s+"\$status"/)
  end

  # @lat: [[verification-gates#The frontend test bundle a spec run reads]]
  describe "the frontend build directory it gives its run" do
    it "is this run's own, never the directory every other run's lives inside" do
      expect(runnable_lines).to match(%r{^SWAY_VITE_BUILD_DIR="vite-test/run-}),
        "the suite builds straight into public/vite-test, the parent of every verify run's vite-test/run-<id>, in " \
        "a volume every checkout shares. Vite empties its output directory first, so an ordinary suite run would " \
        "delete a live verify run's whole bundle"
    end

    it "reaches the container, which is where the build and the manifest read both happen" do
      expect(joined_lines).to match(/-e SWAY_VITE_BUILD_DIR="\$SWAY_VITE_BUILD_DIR"/),
        "the directory this run picks on the host never reaches the container, so the container falls back to the " \
        "shared one and the isolation above is written down and delivered nowhere"
      expect(runnable_lines).not_to match(/^\s*dip compose run/),
        "a container is started through `dip compose run`, whose second shell re-splits the argument line " \
        ", so the -e flag above would never arrive"
    end

    it "sweeps abandoned build directories, and only ones too old to belong to a live run" do
      sweep = runnable_lines[/find [^\n]*vite-test[^\n]*/].to_s

      expect(sweep).to include("run-*"),
        "nothing sweeps abandoned per-run build directories, so a killed run's bundle stays in the shared volume " \
        "until somebody notices the volume is full"
      expect(sweep).to match(/-mmin \+(\d+)/),
        "the sweep has no age gate, so it can remove the build directory of a run that is still going"
      expect(sweep[/-mmin \+(\d+)/, 1].to_i).to be >= 1440,
        "the sweep reaches back less than a day, which is shorter than a suite run has taken here"
    end
  end
end
