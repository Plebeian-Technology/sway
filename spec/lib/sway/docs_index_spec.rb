# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# @lat: [[comments-and-docs#The legacy docs index and its generator]]
RSpec.describe Sway::DocsIndex do
  it "writes exactly the index that is checked in" do
    expect(described_class.new(Rails.root).render).to eq(Rails.root.join("docs", "index.md").read),
      "docs/index.md is not what the generator produces. Run: bundle exec rake sway:docs:index"
  end

  it "lists every document under the four mode directories" do
    documented = Rails.root.glob("docs/{tutorials,how-to,reference,explanation}/*.md").size
    listed = Rails.root.join("docs", "index.md").read.lines.count { |line| line.start_with?("- [") }

    expect(listed).to eq(documented)
  end

  describe "one entry's shape" do
    it "reads the title from the heading and the rest from the frontmatter" do
      Dir.mktmpdir("docs-index") do |root|
        FileUtils.mkdir_p(File.join(root, "docs", "reference"))
        File.write(File.join(root, "docs", "reference", "a-thing.md"), <<~DOC)
          ---
          mode: reference
          summary: "What the thing is."
          status: agent-extracted
          related: []
          ---

          # A thing

          Body.
        DOC

        rendered = described_class.new(root).render

        expect(rendered).to include(
          "- [A thing](reference/a-thing.md) — What the thing is. [unreviewed]\n"
        )
        expect(rendered).to include("## Tutorials\n\n(none yet)\n")
      end
    end

    it "tags nothing but an agent-extracted document as unreviewed" do
      Dir.mktmpdir("docs-index") do |root|
        FileUtils.mkdir_p(File.join(root, "docs", "how-to"))
        File.write(File.join(root, "docs", "how-to", "b-thing.md"), <<~DOC)
          ---
          mode: how-to
          summary: "How to do the thing."
          status: human-reviewed
          ---

          # Do the thing
        DOC

        expect(described_class.new(root).render).to include(
          "- [Do the thing](how-to/b-thing.md) — How to do the thing.\n"
        )
      end
    end
  end

  # A document the generator cannot describe stops the run and names itself,
  # rather than going unlisted the way five did.
  it "refuses a document with no frontmatter" do
    Dir.mktmpdir("docs-index") do |root|
      FileUtils.mkdir_p(File.join(root, "docs", "explanation"))
      File.write(File.join(root, "docs", "explanation", "bare.md"), "# Bare\n")

      expect { described_class.new(root).render }
        .to raise_error(Sway::DocsIndex::Malformed, /docs\/explanation\/bare\.md has no frontmatter/)
    end
  end

  it "refuses a document with no heading" do
    Dir.mktmpdir("docs-index") do |root|
      FileUtils.mkdir_p(File.join(root, "docs", "explanation"))
      File.write(File.join(root, "docs", "explanation", "headless.md"), <<~DOC)
        ---
        mode: explanation
        summary: "No heading anywhere."
        status: agent-extracted
        ---

        Body with no heading.
      DOC

      expect { described_class.new(root).render }
        .to raise_error(Sway::DocsIndex::Malformed, /headless\.md has no `# ` heading/)
    end
  end
end
