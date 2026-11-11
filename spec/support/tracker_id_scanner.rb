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

  # File types whose tracked bytes are not lines of text.
  SKIPPED_EXTENSIONS = %w[
    .png .jpg .jpeg .gif .webp .ico .ttf .otf .woff .woff2 .pdf .gz .zip .enc .sqlite3
  ].freeze

  # path => the evidence for accepting that path's findings.
  EXEMPT_PATHS = [".dockerignore", "docker/dockerfiles/production.alpine.dockerfile.dockerignore"].to_h do |path|
    [path, "The entry /#{["sw", "ay"].join}-a2p.md names a local notes file about A2P SMS registration, not a tracker id, so it points at nothing private."]
  end.freeze

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
