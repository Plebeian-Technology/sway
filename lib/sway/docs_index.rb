# frozen_string_literal: true

require "psych"

module Sway
  # @lat: [[comments-and-docs#The legacy docs index and its generator]]
  class DocsIndex
    class Malformed < StandardError; end

    TITLE = "# Documentation index"
    GENERATED_NOTE =
      "Generated from docs/**/*.md frontmatter by `bundle exec rake sway:docs:index` — do not edit by hand."
    SECTIONS = [
      ["Tutorials", "tutorials"],
      ["How-to", "how-to"],
      ["Reference", "reference"],
      ["Explanation", "explanation"]
    ].freeze #: Array[[String, String]]
    EMPTY_SECTION = "(none yet)"
    UNREVIEWED_STATUS = "agent-extracted"

    def initialize(root)
      @root = root.to_s
    end

    def render
      lines = [TITLE, "", GENERATED_NOTE, ""]

      SECTIONS.each do |heading, directory|
        lines << "## #{heading}" << ""
        rows = rows_for(directory)
        lines.concat(rows.empty? ? [EMPTY_SECTION] : rows)
        lines << ""
      end

      lines.join("\n")
    end

    def path
      File.join(@root, "docs", "index.md")
    end

    def write
      before = File.exist?(path) ? File.read(path) : nil
      rendered = render
      return false if before == rendered

      File.write(path, rendered)
      true
    end

    private

    def rows_for(directory)
      Dir.glob(File.join(@root, "docs", directory, "*.md")).sort
        .map { |path| entry(path) }
        .sort_by { |title, _line| title.downcase }
        .map(&:last)
    end

    def entry(path)
      text = File.read(path)
      meta = front_matter(path, text)

      heading = text[/^# (.+)$/, 1]
      if heading.nil?
        raise Malformed, "#{relative(path)} has no `# ` heading, so the index has no title to list it under"
      end
      title = heading #: String

      declared_summary = meta["summary"]
      raise Malformed, "#{relative(path)} has no `summary:` in its frontmatter" if declared_summary.nil?
      summary = declared_summary #: String

      line = "- [#{title}](#{relative(path).delete_prefix("docs/")}) — #{summary}"
      line += " [unreviewed]" if meta["status"] == UNREVIEWED_STATUS
      [title, line]
    end

    def front_matter(path, text)
      matched = text[/\A---\n(.*?)\n---\n/m, 1]
      if matched.nil?
        raise Malformed, "#{relative(path)} has no frontmatter, so nothing can be said about it in the index"
      end
      header = matched #: String

      parsed = Psych.safe_load(header, permitted_classes: [Date, Time], aliases: false)
      raise Malformed, "#{relative(path)} has frontmatter that is not a mapping" unless parsed.is_a?(Hash)

      parsed
    end

    def relative(path)
      path.delete_prefix("#{@root}/")
    end
  end
end
