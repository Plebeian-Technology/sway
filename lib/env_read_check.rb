# frozen_string_literal: true

require "erb"
require "open3"
require "prism"

# @lat: [[env-read-check-design#Why sway_lint_env_reads_rake_spec.rb stubs EnvReadCheck.new for its failure-path examples]]
class EnvReadCheck
  # @lat: [[env-read-check-design#Why EnvReadCheck parses instead of searching]]
  ALLOWED_PATHS = ["app/lib/env_secret.rb"].freeze

  # @lat: [[env-read-check-design#Why sway_lint_env_reads_rake_spec.rb stubs EnvReadCheck.new for its failure-path examples]]
  RUBY_LIKE_EXTENSIONS = [".rb", ".builder"].freeze

  # @lat: [[env-read-check-design#Which extensions count as Ruby source]]
  NON_SOURCE_EXTENSIONS = %w[.png .jpg .jpeg .gif .svg .ico .webp .woff .woff2 .ttf .eot .otf].freeze

  class Offence
    attr_reader :path, :line

    def initialize(path:, line:)
      @path = path
      @line = line
    end

    def to_s
      "#{path}:#{line}"
    end
  end

  # @lat: [[env-read-check-design#Why a missing allowed path raises instead of passing]]
  # @lat: [[env-read-check-design#Why sway_lint_env_reads_rake_spec.rb stubs EnvReadCheck.new for its failure-path examples]]
  class MissingAllowlistedPathError < StandardError; end

  # @lat: [[env-read-check-design#The forms EnvConstantVisitor catches]]
  class EnvConstantVisitor < Prism::Visitor
    def initialize(lines)
      super()
      @lines = lines
    end

    def visit_constant_read_node(node)
      @lines << node.location.start_line if node.name == :ENV
      super
    end

    def visit_constant_path_node(node)
      @lines << node.location.start_line if node.name == :ENV
      super
    end
  end

  def initialize(root)
    @root = root
  end

  # @lat: [[env-read-check-design#Why offences includes the allowed path]]
  def offences
    assert_allowed_paths_exist!
    # @lat: [[env-read-check-design#Why skipped_paths must be called after offences]]
    @skipped_paths = []
    scanned_paths.flat_map { |path| offences_in(path) }
  end

  def allowed_paths
    ALLOWED_PATHS
  end

  # @lat: [[env-read-check-design#Which files it looks at]]
  def scanned_paths
    @scanned_paths ||= git_tracked_app_files
  end

  # @lat: [[env-read-check-design#Why a name in skipped_paths is not a failure]]
  def skipped_paths
    @skipped_paths ||= []
  end

  private

  attr_reader :root

  def assert_allowed_paths_exist!
    missing = ALLOWED_PATHS.reject { |path| File.file?(File.join(root, path)) }
    return if missing.empty?

    raise MissingAllowlistedPathError,
      "The allowed path(s) no longer exist on disk: #{missing.join(", ")}. " \
      "This check has not run -- reporting zero findings here would be a " \
      "renamed guarded file silently switching a check off, which has " \
      "already happened once in this repository. Update " \
      "EnvReadCheck::ALLOWED_PATHS, or restore the missing file."
  end

  # @lat: [[env-read-check-design#Which files it looks at]]
  def git_tracked_app_files
    stdout, status =
      begin
        Open3.capture2("git", "-C", root.to_s, "ls-files", "-z", "--", "app")
      rescue Errno::ENOENT
        # @lat: [[run-the-stack#Run the stack locally#When a check shells out to git]]
        raise "git was not found on PATH -- this check did not run against #{root}."
      end
    raise "git ls-files failed under #{root} (exit #{status.exitstatus})" unless status.success?

    stdout.split("\0").reject { |path| path.start_with?("app/frontend/") }
  end

  def offences_in(relative_path)
    absolute = File.join(root, relative_path)
    return [] unless File.file?(absolute)

    if relative_path.end_with?(".erb")
      offences_from_erb(relative_path, absolute)
    elsif RUBY_LIKE_EXTENSIONS.any? { |ext| relative_path.end_with?(ext) }
      offences_from_ruby(relative_path, File.read(absolute))
    elsif NON_SOURCE_EXTENSIONS.any? { |ext| relative_path.end_with?(ext) }
      []
    else
      skipped_paths << relative_path
      []
    end
  end

  def offences_from_ruby(relative_path, source)
    lines_with_env(source).map { |line| Offence.new(path: relative_path, line: line) }
  end

  # @lat: [[env-read-check-design#Mapping ERB and Prism edge cases back to a real line number]]
  def offences_from_erb(relative_path, absolute)
    compiled = ERB.new(File.read(absolute), trim_mode: "-").src
    lines_with_env(compiled).map { |line| Offence.new(path: relative_path, line: line - 1) }
  end

  # @lat: [[env-read-check-design#Mapping ERB and Prism edge cases back to a real line number]]
  def lines_with_env(source)
    lines = [] #: Array[Integer]
    Prism.parse(source).value.accept(EnvConstantVisitor.new(lines))
    lines.sort
  end
end
