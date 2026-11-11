# frozen_string_literal: true

require "rails_helper"
require "yaml"

# @lat: [[ci-runner-variable-indirection#Why the fallback matters as much as the indirection]]
RSpec.describe ".github/workflows" do
  # file name => the runs-on value of each job in it.
  let(:ci_workflow_runners) do
    Rails.root.glob(".github/workflows/*.yml").to_h do |path|
      jobs = YAML.safe_load_file(path, aliases: true).fetch("jobs", {})
      [path.basename.to_s, jobs.values.filter_map { |job| job["runs-on"] if job.is_a?(Hash) }]
    end
  end

  it "finds a runner for every job, so a file this check cannot read is not a pass" do
    silent = ci_workflow_runners.select { |_, runners| runners.empty? }

    expect(ci_workflow_runners).not_to be_empty
    expect(silent).to be_empty, "no job runner found in: #{silent.keys.join(", ")}"
  end

  it "never writes a particular machine into a workflow" do
    named = ci_workflow_runners.select do |_, runners|
      runners.any? { |runner| runner.to_s.include?("self-hosted") }
    end

    expect(named).to be_empty,
      "#{named.keys.join(", ")} names a runner outright. Read it from a variable instead, " \
      "so a copy of this repository that has no such machine still runs its checks."
  end

  # @lat: [[ci-runner-variable-indirection#Why the fallback matters as much as the indirection]]
  it "falls back to a hosted runner when nothing is configured" do
    unguarded = ci_workflow_runners.reject do |_, runners|
      runners.all? { |runner| !runner.to_s.include?("vars.") || runner.to_s.include?("ubuntu-") }
    end

    expect(unguarded).to be_empty,
      "#{unguarded.keys.join(", ")} reads a runner variable with no hosted fallback. Unset, " \
      "the job would queue forever with no machine willing to take it."
  end

  it "forces a hosted runner on pull_request events before reading vars.CI_RUNNER" do
    pr_unguarded = Rails.root.glob(".github/workflows/*.yml").filter_map do |path|
      workflow = YAML.safe_load_file(path, aliases: true)
      triggers = workflow["on"] || workflow[true]
      runs_on_pr =
        case triggers
        when Hash then triggers.key?("pull_request")
        when Array then triggers.include?("pull_request")
        else triggers.to_s == "pull_request"
        end
      next unless runs_on_pr

      jobs = workflow.fetch("jobs", {})
      runners = jobs.values.filter_map { |job| job["runs-on"] if job.is_a?(Hash) }
      unsafe = runners.reject do |runner|
        !runner.to_s.include?("vars.CI_RUNNER") ||
          runner.to_s.match?(/github\.event_name\s*==\s*['"]pull_request['"]\s*&&\s*['"]ubuntu-latest['"].*vars\.CI_RUNNER/)
      end
      path.basename.to_s if unsafe.any?
    end

    expect(pr_unguarded).to be_empty,
      "#{pr_unguarded.join(", ")} triggers on pull_request without forcing ubuntu-latest before vars.CI_RUNNER"
  end
end
