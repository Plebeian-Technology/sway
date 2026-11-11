# frozen_string_literal: true

# @lat: [[lat.md/explanation/testimony-fixtures#Why the testimony fixtures are local-only]]
module TestimonyFixtures
  CAMPAIGN_BUNDLE = Rails.root.join("spec", "fixtures", "testimony", "campaign_bundle.txt").to_s.freeze
  NO_CAMPAIGN_BUNDLE = Rails.root.join("spec", "fixtures", "testimony", "no_campaign_bundle.txt").to_s.freeze

  def self.campaign_bundle
    read(CAMPAIGN_BUNDLE)
  end

  def self.no_campaign_bundle
    read(NO_CAMPAIGN_BUNDLE)
  end

  WRAPPED_ADDRESS = /<([^<>@\s]+)\n(@[^<>\s]+)>/

  def self.wrapped_sender_address
    match = WRAPPED_ADDRESS.match(campaign_bundle) || raise("campaign bundle has no address wrapped at the at-sign")
    "#{match[1]}#{match[2]}"
  end

  # Skips the running example when the file is absent; raises outside an example.
  def self.read(path)
    return File.read(path) if File.exist?(path)

    RSpec.current_example&.example_group_instance&.skip(missing_message(path))
    raise Errno::ENOENT, path
  end

  def self.missing_message(path)
    "#{Pathname(path).relative_path_from(Rails.root)} not present " \
      "(real testimony letters, kept local-only and untracked)"
  end
end
