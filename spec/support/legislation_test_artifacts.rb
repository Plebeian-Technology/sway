# frozen_string_literal: true

# @lat: [[legislation-test-isolation-paths#Why LegislationTestArtifacts mirrors the same shape for throwaway fixture files]]
module LegislationTestArtifacts
  # @param name [String] a name unique to the calling spec file, matching
  #   the directory name each spec used before isolation existed.
  # @return [String]
  def self.root_for(name)
    isolation_dir = ENV["SWAY_TEST_DATABASE_DIR"].to_s
    return Rails.root.join("tmp", "test_artifacts", name).to_s if isolation_dir.empty?

    File.join(isolation_dir, "test_artifacts#{ENV["TEST_ENV_NUMBER"]}", name)
  end
end
