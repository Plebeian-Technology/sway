# frozen_string_literal: true

require "json"

module Sway
  # @lat: [[oss-license-snapshot#Why the snapshot is read from node_modules]]
  class FrontendLicenses
    class Error < StandardError; end

    UNKNOWN_LICENSE = "UNKNOWN"

    # @lat: [[oss-license-snapshot#Why a failure is now audible twice]]
    UNAVAILABLE = {
      "unavailable" => [
        {
          "name" => "Frontend licence snapshot unavailable — sway:licenses:frontend failed during the image build",
          "versions" => [],
          "license" => "unavailable",
          "homepage" => nil
        }
      ]
    }.freeze

    def initialize(root)
      @root = root.to_s
    end

    def snapshot
      names = direct_dependencies
      raise Error, "package.json lists no dependencies, so there is nothing to attribute" if names.empty?

      grouped = {}
      missing = []

      names.sort.each do |name|
        manifest = installed_manifest(name)
        if manifest.nil?
          missing << name
          next
        end

        license = license_of(manifest)
        (grouped[license] ||= []) << {
          "name" => name,
          "versions" => [manifest["version"].to_s],
          "license" => license,
          "homepage" => manifest["homepage"]
        }
      end

      unless missing.empty?
        raise Error, "these dependencies are not installed under node_modules: #{missing.join(", ")}"
      end

      grouped
    end

    private

    def direct_dependencies
      path = File.join(@root, "package.json")
      raise Error, "no package.json at #{path}" unless File.file?(path)

      JSON.parse(File.read(path)).fetch("dependencies", {}).keys
    rescue JSON::ParserError => e
      raise Error, "package.json does not parse: #{e.message}"
    end

    def installed_manifest(name)
      path = File.join(@root, "node_modules", name, "package.json")
      return nil unless File.file?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end

    # @lat: [[oss-license-snapshot#Why the snapshot is read from node_modules]]
    def license_of(manifest)
      value = manifest["license"] || manifest["licenses"]

      case value
      when String
        value.empty? ? UNKNOWN_LICENSE : value
      when Hash
        type = value["type"].to_s
        type.empty? ? UNKNOWN_LICENSE : type
      when Array
        types = value.filter_map { |entry| entry.is_a?(Hash) ? entry["type"] : entry }
        types.empty? ? UNKNOWN_LICENSE : types.join(" OR ")
      else
        UNKNOWN_LICENSE
      end
    end
  end
end
