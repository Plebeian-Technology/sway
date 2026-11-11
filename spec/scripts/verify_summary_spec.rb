# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "json"

# summary.json is what every later reader of a verify run is told: which lanes
# ran, which state each reached, and which examples failed. It used to be built
# by a `node -e` string inside scripts/dip/verify.sh, where no linter could see
# it and nothing could run it against a known input.
RSpec.describe "the summary a verify run writes" do
  # Runs scripts/dip/verify-summary.mjs over one facts file and returns the
  # parsed JSON. +logs+ maps a lane's log path to the text to put there, so an
  # example can plant rspec's own failure lines.
  def build_summary(facts_rows, logs = {})
    Dir.mktmpdir("verify-summary") do |dir|
      logs.each do |name, body|
        path = File.join(dir, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, body)
      end

      # @lat: [[verify-summary-log-path-anchoring#Why the log column has to be an absolute path]]
      facts = File.join(dir, "facts.tsv")
      rows = facts_rows.map do |row|
        anchored = row.dup
        anchored[5] = File.join(dir, anchored.fetch(5).to_s)
        anchored
      end
      File.write(facts, rows.map { |row| row.join("\t") }.join("\n") + "\n")
      out = File.join(dir, "summary.json")

      _stdout, stderr, status = Open3.capture3(
        {
          "RUN_ID" => "99-1", "STARTED_AT" => "2026-08-16T00:00:00Z",
          "TOTAL_DURATION" => "334", "EXIT_CODE" => "2",
          "FACTS_FILE" => facts, "SUMMARY_PATH" => out
        },
        "node", "scripts/dip/verify-summary.mjs",
        chdir: Rails.root.to_s
      )
      raise "verify-summary.mjs failed: #{stderr}" unless status.success?

      JSON.parse(File.read(out))
    end
  end

  # A lane row in the column order verify.sh writes.
  def facts_row(name:, state: "green", duration: "10", exit_code: "0", oom: "false",
    log: "logs/#{name}.log", rerun: "RERUN", examples: "", failures: "",
    checks_ran: "", checks_failed: "")
    [name, state, duration, exit_code, oom, log, rerun, examples, failures, checks_ran, checks_failed]
  end

  it "records each lane's state, duration and exit code" do
    summary = build_summary([facts_row(name: "rubocop", duration: "12", rerun: "bin/rubocop")])
    lane = summary.fetch("lanes").first

    expect(summary).to include("run_id" => "99-1", "exit_code" => 2)
    expect(lane).to include("name" => "rubocop", "state" => "green", "duration_seconds" => 12, "exit_code" => 0)
    expect(lane.fetch("rerun")).to eq("bin/rubocop"),
      "the rerun command is dropped from summary.json, so a red lane offers no way back in"
  end

  it "leaves a non-rspec lane's counts null rather than zero" do
    lane = build_summary([facts_row(name: "tsc")]).fetch("lanes").first

    expect(lane.fetch("examples")).to be_nil,
      "a lane that counts no examples reports 0, which reads as 'counted, and there were none' — the state a " \
      "zero-example rspec lane is refused for"
    expect(lane.fetch("failures")).to be_nil
  end

  # @lat: [[verification-gates#Docker lanes]]
  it "says how many checks a lane ran and how many failed, which tells a failed gate from an unrun one" do
    failed = build_summary([facts_row(name: "rake-gates", state: "red", exit_code: "1",
      checks_ran: "7", checks_failed: "1")]).fetch("lanes").first
    never_ran = build_summary([facts_row(name: "rake-gates", state: "did-not-complete", exit_code: "137",
      checks_ran: "0", checks_failed: "0")]).fetch("lanes").first

    expect(failed).to include("checks_ran" => 7, "checks_failed" => 1),
      "summary.json says nothing about how many gates the lane ran, so a reader cannot tell one failing gate " \
      "from six that never started"
    expect(never_ran).to include("checks_ran" => 0, "checks_failed" => 0)
  end

  it "leaves the check counts null for a lane that reports none of its own" do
    lane = build_summary([facts_row(name: "tsc")]).fetch("lanes").first

    expect(lane.fetch("checks_ran")).to be_nil
    expect(lane.fetch("checks_failed")).to be_nil
  end

  it "carries the out-of-memory flag through, which is how a killed lane is told apart" do
    lane = build_summary([facts_row(name: "steep", state: "did-not-complete", exit_code: "137", oom: "true")])
      .fetch("lanes").first

    expect(lane.fetch("oom_killed")).to be(true)
    expect(lane.fetch("state")).to eq("did-not-complete")
  end

  it "collects an rspec lane's failing examples verbatim, as rspec printed them" do
    log = <<~LOG
      Failures:
        1) something broke
      Failed examples:

      rspec ./spec/system/a_spec.rb:12 # something broke
      rspec ./spec/models/b_spec.rb:34 # another thing
    LOG
    lane = build_summary(
      [facts_row(name: "rspec-browser", state: "red", exit_code: "1", examples: "152", failures: "2")],
      {"logs/rspec-browser.log" => log}
    ).fetch("lanes").first

    expect(lane.fetch("failing_examples")).to eq([
      "rspec ./spec/system/a_spec.rb:12 # something broke",
      "rspec ./spec/models/b_spec.rb:34 # another thing"
    ]),
      "the failing examples are reformatted or lost — each line is already a copy-pasteable rerun and is worth " \
      "more unaltered than tidied"
  end

  it "still writes a lane whose log cannot be read at all" do
    lane = build_summary(
      [facts_row(name: "rspec-nonbrowser", state: "did-not-complete", exit_code: "137", log: "logs/gone.log")]
    ).fetch("lanes").first

    expect(lane.fetch("failing_examples")).to eq([])
    expect(lane.fetch("state")).to eq("did-not-complete"),
      "a lane killed before it wrote a log takes the whole summary down with it, so the run reports nothing " \
      "about the fourteen lanes that did finish"
  end

  it "reads only rspec's own summary lines, not any line mentioning rspec" do
    log = "see rspec ./spec/foo_spec.rb:1 for the pattern\nrspec ./spec/real_spec.rb:9 # the real one\n"
    lane = build_summary(
      [facts_row(name: "rspec-browser", state: "red", exit_code: "1")],
      {"logs/rspec-browser.log" => log}
    ).fetch("lanes").first

    expect(lane.fetch("failing_examples")).to eq(["rspec ./spec/real_spec.rb:9 # the real one"])
  end
end
