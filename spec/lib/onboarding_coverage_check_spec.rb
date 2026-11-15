# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "fileutils"
require_relative "../../lib/onboarding_coverage_check"

# @lat: [[verification-gates#Onboarding coverage gate]]
RSpec.describe OnboardingCoverageCheck do
  let(:coverage_root) { Dir.mktmpdir("onboarding-coverage") }
  let(:sample_path) { "app/services/sample_service.rb" }
  let(:fresh_timestamp) { 2_000_000_000 }

  before do
    FileUtils.mkdir_p(File.join(coverage_root, "app/services"))
    File.write(File.join(coverage_root, sample_path), <<~RUBY)
      def sample(flag)
        if flag
          :yes
        else
          :no
        end
      end
    RUBY
  end

  after { FileUtils.remove_entry(coverage_root) }

  def worker_entry(lines:, then_hits:, else_hits:, timestamp: fresh_timestamp)
    {
      "timestamp" => timestamp,
      "coverage" => {
        File.join(coverage_root, sample_path) => {
          "lines" => lines,
          "branches" => {
            "[:if, 0, 2, 2, 6, 5]" => {
              "[:then, 1, 3, 4, 3, 8]" => then_hits,
              "[:else, 2, 5, 4, 5, 7]" => else_hits
            }
          }
        }
      }
    }
  end

  def run_check(resultset, floors, since: nil)
    resultset_path = File.join(coverage_root, "resultset.json")
    File.write(resultset_path, JSON.generate(resultset))
    described_class.new(resultset_path: resultset_path, floors: floors, root: coverage_root, since: since)
  end

  it "passes when every listed file meets its line and branch floors" do
    resultset = {
      "rspec-browser-worker-1" => worker_entry(lines: [1, 1, 1, nil, 0, nil, nil], then_hits: 1, else_hits: 0),
      "rspec-nonbrowser-worker-1" => worker_entry(lines: [1, 1, 0, nil, 1, nil, nil], then_hits: 0, else_hits: 1)
    }

    result = run_check(resultset, {sample_path => {"line" => 100.0, "branch" => 100.0}})

    expect(result.failures).to be_empty
    expect(result.report).to eq(["#{sample_path}: line 100.0% (floor 100.0%), branch 100.0% (floor 100.0%)"])
  end

  it "fails, naming the file, when its line coverage drops below the floor" do
    resultset = {"rspec-all-worker-1" => worker_entry(lines: [1, 1, 1, nil, 0, nil, nil], then_hits: 1, else_hits: 0)}

    result = run_check(resultset, {sample_path => {"line" => 80.0, "branch" => 50.0}})

    expect(result.failures).to eq(["#{sample_path}: line coverage 75.0% is below its floor of 80.0%"])
  end

  it "fails, naming the file, when its branch coverage drops below the floor" do
    resultset = {"rspec-all-worker-1" => worker_entry(lines: [1, 1, 1, nil, 0, nil, nil], then_hits: 1, else_hits: 0)}

    result = run_check(resultset, {sample_path => {"line" => 75.0, "branch" => 60.0}})

    expect(result.failures).to eq(["#{sample_path}: branch coverage 50.0% is below its floor of 60.0%"])
  end

  it "fails when a listed file is absent from the coverage report" do
    resultset = {"rspec-all-worker-1" => worker_entry(lines: [1, 1, 1, nil, 1, nil, nil], then_hits: 1, else_hits: 1)}

    result = run_check(resultset, {"app/services/missing_service.rb" => {"line" => 0.0, "branch" => 0.0}})

    expect(result.failures).to eq(["app/services/missing_service.rb: missing from the coverage report"])
  end

  it "leaves out worker results written before the since time" do
    resultset = {
      "rspec-all-worker-1" => worker_entry(lines: [1, 1, 1, nil, 0, nil, nil], then_hits: 1, else_hits: 0),
      "rspec-all-worker-2" => worker_entry(lines: [1, 1, 0, nil, 1, nil, nil], then_hits: 0, else_hits: 1, timestamp: fresh_timestamp - 60)
    }

    result = run_check(resultset, {sample_path => {"line" => 100.0, "branch" => 100.0}}, since: fresh_timestamp - 1)

    expect(result.failures).to eq([
      "#{sample_path}: line coverage 75.0% is below its floor of 100.0%",
      "#{sample_path}: branch coverage 50.0% is below its floor of 100.0%"
    ])
  end
end
