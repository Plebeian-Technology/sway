# frozen_string_literal: true

# @lat: [[lat.md/explanation/comments-and-docs#Which way a reference points]]
class TrackerIdScanner
  # One cited tracker id, at the place it was found.
  class Finding
    attr_reader :path, :line, :id, :exempt

    def initialize(path:, line:, id:, exempt:)
      @path = path
      @line = line
      @id = id
      @exempt = exempt
    end

    # The id is the whole finding, so the line it sat on is never quoted back.
    def to_s
      "#{path}:#{line} #{id}"
    end
  end

  # Assembled from pieces so this file is not a hit against itself.
  ID_PATTERN = Regexp.new(
    "#{["SW", "AY"].join}-[a-z0-9]{3,6}(?:\\.[0-9]+)*|" \
    "\\b#{["sw", "ay"].join}-(?=[a-z0-9]*[0-9])(?=[a-z0-9]*[a-z])[a-z0-9]{3,6}\\b"
  )

  # Paths the export removes are skipped.
  SKIPPED_PREFIXES = [
    "plans/",
    "prompts/"
  ].freeze

  # File types whose tracked bytes are not lines of text.
  SKIPPED_EXTENSIONS = %w[
    .png .jpg .jpeg .gif .webp .ico .ttf .otf .woff .woff2 .pdf .gz .zip .enc .sqlite3
  ].freeze

  # The reason every EXEMPT_PATHS entry below is built from.
  TRACKER_INTEGRATION =
    "scripts/agent_hooks/ is the tracker integration itself -- the hook that " \
    "makes an agent name a bd issue's title next to its id. It has to recognise " \
    "the id prefix to do its job, so an id-shaped string here is the code working " \
    "rather than a private reference a public reader cannot follow."

  # path => the evidence for accepting that path's findings.
  EXEMPT_PATHS = {
    "scripts/agent_hooks/install.py" =>
      "#{TRACKER_INTEGRATION} This file writes issue_titles.py into each agent host's hook configuration.",
    "scripts/agent_hooks/issue_titles.py" =>
      "#{TRACKER_INTEGRATION} Its own id-matching regex is what finds the cited ids in an agent's response.",
    "scripts/agent_hooks/test_issue_titles.py" =>
      "#{TRACKER_INTEGRATION} Every fixture in it is an id-shaped string fed through that hook."
  }.merge(
    [".dockerignore", "docker/dockerfiles/production.alpine.dockerfile.dockerignore"].to_h do |path|
      [path, "The entry /#{["sw", "ay"].join}-a2p.md names a local notes file about A2P SMS registration, not a tracker id, so it points at nothing private."]
    end
  ).freeze

  def initialize(root: Rails.root)
    @root = root
  end

  # @return [Array<Finding>] every cited id, including the ones EXEMPT_PATHS allows through.
  def findings
    @findings ||= scannable_paths.flat_map { |path| findings_in(path) }
  end

  # @return [Array<Finding>] the citations nothing has vouched for.
  def unexempt
    @unexempt ||= findings.reject(&:exempt)
  end

  private

  attr_reader :root

  def raw_paths
    listing = IO.popen(["git", "-C", root.to_s, "ls-files", "-z"]) { |io| io.read }
    raise "git ls-files failed in #{root}" unless $?&.success?
    listing.split("\0")
  end

  def scannable_paths
    raw_paths.reject do |path|
      SKIPPED_PREFIXES.any? { |prefix| path.start_with?(prefix) } ||
        SKIPPED_EXTENSIONS.include?(File.extname(path).downcase) ||
        !scannable_file?(root.join(path))
    end
  end

  # A tracked symlink's bytes are its target's.
  def scannable_file?(full_path)
    full_path.file? && !full_path.symlink?
  end

  def findings_in(path)
    exempt = EXEMPT_PATHS.key?(path)
    root.join(path).readlines.each_with_index.filter_map do |line, index|
      next unless line.valid_encoding?

      id = line[ID_PATTERN]
      next if id.nil?

      Finding.new(path: path, line: index + 1, id: id, exempt: exempt)
    end
  rescue ArgumentError
    # Binary content that slipped the extension filter.
    []
  end
end
