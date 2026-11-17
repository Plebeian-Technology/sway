# frozen_string_literal: true

namespace :sway do
  namespace :coverage do
    # @lat: [[verification-gates#Onboarding coverage gate]]
    desc "sway:coverage:onboarding[since]: fail when an onboarding file is under its line or branch coverage floor"
    task :onboarding, [:since] do |_t, args|
      require "yaml"
      require "simplecov"
      require_relative "../onboarding_coverage_check"

      root = File.expand_path("../..", __dir__)
      resultset_path = File.join(root, "coverage", ".resultset.json")
      abort "sway:coverage:onboarding: #{resultset_path} not found; run the rspec suite first" unless File.exist?(resultset_path)

      check = OnboardingCoverageCheck.new(
        resultset_path: resultset_path,
        floors: YAML.load_file(File.join(root, OnboardingCoverageCheck::FLOOR_PATH)),
        root: root,
        since: args[:since].presence&.to_i
      )
      puts check.report

      failures = check.failures
      if failures.any?
        warn "Onboarding coverage is under its floor in #{OnboardingCoverageCheck::FLOOR_PATH}:"
        failures.each { |failure| warn "  - #{failure}" }
        abort "sway:coverage:onboarding failed"
      end

      puts "sway:coverage:onboarding: every onboarding file meets its floor"
    end
  end
end
