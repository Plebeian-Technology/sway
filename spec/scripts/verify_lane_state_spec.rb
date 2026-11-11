# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tempfile"

# The gate's whole promise is that it cannot report green while running fewer
# checks than it was asked to. Every other check on verify.sh reads the script
# as TEXT, so a regex still matches an if-chain whose branches have been
# reordered into deciding the opposite. These call the decision instead.
RSpec.describe "how verify.sh judges a finished lane" do
  # bash, named explicitly: the decision uses [[ ]] and BASH_REMATCH, and this
  # machine's login shell is zsh, which would also stop treating an unquoted
  # list as several words.
  def lane_state(exit_code:, docker_exit: "", oom: "false", examples: "", failures: "", ok_codes: nil)
    args = [docker_exit, oom, exit_code.to_s, examples.to_s, failures.to_s]
    args << ok_codes if ok_codes

    out, err, status = Open3.capture3(
      "bash", "-c", 'source scripts/dip/verify-lib.sh; lane_state "$@"', "bash", *args,
      chdir: Rails.root.to_s
    )
    raise "lane_state failed (#{status.exitstatus}): #{err}" unless status.success?
    out.strip
  end

  def lane_totals(log_body)
    Tempfile.create("verify-lane-log") do |file|
      file.write(log_body)
      file.flush
      out, err, status = Open3.capture3(
        "bash", "-c", 'source scripts/dip/verify-lib.sh; rspec_lane_totals "$1"', "bash", file.path,
        chdir: Rails.root.to_s
      )
      raise "rspec_lane_totals failed (#{status.exitstatus}): #{err}" unless status.success?
      out.strip
    end
  end

  def gate_totals(log_body)
    Tempfile.create("verify-rake-gates-log") do |file|
      file.write(log_body)
      file.flush
      out, err, status = Open3.capture3(
        "bash", "-c", 'source scripts/dip/verify-lib.sh; rake_gates_totals "$1"', "bash", file.path,
        chdir: Rails.root.to_s
      )
      raise "rake_gates_totals failed (#{status.exitstatus}): #{err}" unless status.success?
      out.strip
    end
  end

  it "exists as its own file, so these examples test the code the gate runs" do
    expect(Rails.root.join("scripts", "dip", "verify-lib.sh")).to exist,
      "scripts/dip/verify-lib.sh is gone — either it was re-inlined into verify.sh, in which case these examples " \
      "test nothing that runs, or the gate is broken outright"
  end

  describe "a lane that never reached a result" do
    it "is did-not-complete when the kernel killed its container" do
      expect(lane_state(docker_exit: "137", exit_code: 137)).to eq("did-not-complete")
    end

    it "is did-not-complete when the container ran out of memory" do
      expect(lane_state(oom: "true", exit_code: 1)).to eq("did-not-complete")
    end

    it "is did-not-complete on an exit code the tool does not document" do
      # A lane with no branch in run_lane() returns 2 for exactly this reason.
      expect(lane_state(exit_code: 2)).to eq("did-not-complete")
      expect(lane_state(exit_code: 139)).to eq("did-not-complete")
    end

    it "prefers did-not-complete over red when a killed lane also counted failures" do
      state = lane_state(docker_exit: "137", exit_code: 137, examples: 800, failures: 12)
      expect(state).to eq("did-not-complete"),
        "a lane killed part-way is being reported as an ordinary test failure, which invites someone to go and " \
        "fix tests that may be fine — the run never finished"
    end
  end

  describe "a lane that finished but checked nothing" do
    it "is did-not-complete when it ran zero examples, whatever it exited with" do
      expect(lane_state(exit_code: 0, examples: 0, failures: 0)).to eq("did-not-complete"),
        "a lane pointed at no files reports an empty pass — the exact failure this gate exists to remove"
    end
  end

  describe "a lane that finished with an answer" do
    it "is green only when it ran examples and counted none failing" do
      expect(lane_state(exit_code: 0, examples: 5314, failures: 0)).to eq("green")
    end

    it "is red when it counted failures" do
      expect(lane_state(exit_code: 1, examples: 5314, failures: 4)).to eq("red")
    end

    it "is red when it counted failures and still exited 0" do
      expect(lane_state(exit_code: 0, examples: 5314, failures: 4)).to eq("red"),
        "a lane whose own summary says it failed is reported green because a wrapper swallowed the exit code — " \
        "the contradiction would sit in summary.json with nothing reading it"
    end

    it "falls back to the exit code for a lane that prints no example count" do
      expect(lane_state(exit_code: 0)).to eq("green")
      expect(lane_state(exit_code: 1)).to eq("red")
    end
  end

  describe "a lane whose tool uses its own exit codes" do
    # Brakeman's own lib/brakeman.rb (8.0.6): 3 = warnings found, 7 = errors
    # raised, under the --exit-on-warn/--exit-on-error flags that lane runs.
    it "reports a brakeman finding as red rather than as a crash" do
      expect(lane_state(exit_code: 3, ok_codes: "0 1 3 7")).to eq("red")
      expect(lane_state(exit_code: 7, ok_codes: "0 1 3 7")).to eq("red")
    end

    it "still treats those codes as a crash for a lane that does not claim them" do
      expect(lane_state(exit_code: 3)).to eq("did-not-complete")
    end

    it "does not match a code by substring alone" do
      expect(lane_state(exit_code: 1, ok_codes: "0 13")).to eq("did-not-complete"),
        "exit 1 was accepted because \"1\" appears inside \"13\" — a lane would be judged by a code it never claimed"
    end
  end

  # @lat: [[verification-gates#Docker lanes]]
  describe "reading the lint lane's own gate counts out of its log" do
    it "answers how many gates ran and how many of them failed" do
      log = <<~LOG
        --- sway:lint:admin_guards
        rake-gates: 1 of 7 gates failed
        sway:lint:admin_guards                   exit 1
      LOG
      expect(gate_totals(log)).to eq("7 1")
    end

    it "answers zero gates when the lane died before it printed its summary" do
      expect(gate_totals("--- sway:lint:admin_guards\n")).to eq("0 0"),
        "a lane killed mid-gate would count as green with nothing run, which is the outcome summary.json has to " \
        "tell apart from a gate that ran and failed"
    end

    it "is did-not-complete when no gate ran, and red when one failed" do
      expect(lane_state(exit_code: 0, examples: 0, failures: 0)).to eq("did-not-complete")
      expect(lane_state(exit_code: 1, examples: 7, failures: 1)).to eq("red")
      expect(lane_state(exit_code: 0, examples: 7, failures: 0)).to eq("green")
    end
  end

  describe "reading a lane's totals out of its log" do
    it "takes the last aggregate line, which is the sum across every worker" do
      log = <<~LOG
        4 examples, 1 failure
        900 examples, 2 failures
        5314 examples, 4 failures, 11 pending
      LOG
      expect(lane_totals(log)).to eq("5314 4")
    end

    it "reads a trailing pending count without confusing it for the failure count" do
      expect(lane_totals("120 examples, 0 failures, 7 pending\n")).to eq("120 0")
    end

    it "reads the singular forms rspec prints for one of a thing" do
      expect(lane_totals("1 example, 1 failure\n")).to eq("1 1")
    end

    it "answers zero examples when the log holds no aggregate line at all" do
      expect(lane_totals("every worker crashed before it could finish\n")).to eq("0 0"),
        "a lane whose workers all died would be judged on its exit code alone"
    end

    it "ignores an aggregate-looking line that is not at the start of a line" do
      expect(lane_totals("  indented: 999 examples, 0 failures\n")).to eq("0 0")
    end
  end

  # The two halves above only protect the gate while the gate still asks them.
  it "is what verify.sh asks for each lane's state" do
    verify = Rails.root.join("scripts", "dip", "verify.sh").read
    runnable = verify.lines.grep_v(/\A\s*#/).join

    expect(runnable).to include(". scripts/dip/verify-lib.sh"),
      "verify.sh does not source scripts/dip/verify-lib.sh, so the decision these examples cover is not the one " \
      "the gate runs"

    body = runnable[/classify_lane\(\)\s*\{(.*?)\n\}/m, 1]
    expect(body).not_to be_nil, "no classify_lane() function body found"
    expect(body).to match(/LANE_STATE\[\$idx\]="\$\(lane_state/),
      "classify_lane no longer asks lane_state for the answer — it decided the state some other way, and every " \
      "example in this file went on passing against code the gate does not use"
    expect(body).not_to match(/LANE_STATE\[\$idx\]="(green|red|did-not-complete)"/),
      "classify_lane assigns a lane state literally as well as through lane_state, so two rules decide the same " \
      "thing and can drift apart"
  end
end
