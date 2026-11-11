# frozen_string_literal: true

# @lat: [[oss-license-snapshot#Why the snapshot is read from node_modules]]
namespace :sway do
  namespace :licenses do
    desc "Snapshot frontend dependency licenses to config/oss-frontend-licenses.json"
    task :frontend do
      require "json"
      require_relative "../sway/frontend_licenses"

      root = File.expand_path("../..", __dir__)
      output_path = File.join(root, "config", "oss-frontend-licenses.json")

      begin
        snapshot = Sway::FrontendLicenses.new(root).snapshot
      rescue Sway::FrontendLicenses::Error => e
        File.write(output_path, "#{JSON.pretty_generate(Sway::FrontendLicenses::UNAVAILABLE)}\n")
        warn "[sway:licenses:frontend] FAILED: #{e.message}"
        warn "[sway:licenses:frontend] /licenses will carry one row saying the snapshot is unavailable"
        raise
      end

      File.write(output_path, "#{JSON.pretty_generate(snapshot)}\n")
      total = snapshot.values.sum(&:size)
      puts "[sway:licenses:frontend] wrote #{total} direct packages across #{snapshot.size} licenses → #{output_path}"
    end
  end
end
