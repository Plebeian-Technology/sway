# frozen_string_literal: true

require "anyway_config"

module Sway
  module Settings
    # @lat: [[settings-groups#Why some groups declare a blank env prefix]]
    class Base < Anyway::Config
      # @lat: [[settings-and-secrets#Type casters]]
      # @lat: [[settings-groups#Why the base class replaces the gem's casters]]
      Anyway::TypeRegistry.default.tap do |registry|
        registry.accept(:string) do |value|
          stripped = value.to_s.strip
          stripped.empty? ? nil : stripped
        end

        integer_caster = lambda do |value|
          stripped = value.to_s.strip
          stripped.empty? ? nil : Integer(stripped, 10)
        end
        registry.accept(:integer, &integer_caster)
        registry.accept(:integer!, &integer_caster)

        float_caster = lambda do |value|
          stripped = value.to_s.strip
          next nil if stripped.empty?
          unless stripped.match?(/\A[+-]?(\d+(\.\d+)?|\.\d+)([eE][+-]?\d+)?\z/)
            raise ArgumentError, "invalid value for Float(): #{stripped.inspect}"
          end
          Float(stripped)
        end
        registry.accept(:float, &float_caster)
        registry.accept(:float!, &float_caster)

        registry.accept(:boolean) do |value|
          stripped = value.to_s.strip
          stripped.empty? ? nil : %w[true yes y 1 t].include?(stripped.downcase)
        end
      end

      # @lat: [[settings-groups#Why the mobile group's id and version numbers are text]]
      disable_auto_cast!

      # @lat: [[settings-groups#Why the required check moves to the end of the callbacks]]
      required_check = load_callbacks.find do |callback|
        callback.is_a?(Anyway::Config::NamedCallback) &&
          callback.name == :validate_required_attributes!
      end
      load_callbacks.delete(required_check) if required_check

      on_load do
        self.class.defaults.each do |name, fallback|
          public_send(:"#{name}=", fallback) if public_send(name).nil?
        end
      end

      load_callbacks << required_check if required_check

      class << self
        # @lat: [[settings-groups#Why the generated RBS interface is renamed per group]]
        def to_rbs
          interface_name = "_#{name.split("::").last}Config"
          super
            .sub("interface _Config", "interface #{interface_name}")
            .sub("include _Config", "include #{interface_name}")
        end

        # @lat: [[settings-groups#Why the freeze runs after a group's own repair]]
        def freeze_mutable_attributes!(instance)
          (config_attributes || []).each do |name|
            value = instance.public_send(name)
            instance.public_send(:"#{name}=", value.freeze) if value.is_a?(String) || value.is_a?(Array)
          end
        end
      end
    end
  end
end
