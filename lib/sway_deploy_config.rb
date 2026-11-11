# frozen_string_literal: true

# @lat: [[deploy-config-lookup-order#Lookup order]]
module SwayDeployConfig
  class MissingValue < StandardError; end

  FILE_VARIABLE = "SWAY_DEPLOY_CONFIG_FILE"

  REAL_FILE = "deploy/config/sway.env"
  TEST_FILE = "deploy/config/sway.test.env"
  EXAMPLE_FILE = "deploy/config/sway.env.example"

  class << self
    def [](name)
      from_environment = ENV[name]
      return from_environment unless blank?(from_environment)

      file_values[name]
    end

    def fetch(name)
      value = self[name]
      return value if value && !blank?(value)

      raise MissingValue, missing_message(name)
    end

    def require_values!(*names)
      missing = names.select { |name| blank?(self[name]) }
      raise MissingValue, missing_message(*missing) if missing.any?

      true
    end

    def file
      configured = ENV[FILE_VARIABLE]
      candidate =
        if configured && !blank?(configured)
          configured
        else
          test_environment? ? TEST_FILE : REAL_FILE
        end
      path = File.expand_path(candidate, root)
      File.exist?(path) ? path : nil
    end

    def root
      here = __dir__
      return File.expand_path("..", here) unless here.nil?

      raise MissingValue, "SwayDeployConfig was loaded without a file to sit beside"
    end

    def reload!
      @file_values = nil
      self
    end

    private

    def file_values
      @file_values ||= parse(file)
    end

    def parse(path)
      return {} if path.nil?

      File.readlines(path, chomp: true).each_with_object({}) do |line, values|
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?("#")

        stripped = stripped.sub(/\Aexport\s+/, "")
        name, separator, raw = stripped.partition("=")
        next if separator.empty?

        values[name.strip] = unquote(raw.strip)
      end
    end

    def unquote(value)
      return value.delete_prefix('"').delete_suffix('"') if value.length >= 2 && value.start_with?('"') && value.end_with?('"')
      return value.delete_prefix("'").delete_suffix("'") if value.length >= 2 && value.start_with?("'") && value.end_with?("'")

      value
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def test_environment?
      ENV["RAILS_ENV"] == "test" || ENV["RACK_ENV"] == "test"
    end

    def missing_message(*names)
      wanted = names.map { |name| "  #{name}" }.join("\n")
      using = file || "(no file — every value must come from the environment)"

      <<~MESSAGE
        Sway does not know #{names.one? ? "this value" : "these values"}:

        #{wanted}

        Values are looked for in this order:
          1. an environment variable of that name
          2. #{file || REAL_FILE}
          3. nothing — which is where this stopped

        Reading: #{using}

        To fix it, either set the variable for this one run:

          #{names.first}=... <your command>

        or write your own values once:

          cp #{EXAMPLE_FILE} #{REAL_FILE}
          # then edit #{REAL_FILE}

        #{REAL_FILE} is ignored by git on purpose. It holds the addresses and
        account names that belong to your installation and to nobody else's.
      MESSAGE
    end
  end
end
