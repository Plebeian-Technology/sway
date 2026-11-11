# frozen_string_literal: true

require "fileutils"

module Sway
  # @lat: [[github-wiki-sync#How GitHubWikiBuilder compiles lat.md for Gollum]]
  # @lat: [[github-wiki-sync#Why GitHubWikiBuilder lives under scripts/]]
  class GitHubWikiBuilder
    DEFAULT_REPO = "Plebeian-Technology/sway"
    DEFAULT_BRANCH = "main"
    ROOT_DOC = "lat.md/lat.md"
    HOME_SLUG = "Home"
    SIDEBAR_FILE = "_Sidebar.md"

    FRONTMATTER_PATTERN = /\A---\r?\n.*?\r?\n---\r?\n+/m
    FENCE_LINE_PATTERN = /\A\s*(?:```|~~~)/
    ESCAPED_WIKI_LINK_PATTERN = /\\\[\\\[([^\[\]]+)\\\]\\\]/
    CODE_WRAPPED_WIKI_LINK_PATTERN = /`\[\[([^\[\]`]+)\]\]`/
    WIKI_LINK_PATTERN = /\[\[([^\[\]]+)\]\]/
    MARKDOWN_LINK_PATTERN = /(?<!!)\[([^\[\]]+)\]\(([^()\s]+)\)/

    def initialize(root, repo: DEFAULT_REPO, branch: DEFAULT_BRANCH)
      @root = File.expand_path(root.to_s)
      @repo = repo
      @branch = branch
      @source_files = nil
      @slug_by_file = nil
      @file_by_stem = nil
    end

    def source_files
      @source_files ||= discover_source_files
    end

    def slug_for(relative_path)
      slug_by_file.fetch(relative_path)
    end

    def render_page(relative_path)
      raw = File.read(File.join(@root, relative_path))
      body = raw.sub(FRONTMATTER_PATTERN, "")
      in_fence = false

      transformed = body.lines.map do |line|
        if line.match?(FENCE_LINE_PATTERN)
          in_fence = !in_fence
          line
        elsif in_fence
          line
        else
          transform_line(relative_path, line)
        end
      end

      transformed.join
    end

    def render_sidebar
      [
        "## Sway Documentation",
        "",
        "- [Home](#{HOME_SLUG})",
        "",
        "### Diátaxis Modes",
        "",
        "- [Tutorials](tutorials)",
        "- [How-to Guides](how-to)",
        "- [Reference](reference)",
        "- [Explanation](explanation)",
        "",
        "### Key Entrypoints",
        "",
        "- [System Shape](system-shape)",
        "- [Trace a Vote](trace-a-vote)",
        "- [Domain Entities](domain-entities)",
        "- [Naming Decisions](naming-decisions)",
        "- [Distributed Testimony Pipeline](distributed-testimony-pipeline)",
        ""
      ].join("\n")
    end

    def build(output_dir)
      target = File.expand_path(output_dir.to_s)
      FileUtils.mkdir_p(target)

      Dir.glob(File.join(target, "*.md")).each do |existing|
        FileUtils.rm_f(existing)
      end

      written = [] #: Array[String]
      source_files.each do |relative_path|
        filename = "#{slug_for(relative_path)}.md"
        File.write(File.join(target, filename), render_page(relative_path))
        written << filename
      end

      File.write(File.join(target, SIDEBAR_FILE), render_sidebar)
      written << SIDEBAR_FILE
      written.sort
    end

    private

    def discover_source_files
      git_files = git_tracked_lat_files
      files = git_files.empty? ? filesystem_lat_files : git_files
      files.select { |path| File.file?(File.join(@root, path)) }.sort
    end

    def git_tracked_lat_files
      return [] unless File.exist?(File.join(@root, ".git"))

      output = IO.popen(
        ["git", "-C", @root, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "lat.md/*.md", "lat.md/**/*.md"],
        err: File::NULL,
        &:read
      )
      return [] unless $?&.success?

      output.split("\0").reject { |path| excluded_lat_path?(path) }
    rescue Errno::ENOENT
      []
    end

    def filesystem_lat_files
      Dir.glob(File.join(@root, "lat.md", "**", "*.md"))
        .map { |abs| abs.delete_prefix("#{@root}/") }
        .reject { |path| excluded_lat_path?(path) }
    end

    def excluded_lat_path?(path)
      path.include?("/.cache/") || path.start_with?("lat.md/.cache/")
    end

    def file_by_stem
      @file_by_stem ||= begin
        grouped = {} #: Hash[String, Array[String]]
        source_files.each do |path|
          stem = File.basename(path, ".md")
          list = grouped[stem] ||= []
          list << path
        end
        grouped
      end
    end

    def slug_by_file
      @slug_by_file ||= begin
        mapping = {} #: Hash[String, String]
        source_files.each do |path|
          stem = File.basename(path, ".md")
          mapping[path] =
            if path == ROOT_DOC
              HOME_SLUG
            elsif file_by_stem.fetch(stem).size > 1
              mode = path.split("/")[1].to_s
              "#{mode}-#{stem}"
            else
              stem
            end
        end
        mapping
      end
    end

    def transform_line(current_file, line)
      rewritten = line.gsub(ESCAPED_WIKI_LINK_PATTERN) { "[[" + Regexp.last_match(1).to_s + "]]" }
      rewritten = rewritten.gsub(CODE_WRAPPED_WIKI_LINK_PATTERN) do
        resolve_wiki_link(current_file, Regexp.last_match(1).to_s, code_wrapped: true)
      end
      rewritten = rewritten.gsub(WIKI_LINK_PATTERN) do
        match_data = Regexp.last_match
        prefix = match_data ? match_data.pre_match : ""
        if prefix.end_with?("@lat: ")
          match_data.to_s
        else
          resolve_wiki_link(current_file, match_data ? match_data[1].to_s : "", code_wrapped: false)
        end
      end
      rewritten.gsub(MARKDOWN_LINK_PATTERN) do
        label = Regexp.last_match(1).to_s
        href = Regexp.last_match(2).to_s
        resolve_markdown_link(current_file, label, href)
      end
    end

    def resolve_wiki_link(current_file, inner, code_wrapped:)
      parts = inner.split("|", 2)
      raw_target = parts[0].to_s.strip
      explicit_alias = parts[1]&.strip

      target_parts = raw_target.split("#", 2)
      path_part = target_parts[0].to_s.strip
      fragment_part = target_parts[1].to_s.strip

      if path_part.empty?
        heading = last_fragment_segment(fragment_part)
        url = "##{heading_anchor(heading)}"
        label = explicit_alias || heading
        return format_markdown_link(label, url, code_wrapped: code_wrapped)
      end

      target_file = resolve_lat_file(current_file, path_part)
      if target_file
        slug = slug_for(target_file)
        anchor =
          if fragment_part.empty?
            ""
          else
            "##{heading_anchor(last_fragment_segment(fragment_part))}"
          end
        default_label =
          if fragment_part.empty?
            File.basename(target_file, ".md")
          else
            last_fragment_segment(fragment_part)
          end
        label = explicit_alias || default_label
        return format_markdown_link(label, "#{slug}#{anchor}", code_wrapped: code_wrapped)
      end

      repo_path = path_part.delete_prefix("/")
      kind = File.directory?(File.join(@root, repo_path)) ? "tree" : "blob"
      anchor =
        if repo_path.end_with?(".md") && !fragment_part.empty?
          "##{heading_anchor(last_fragment_segment(fragment_part))}"
        else
          ""
        end
      default_label =
        if fragment_part.empty?
          repo_path
        else
          last_fragment_segment(fragment_part)
        end
      label = explicit_alias || default_label
      url = "https://github.com/#{@repo}/#{kind}/#{@branch}/#{repo_path}#{anchor}"
      format_markdown_link(label, url, code_wrapped: code_wrapped)
    end

    def resolve_markdown_link(current_file, label, href)
      return "[#{label}](#{href})" if href.start_with?("http://", "https://", "mailto:", "#")

      parts = href.split("#", 2)
      path_part = parts[0].to_s
      fragment_part = parts[1].to_s

      target_file = resolve_lat_file(current_file, path_part)
      if target_file
        slug = slug_for(target_file)
        anchor =
          if fragment_part.empty?
            ""
          else
            "##{heading_anchor(last_fragment_segment(fragment_part))}"
          end
        return "[#{label}](#{slug}#{anchor})"
      end

      expanded = File.expand_path(path_part, File.dirname(File.join(@root, current_file)))
      if expanded.start_with?("#{@root}/") && File.exist?(expanded)
        repo_path = expanded.delete_prefix("#{@root}/")
        kind = File.directory?(expanded) ? "tree" : "blob"
        anchor =
          if fragment_part.empty?
            ""
          else
            "##{heading_anchor(last_fragment_segment(fragment_part))}"
          end
        return "[#{label}](https://github.com/#{@repo}/#{kind}/#{@branch}/#{repo_path}#{anchor})"
      end

      "[#{label}](#{href})"
    end

    def resolve_lat_file(current_file, path_part)
      return nil if path_part.empty?

      candidates = candidate_lat_paths(current_file, path_part)
      matched = candidates.find { |candidate| slug_by_file.key?(candidate) }
      return matched if matched

      return nil if path_part.include?("/") && !path_part.start_with?("lat.md/")

      stem = File.basename(path_part, ".md")
      matches = file_by_stem.fetch(stem, [])
      return nil if matches.empty?
      return matches.first if matches.size == 1

      current_mode = current_file.split("/")[1].to_s
      matches.find { |m| m.split("/")[1] == current_mode } || matches.first
    end

    def candidate_lat_paths(current_file, path_part)
      clean = path_part.delete_prefix("/")
      current_dir = File.dirname(File.join(@root, current_file))
      rel_expanded = File.expand_path(clean, current_dir).delete_prefix("#{@root}/")
      base = File.basename(clean, ".md")

      [
        with_md(clean),
        "#{clean}/#{base}.md",
        with_md("lat.md/#{clean}"),
        "lat.md/#{clean}/#{base}.md",
        with_md(rel_expanded),
        "#{rel_expanded}/#{base}.md"
      ].uniq
    end

    def with_md(path)
      path.end_with?(".md") ? path : "#{path}.md"
    end

    def last_fragment_segment(fragment)
      fragment.split("#").last.to_s.strip
    end

    def heading_anchor(heading)
      heading
        .downcase
        .gsub(/[^\p{Alnum}\s_-]/, "")
        .tr(" ", "-")
    end

    def format_markdown_link(label, url, code_wrapped:)
      formatted_label =
        if code_wrapped && !label.start_with?("`")
          "`#{label}`"
        else
          label
        end
      "[#{formatted_label}](#{url})"
    end
  end
end
