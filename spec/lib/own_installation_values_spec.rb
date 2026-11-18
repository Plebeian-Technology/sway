# frozen_string_literal: true

require "rails_helper"

# Holds what this check needs to know, so the examples below stay readable.
module OwnInstallationValues
  # @lat: [[deploy-values-boot-check#Keeping one installation's values out of the tracked repository#Why some keys are left out of the search]]
  KEYS = %w[
    SWAY_HOST
    SWAY_TAILSCALE_IP
    SWAY_STORAGE_DIR
    SWAY_REGISTRY
    SWAY_GCP_PROJECT_ID
    SWAY_GCS_BUCKET_DB
    SWAY_GCS_BUCKET_ASSETS
    SWAY_KEYFILE_PATH
    SWAY_STANDBY_HOST
    SWAY_STANDBY_DIR
    SWAY_STANDBY_MOUNT
    SWAY_ANDROID_CERT_SHA256_FINGERPRINTS
  ].freeze

  # A disk path leaks far more often as a sibling folder under it than as
  # itself, so its parents are searched for too, down to this many segments.
  SHALLOWEST_DIRECTORY = 2

  class << self
    def config_file
      Rails.root.join(SwayDeployConfig::REAL_FILE)
    end

    # What the tracked example file shows. Published on purpose, so a tracked
    # file repeating any of it is not a leak.
    def published
      Rails.root.join(SwayDeployConfig::EXAMPLE_FILE).read
    end

    # The value itself, each entry of a comma-separated list, the host
    # without its port, and each parent folder.
    def searches_for(value)
      entries = value.split(",").map(&:strip)
      return entries.flat_map { |entry| searches_for(entry) }.uniq if entries.length > 1

      found = [value]
      found << value.split(":").first.to_s if value.match?(/\A[^:\/]+:\d+\z/)

      if value.start_with?("/")
        segments = value.split("/").reject(&:empty?)
        SHALLOWEST_DIRECTORY.upto(segments.length - 1) do |depth|
          found << "/#{segments.take(depth).join("/")}"
        end
      end

      found.reject(&:empty?).uniq
    end

    # @lat: [[deploy-values-boot-check#Keeping one installation's values out of the tracked repository#Why a bare machine name is matched as a whole word]]
    def found_in?(contents, candidate)
      return contents.include?(candidate) unless candidate.match?(/\A[A-Za-z0-9][A-Za-z0-9-]*\z/)

      contents.match?(/(?<![A-Za-z0-9_.-])#{Regexp.escape(candidate)}(?![A-Za-z0-9_-])/)
    end

    # Every tracked path. Raises rather than answering nothing, because an
    # empty list would let this whole check pass while looking at nothing —
    # which is what happens when git cannot read the repository (a worktree
    # inside Docker is the way that turns up here).
    def tracked_paths
      paths = Dir.chdir(Rails.root) { `git ls-files -z`.split("\0") }
      raise "git ls-files listed no tracked files, so nothing was checked" if paths.empty?

      paths
    end
  end
end

# @lat: [[deploy-values-boot-check#Keeping one installation's values out of the tracked repository]]
# WITH NO deploy/config/sway.env THESE EXAMPLES ARE PENDING, NOT GREEN.
RSpec.describe "values belonging to one installation" do
  around do |example|
    original = ENV.to_h
    begin
      ENV[SwayDeployConfig::FILE_VARIABLE] = OwnInstallationValues.config_file.to_s
      SwayDeployConfig.reload!
      example.run
    ensure
      ENV.replace(original)
      SwayDeployConfig.reload!
    end
  end

  it "protects SWAY_TAILSCALE_IP from leaking into git" do
    expect(OwnInstallationValues::KEYS).to include("SWAY_TAILSCALE_IP")
  end

  it "matches a bare machine name only as a whole name" do
    expect(OwnInstallationValues.found_in?("ssh kamal@sway-pi uptime", "sway-pi")).to be(true)
    expect(OwnInstallationValues.found_in?("SWAY_HOST=sway-pi\n", "sway-pi")).to be(true)
    expect(OwnInstallationValues.found_in?("rapid2.example.test", "id2")).to be(false)
    expect(OwnInstallationValues.found_in?("sway-pi-2", "sway-pi")).to be(false)
    expect(OwnInstallationValues.found_in?("http://10.0.0.10:8090", "10.0.0.10")).to be(true)
  end

  it "protects the Android signing fingerprints from leaking into git, one at a time" do
    expect(OwnInstallationValues::KEYS).to include("SWAY_ANDROID_CERT_SHA256_FINGERPRINTS")
    expect(OwnInstallationValues.searches_for("AA:BB, CC:DD")).to eq(["AA:BB", "CC:DD"])
  end

  it "is a check with something to check against" do
    skip "no #{SwayDeployConfig::REAL_FILE} on this machine — nothing to protect" unless
      OwnInstallationValues.config_file.exist?

    named = OwnInstallationValues::KEYS.count { |key| SwayDeployConfig[key].present? }

    expect(named).to be_positive
  end

  it "keeps every one of them out of the tracked repository" do
    skip "no #{SwayDeployConfig::REAL_FILE} on this machine — nothing to protect" unless
      OwnInstallationValues.config_file.exist?

    published = OwnInstallationValues.published
    # candidate string => the keys it came from. Names, never values: this
    # message is read in a terminal and pasted into issues.
    wanted = {}
    OwnInstallationValues::KEYS.each do |key|
      value = SwayDeployConfig[key]
      # nil? spelled out rather than folded into blank?, which narrows nothing.
      next if value.nil? || value.blank?

      OwnInstallationValues.searches_for(value).each do |candidate|
        next if published.include?(candidate)

        (wanted[candidate] ||= []) << key
      end
    end

    leaks = []
    OwnInstallationValues.tracked_paths.each do |path|
      next if path == SwayDeployConfig::EXAMPLE_FILE

      contents = Rails.root.join(path).read
      wanted.each { |candidate, keys| leaks << "#{path} — #{keys.join(", ")}" if OwnInstallationValues.found_in?(contents, candidate) }
    rescue ArgumentError, Errno::EISDIR, Errno::ENOENT
      next # not text, or gone since git listed it
    end

    expect(leaks.uniq).to be_empty, lambda {
      <<~MESSAGE
        These tracked files hold a value that belongs to this installation:

        #{leaks.uniq.map { |line| "  #{line}" }.join("\n")}

        The value is not printed here on purpose. Look the key up in
        #{SwayDeployConfig::REAL_FILE} to see what to search for.

        Replace it with the matching example value from
        #{SwayDeployConfig::EXAMPLE_FILE}, which is published on purpose.
      MESSAGE
    }
  end
end
