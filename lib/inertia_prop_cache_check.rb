# frozen_string_literal: true

require "prism"

# @lat: [[identity-scoped-prop-caches#The gate]]
class InertiaPropCacheCheck
  SCANNED_DIRECTORY = "app"

  EXCLUDED_PREFIX = "app/frontend/"

  RUBY_LIKE_EXTENSIONS = [".rb", ".builder"].freeze

  CACHING_METHODS = [:once, :cache].freeze

  CACHING_KEYWORDS = ["cache:", "once:"].freeze

  DISCRIMINATOR = /(?<![A-Za-z0-9])(current_user|user|sway_locale|locale|role|admin)(?![A-Za-z0-9])/i

  ALLOWED_PATHS = [].freeze

  class Offence
    attr_reader :path, :line, :source

    def initialize(path:, line:, source:)
      @path = path
      @line = line
      @source = source
    end

    def to_s
      "#{path}:#{line} #{source}"
    end
  end

  class MissingAllowlistedPathError < StandardError; end

  class InertiaCallVisitor < Prism::Visitor
    attr_reader :calls

    def initialize
      super
      @calls = []
    end

    def visit_call_node(node)
      @calls << node if inertia_prop_cache?(node)
      super
    end

    private

    def inertia_prop_cache?(node)
      return false unless receiver_name(node.receiver) == "InertiaRails"
      return true if CACHING_METHODS.include?(node.name)

      arguments = node.arguments&.slice.to_s
      CACHING_KEYWORDS.any? { |keyword| arguments.include?(keyword) }
    end

    def receiver_name(node)
      case node
      when Prism::ConstantReadNode
        node.name.to_s
      when Prism::ConstantPathNode
        node.name&.to_s
      end
    end
  end

  def initialize(root)
    @root = root
  end

  def offences
    assert_allowed_paths_exist!
    scanned_paths.flat_map { |path| offences_in(path) }
  end

  def allowed_paths
    ALLOWED_PATHS
  end

  def scanned_paths
    @scanned_paths ||= Dir.glob(File.join(root, SCANNED_DIRECTORY, "**", "*"))
      .select { |path| File.file?(path) }
      .map { |path| relative(path) }
      .reject { |path| path.start_with?(EXCLUDED_PREFIX) }
      .select { |path| RUBY_LIKE_EXTENSIONS.any? { |extension| path.end_with?(extension) } }
      .sort
  end

  private

  attr_reader :root

  def assert_allowed_paths_exist!
    missing = ALLOWED_PATHS.reject { |path| File.file?(File.join(root, path)) }
    return if missing.empty?

    raise MissingAllowlistedPathError,
      "The allowed path(s) no longer exist on disk: #{missing.join(", ")}. " \
      "Update InertiaPropCacheCheck::ALLOWED_PATHS."
  end

  def offences_in(relative_path)
    return [] if ALLOWED_PATHS.include?(relative_path)

    visitor = InertiaCallVisitor.new
    Prism.parse(File.read(File.join(root, relative_path))).value.accept(visitor)

    visitor.calls.filter_map { |node|
      arguments = node.arguments&.slice.to_s
      next if DISCRIMINATOR.match?(arguments)

      Offence.new(
        path: relative_path,
        line: node.location.start_line,
        source: node.slice.lines.first.to_s.strip
      )
    }
  end

  def relative(path)
    path.delete_prefix("#{root}/")
  end
end
