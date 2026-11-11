# frozen_string_literal: true

require "json"

# @lat: [[open-source-licenses-service-design#Why the source is a pre-built snapshot, not a live scan]]
class OpenSourceLicensesService
  FRONTEND_JSON_PATH = Rails.root.join("config", "oss-frontend-licenses.json")
  MIT = "MIT"

  def self.call
    new.call
  end

  def call
    javascript_dependencies
  end

  def javascript_dependencies
    return [] unless FRONTEND_JSON_PATH.exist?

    # @lat: [[open-source-licenses-service-design#Two filters narrow the list to "licenses worth a look"]]
    parsed = JSON.parse(FRONTEND_JSON_PATH.read)
    return [] unless parsed.is_a?(Hash)

    parsed.flat_map do |license_group, packages|
      next [] unless packages.is_a?(Array)

      packages.filter_map do |pkg|
        next unless pkg.is_a?(Hash)

        license = pkg["license"].presence || license_group.to_s
        next if license == MIT

        versions = pkg["versions"]
        {
          name: pkg["name"].to_s,
          version: versions.is_a?(Array) ? versions.join(", ") : versions.to_s,
          license: license,
          homepage: pkg["homepage"].presence
        }
      end
    end.sort_by { |dep| dep[:name].to_s.downcase }
  rescue
    []
  end
end
