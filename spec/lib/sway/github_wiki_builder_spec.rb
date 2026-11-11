# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require_relative "../../../scripts/github_wiki_builder"

# @lat: [[github-wiki-sync#How GitHubWikiBuilder compiles lat.md for Gollum]]
RSpec.describe Sway::GitHubWikiBuilder do
  it "maps lat.md/lat.md to Home and disambiguates duplicate stems by Diátaxis mode" do
    Dir.mktmpdir("github-wiki-builder") do |root|
      FileUtils.mkdir_p(File.join(root, "lat.md", "explanation"))
      FileUtils.mkdir_p(File.join(root, "lat.md", "reference"))

      File.write(File.join(root, "lat.md", "lat.md"), "# Sway\n\nRoot overview.\n")
      File.write(File.join(root, "lat.md", "explanation", "unique-doc.md"), "# Unique\n\nBody.\n")
      File.write(File.join(root, "lat.md", "explanation", "shared-name.md"), "# Shared explanation\n\nBody.\n")
      File.write(File.join(root, "lat.md", "reference", "shared-name.md"), "# Shared reference\n\nBody.\n")

      builder = described_class.new(root)

      expect(builder.slug_for("lat.md/lat.md")).to eq("Home")
      expect(builder.slug_for("lat.md/explanation/unique-doc.md")).to eq("unique-doc")
      expect(builder.slug_for("lat.md/explanation/shared-name.md")).to eq("explanation-shared-name")
      expect(builder.slug_for("lat.md/reference/shared-name.md")).to eq("reference-shared-name")
    end
  end

  it "strips frontmatter, converts wiki and markdown links, and leaves fenced code blocks untouched" do
    Dir.mktmpdir("github-wiki-builder") do |root|
      FileUtils.mkdir_p(File.join(root, "lat.md", "explanation"))
      FileUtils.mkdir_p(File.join(root, "lat.md", "reference"))
      FileUtils.mkdir_p(File.join(root, "app", "services"))

      File.write(File.join(root, "app", "services", "foo.rb"), "class Foo; end\n")
      File.write(File.join(root, "lat.md", "reference", "target-doc.md"), <<~MD)
        ---
        lat:
          mode: reference
        ---

        # Target doc

        Overview.

        ## Outer section

        Outer overview.

        ### Inner Detail

        Inner overview.
      MD

      File.write(File.join(root, "lat.md", "explanation", "source-doc.md"), <<~'MD')
        ---
        lat:
          mode: explanation
        ---

        # Source doc

        See [[target-doc#Outer section#Inner Detail|the inner detail]] and `[[app/services/foo.rb#Foo]]`.
        Also see [Target](../reference/target-doc.md) and \[\[target-doc\]\].

        ```mermaid
        flowchart LR
            A[["Keep [[inside]] fence"]] --> B["Node"]
        ```
      MD

      builder = described_class.new(root, repo: "Plebeian-Technology/sway", branch: "main")
      rendered = builder.render_page("lat.md/explanation/source-doc.md")

      expect(rendered).not_to include("lat:\n  mode: explanation")
      expect(rendered).to include("[the inner detail](target-doc#inner-detail)")
      expect(rendered).to include("[`Foo`](https://github.com/Plebeian-Technology/sway/blob/main/app/services/foo.rb)")
      expect(rendered).to include("[Target](target-doc)")
      expect(rendered).to include("[target-doc](target-doc)")
      expect(rendered).to include('A[["Keep [[inside]] fence"]] --> B["Node"]')
    end
  end

  # @lat: [[github-wiki-sync#Why source discovery reads git ls-files]]
  it "excludes .cache directories and writes _Sidebar.md alongside compiled pages" do
    Dir.mktmpdir("github-wiki-builder") do |root|
      FileUtils.mkdir_p(File.join(root, "lat.md", ".cache", "parsed"))
      FileUtils.mkdir_p(File.join(root, "lat.md", "explanation"))

      File.write(File.join(root, "lat.md", ".cache", "parsed", "cached.md"), "# Secret cache\n")
      File.write(File.join(root, "lat.md", "lat.md"), "# Sway\n\nOverview.\n")
      File.write(File.join(root, "lat.md", "explanation", "topic.md"), "# Topic\n\nOverview.\n")

      Dir.mktmpdir("github-wiki-output") do |out|
        builder = described_class.new(root)
        written = builder.build(out)

        expect(written).to contain_exactly("Home.md", "_Sidebar.md", "topic.md")
        expect(File.read(File.join(out, "_Sidebar.md"))).to include("- [Home](Home)")
      end
    end
  end

  it "links the agent memory index in the sidebar only when that page is in the tree" do
    Dir.mktmpdir("github-wiki-builder") do |root|
      FileUtils.mkdir_p(File.join(root, "lat.md", "reference", "agent-memory"))
      File.write(File.join(root, "lat.md", "lat.md"), "# Sway\n\nOverview.\n")

      expect(described_class.new(root).render_sidebar).not_to include("agent-memory")

      File.write(File.join(root, "lat.md", "reference", "agent-memory", "agent-memory.md"), "# Memory\n\nOverview.\n")

      expect(described_class.new(root).render_sidebar).to include("- [Agent Memory Index](agent-memory)")
    end
  end

  it "compiles the repository's real lat.md tree with no unresolved wiki links" do
    Dir.mktmpdir("github-wiki-full") do |out|
      builder = described_class.new(Rails.root)
      written = builder.build(out)

      expect(written).to include("Home.md", "_Sidebar.md", "distributed-testimony-pipeline.md")

      unresolved = []
      written.each do |filename|
        in_fence = false
        File.readlines(File.join(out, filename)).each_with_index do |line, idx|
          if line.match?(Sway::GitHubWikiBuilder::FENCE_LINE_PATTERN)
            in_fence = !in_fence
            next
          end
          next if in_fence

          line.scan(/\[\[[^\]]+\]\]/) do |match|
            next if line.include?("@lat: #{match}")

            unresolved << "#{filename}:#{idx + 1}: #{match}"
          end
        end
      end

      expect(unresolved).to be_empty
    end
  end
end
