# frozen_string_literal: true

module Sway
  # @lat: [[legislation-test-isolation-paths#Why LegislationTestArtifacts mirrors the same shape for throwaway fixture files]]
  # @lat: [[env-read-check-design#Why SWAY_TEST_DATABASE_DIR and TEST_ENV_NUMBER live in lib/, not app/]]
  module LegislationTestIsolation
    def self.root_override
      run_dir = ENV["SWAY_TEST_DATABASE_DIR"].to_s
      return nil if run_dir.empty?

      Pathname.new(run_dir).join("legislation#{ENV["TEST_ENV_NUMBER"]}")
    end
  end
end
