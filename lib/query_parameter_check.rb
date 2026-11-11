# frozen_string_literal: true

require "yaml"

# @lat: [[query-parameter-namespaces#Machine-readable registry and lint enforcement]]
class QueryParameterCheck
  REGISTRY_PATH = "config/query_parameters.yml"

  class Offence
    attr_reader :message

    def initialize(message)
      @message = message
    end

    def to_s
      @message
    end
  end

  class MissingRegistryFileError < StandardError; end
  class EmptyRegistryError < StandardError; end
  class InvalidRegistryError < StandardError; end

  attr_reader :root, :registry_path

  def initialize(root = nil, registry_path: REGISTRY_PATH)
    base = __dir__
    default_root = base ? File.expand_path("..", base) : "."
    @root = root || default_root
    @registry_path = registry_path
    @scanned_count = nil
    @features = nil
    @canonical_parameters = nil
    @global_ambient = nil
    @registry_projection = nil
  end

  def offences
    load_registry!
    offences = []

    detect_parameter_collisions(offences)
    detect_duplicate_parameters_within_features(offences)
    detect_ambient_collisions(offences)
    detect_duplicate_ambient_parameters(offences)

    offences
  end

  def features
    load_registry!
    @features || {}
  end

  def canonical_parameters
    load_registry!
    @canonical_parameters || {}
  end

  def registry_projection
    load_registry!
    @registry_projection || {
      global_ambient: global_ambient,
      features: features.transform_values do |feature|
        {
          parameters: feature[:parameters],
          route_patterns: feature[:route_patterns],
          parameter_families: feature[:parameter_families]
        }
      end
    }
  end

  def feature_for_path(path)
    return nil unless path.is_a?(String)

    matches = features.filter_map do |feature_name, feature|
      next unless feature[:route_patterns].any? { |pattern| Regexp.new(pattern).match?(path) }

      feature_name
    end
    matches.one? ? matches.first : nil
  end

  def parameter_family(feature_name, parameter_name)
    feature = features[feature_name]
    return [] unless feature

    base_name = parameter_name.delete_suffix("[]")
    canonical, aliases = feature[:parameter_families].find do |name, legacy_aliases|
      name == base_name || legacy_aliases.include?(base_name)
    end
    canonical ? [canonical, *aliases] : []
  end

  def global_ambient
    load_registry!
    @global_ambient || []
  end

  def scanned_count
    load_registry!
    @scanned_count || 0
  end

  private

  def portable_route_pattern?(pattern)
    return false if pattern.match?(/\\(?:A|Z|z|K|h|H|R|X|G|p|P|k|g|u|c|C|M)/)
    return false if pattern.include?("[[:") || pattern.include?("&&")
    return false if pattern.match?(/\(\?(?:>|P|[imx-]|<|\(|~|')/)

    true
  end

  def full_path
    File.join(root, registry_path)
  end

  def load_registry!
    return if @features

    raise MissingRegistryFileError, "Registry file not found at #{registry_path}" unless File.exist?(full_path)

    raw_content = File.read(full_path)
    data = begin
      YAML.safe_load(raw_content)
    rescue Psych::Exception => e
      raise InvalidRegistryError, "YAML parse error in #{registry_path}: #{e.message}"
    end

    if data.nil? || (data.is_a?(Hash) && data.empty?)
      raise EmptyRegistryError, "Registry file at #{registry_path} is empty"
    end
    raise InvalidRegistryError, "Registry root must be a Hash in #{registry_path}" unless data.is_a?(Hash)

    features_raw = data["features"]
    if features_raw.nil? || (features_raw.is_a?(Hash) && features_raw.empty?)
      raise EmptyRegistryError, "Missing or empty 'features' section in #{registry_path}"
    end
    raise InvalidRegistryError, "'features' must be a Hash in #{registry_path}" unless features_raw.is_a?(Hash)

    parsed_features = {}
    features_raw.each do |feature_name, feature_data|
      name_str = feature_name.to_s
      raise InvalidRegistryError, "Feature '#{name_str}' definition must be a Hash" unless feature_data.is_a?(Hash)

      raw_params = feature_data["parameters"]
      raise InvalidRegistryError, "Feature '#{name_str}' missing 'parameters' array" unless raw_params.is_a?(Array)
      raise EmptyRegistryError, "Feature '#{name_str}' has empty 'parameters' array" if raw_params.empty?

      params = raw_params.map(&:to_s)
      raw_patterns = feature_data["route_patterns"]
      raise InvalidRegistryError, "Feature '#{name_str}' missing 'route_patterns' array" unless raw_patterns.is_a?(Array)
      raise EmptyRegistryError, "Feature '#{name_str}' has empty 'route_patterns' array" if raw_patterns.empty?

      patterns = raw_patterns.map do |pattern|
        raise InvalidRegistryError, "Feature '#{name_str}' route patterns must be Strings" unless pattern.is_a?(String)
        unless portable_route_pattern?(pattern)
          raise InvalidRegistryError,
            "Feature '#{name_str}' route pattern is not portable between Ruby and JavaScript"
        end

        Regexp.new(pattern)
        pattern
      rescue RegexpError => e
        raise InvalidRegistryError, "Feature '#{name_str}' has invalid route pattern: #{e.message}"
      end

      raw_families = feature_data["parameter_families"]
      unless raw_families.is_a?(Hash)
        raise InvalidRegistryError, "Feature '#{name_str}' 'parameter_families' must be a Hash"
      end

      families = {}
      raw_families.each do |canonical, aliases_raw|
        canonical_str = canonical.to_s
        unless params.include?(canonical_str)
          raise InvalidRegistryError, "Feature '#{name_str}' has a family for undeclared parameter '#{canonical_str}'"
        end
        unless aliases_raw.is_a?(Array)
          raise InvalidRegistryError, "Feature '#{name_str}' family '#{canonical_str}' must be an Array"
        end

        families[canonical_str] = aliases_raw.map do |legacy_alias|
          raise InvalidRegistryError, "Feature '#{name_str}' aliases must be Strings" unless legacy_alias.is_a?(String)

          legacy_alias
        end
      end

      missing_families = params - families.keys
      unless missing_families.empty?
        raise InvalidRegistryError,
          "Feature '#{name_str}' is missing parameter families for: #{missing_families.sort.join(", ")}"
      end

      alias_names = families.values.flatten
      duplicate_aliases = alias_names.tally.select { |_name, count| count > 1 }.keys
      unless duplicate_aliases.empty?
        raise InvalidRegistryError,
          "Feature '#{name_str}' assigns aliases to multiple families: #{duplicate_aliases.sort.join(", ")}"
      end

      conflicting_names = alias_names & params
      unless conflicting_names.empty?
        raise InvalidRegistryError,
          "Feature '#{name_str}' aliases collide with canonical parameters: #{conflicting_names.sort.join(", ")}"
      end

      legacy_aliases = alias_names

      parsed_features[name_str] = {
        parameters: params,
        legacy_aliases: legacy_aliases,
        route_patterns: patterns,
        parameter_families: families.transform_values(&:freeze).freeze
      }.freeze
    end

    raw_ambient = data["global_ambient"] || data["global_ambient_parameters"] || []
    raise InvalidRegistryError, "'global_ambient' must be an Array" unless raw_ambient.is_a?(Array)

    parsed_ambient = raw_ambient.map(&:to_s).freeze

    total_scanned = parsed_features.values.sum { |f| f[:parameters].length } + parsed_ambient.length
    raise EmptyRegistryError, "Registry at #{registry_path} contains 0 parameters" if total_scanned.zero?

    @features = parsed_features.freeze
    @canonical_parameters = parsed_features.transform_values { |f| f[:parameters] }.freeze
    @global_ambient = parsed_ambient
    @scanned_count = total_scanned
    @registry_projection = {
      global_ambient: @global_ambient,
      features: parsed_features.transform_values do |feature|
        {
          parameters: feature[:parameters],
          route_patterns: feature[:route_patterns],
          parameter_families: feature[:parameter_families]
        }
      end
    }.freeze
  end

  def detect_parameter_collisions(offences)
    claimants_by_param = Hash.new { |hash, key| hash[key] = [] }

    features.each do |feature_name, feature_data|
      feature_data[:parameters].uniq.each do |param|
        claimants_by_param[param] << feature_name
      end
    end

    claimants_by_param.each do |param, claimants|
      if claimants.length > 1
        offences << Offence.new(
          "Parameter '#{param}' is claimed by multiple features: #{claimants.sort.join(", ")}"
        )
      end
    end
  end

  def detect_duplicate_parameters_within_features(offences)
    features.each do |feature_name, feature_data|
      params = feature_data[:parameters]
      duplicates = params.tally.select { |_param, count| count > 1 }.keys
      duplicates.each do |param|
        offences << Offence.new(
          "Feature '#{feature_name}' declares duplicate parameter '#{param}'"
        )
      end
    end
  end

  def detect_ambient_collisions(offences)
    features.each do |feature_name, feature_data|
      feature_data[:parameters].uniq.each do |param|
        if global_ambient.include?(param)
          offences << Offence.new(
            "Parameter '#{param}' is claimed by feature '#{feature_name}' and declared as global ambient"
          )
        end
      end
    end
  end

  def detect_duplicate_ambient_parameters(offences)
    duplicates = global_ambient.tally.select { |_param, count| count > 1 }.keys
    duplicates.each do |param|
      offences << Offence.new(
        "Global ambient parameter '#{param}' is declared multiple times"
      )
    end
  end
end
