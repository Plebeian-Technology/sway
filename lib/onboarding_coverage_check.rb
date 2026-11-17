# frozen_string_literal: true

require "json"

# @lat: [[verification-gates#Onboarding coverage gate#Loading the check without SimpleCov]]
class OnboardingCoverageCheck
  FLOOR_PATH = "config/onboarding_coverage_floor.yml"

  # since: epoch seconds; nil merges every worker result in the resultset.
  def initialize(resultset_path:, floors:, root:, since: nil)
    @resultset_path = resultset_path
    @floors = floors
    @root = root
    @since = since
  end

  def report
    @floors.filter_map do |path, floor|
      source_file = source_file_for(path)
      next unless source_file

      "#{path}: line #{format_percent(line_percent(source_file))}% (floor #{format_percent(floor.fetch("line"))}%), " \
        "branch #{format_percent(branch_percent(source_file))}% (floor #{format_percent(floor.fetch("branch"))}%)"
    end
  end

  def failures
    @floors.flat_map do |path, floor|
      source_file = source_file_for(path)
      next ["#{path}: missing from the coverage report"] unless source_file

      [
        below_floor(path, "line", line_percent(source_file), floor.fetch("line")),
        below_floor(path, "branch", branch_percent(source_file), floor.fetch("branch"))
      ].compact
    end
  end

  private

  def below_floor(path, criterion, percent, floor)
    return if percent >= floor

    "#{path}: #{criterion} coverage #{format_percent(percent)}% is below its floor of #{format_percent(floor)}%"
  end

  def line_percent(source_file)
    source_file.covered_percent(:line) || 0.0
  end

  def branch_percent(source_file)
    source_file.covered_percent(:branch) || 0.0
  end

  def format_percent(percent)
    format("%.1f", (percent * 10).floor / 10.0)
  end

  def source_file_for(path)
    absolute_path = File.join(@root, path)
    data = merged_coverage[absolute_path]
    data && SimpleCov::SourceFile.new(absolute_path, data)
  end

  def merged_coverage
    @merged_coverage ||= begin
      _command_names, coverage = SimpleCov::ResultMerger.merge_valid_results(fresh_results, ignore_timeout: true)
      coverage || {}
    end
  end

  def fresh_results
    results = JSON.parse(File.read(@resultset_path))
    return results unless @since

    results.select { |_command_name, entry| entry.fetch("timestamp") >= @since }
  end
end
