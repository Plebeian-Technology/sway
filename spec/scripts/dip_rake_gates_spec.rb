# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"

# @lat: [[verification-gates#Docker lanes]]
RSpec.describe "the rake-gates lane" do
  let(:rake_gates_script) { Rails.root.join("scripts", "dip", "rake-gates.sh") }
  let(:verify_runnable_lines) do
    Rails.root.join("scripts", "dip", "verify.sh").read.lines.grep_v(/\A\s*#/).join
  end

  # @lat: [[verification-gates#Known traps]]
  def run_gates(*tasks)
    Dir.mktmpdir("rake-gates", Rails.root.join("tmp").to_s) do |dir|
      stub = File.join(dir, "bundle")
      File.write(stub, <<~SH)
        #!/bin/sh
        task="$3"
        case "$task" in
          *fails*) echo "boom in $task" >&2; exit 1 ;;
        esac
        echo "ran $task"
      SH
      File.chmod(0o755, stub)
      Open3.capture3({"PATH" => "#{dir}:#{ENV.fetch("PATH", "")}"}, "bash", rake_gates_script.to_s, *tasks)
    end
  end

  it "is executable, because the lane names it as the container's command" do
    expect(File.executable?(rake_gates_script)).to be(true),
      "scripts/dip/rake-gates.sh is not executable, so the rake-gates lane cannot start at all"
  end

  it "runs the gates beside a failing one instead of stopping at it" do
    stdout, _stderr, status = run_gates("first", "second-fails", "third")

    expect(status).not_to be_success
    expect(stdout).to include("ran first")
    expect(stdout).to include("ran third"),
      "a gate after a failing one never ran, so the lane checked less than it was asked to — the exact property " \
      "this gate exists to guarantee"
  end

  it "reports each gate's own exit code, so a failed gate is not confused with a never-run one" do
    stdout, _stderr, _status = run_gates("first", "second-fails", "third")

    expect(stdout).to match(/^first\s+exit 0$/)
    expect(stdout).to match(/^second-fails\s+exit 1$/)
    expect(stdout).to match(/^third\s+exit 0$/)
    expect(stdout).to include("1 of 3 gates failed")
  end

  it "is green only when every gate is" do
    _stdout, _stderr, status = run_gates("first", "second")

    expect(status).to be_success
  end

  it "refuses an empty task list rather than reporting green having checked nothing" do
    _stdout, stderr, status = run_gates

    expect(status.exitstatus).to eq(64)
    expect(stderr).to include("name at least one rake task")
  end

  it "is what the rake-gates lane runs, rather than one rake process holding every task" do
    lane = verify_runnable_lines[/rake-gates\)(.*?);;/m, 1]
    expect(lane).not_to be_nil, "no rake-gates arm found in run_lane"

    expect(lane).to include("scripts/dip/rake-gates.sh")
    expect(lane).not_to match(/bundle exec rake\s+sway:lint/),
      "the lane runs several lint tasks in one rake process again, so the first task to call abort ends the " \
      "process and the gates beside it never run"
  end

  def sway_lint_tasks
    Rails.root.join("lib", "tasks", "sway_lint.rake").read
      .scan(/^\s*task\s+:?([a-zA-Z0-9_]+)/).flatten
      .map { |name| "sway:lint:#{name}" }
  end

  it "is handed the gates defined under sway:lint in lib/tasks/sway_lint.rake" do
    declared = verify_runnable_lines[/RAKE_GATES=\(\s*(.*?)\s*\)\n/m, 1].to_s.split(/\s+/).reject(&:empty?)

    expect(declared).to eq(sway_lint_tasks)
  end

  it "matches the gates documented in lat.md/reference/verification-gates.md" do
    doc = Rails.root.join("lat.md", "reference", "verification-gates.md").read
    rake_gates_line = doc.lines.find { |line| line.start_with?("- `rake-gates`") }
    expect(rake_gates_line).not_to be_nil
    verified_line = rake_gates_line #: String

    documented_gates = verified_line.scan(/`([a-z_]+)`/).flatten.select do |name|
      sway_lint_tasks.include?("sway:lint:#{name}")
    end
    expect(documented_gates).to eq(sway_lint_tasks.map { |t| t.delete_prefix("sway:lint:") })
  end

  it "does not spell out a gate count in CLAUDE.md" do
    claude_lines = Rails.root.join("CLAUDE.md").read
    gate_line = claude_lines.lines.find { |l| l.include?("`sway:lint:*` rake gates") }
    expect(gate_line).not_to be_nil
    expect(gate_line).not_to match(/\b(six|\d+)\s+`sway:lint:\*`/)
  end

  it "does not spell out a gate count in lat.md/reference/verification-gates.md" do
    doc = Rails.root.join("lat.md", "reference", "verification-gates.md").read
    rake_gates_line = doc.lines.find { |l| l.start_with?("- `rake-gates`") }
    expect(rake_gates_line).not_to be_nil
    expect(rake_gates_line).not_to match(/\b(six|\d+)\s+`sway:lint:\*`/)
  end

  it "names the same script in the rerun printed beside a red rake-gates lane" do
    entries = verify_runnable_lines[/LANE_RERUN=\((.*?)\n\)/m, 1]
    rerun = entries.to_s.lines.find { |line| line.include?("rake-gates.sh") }

    expect(rerun).not_to be_nil,
      "the rake-gates rerun does not run the lane's own script, so the command handed to whoever is investigating " \
      "a red lane runs a different arrangement of the same tasks"
    expect(rerun).to include("${RAKE_GATES[*]}"),
      "the rerun spells the task list out a second time, where it can drift from the list the lane really runs"
  end
end
