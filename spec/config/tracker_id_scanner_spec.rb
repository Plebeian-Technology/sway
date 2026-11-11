# frozen_string_literal: true

require "rails_helper"
require "support/tracker_id_scanner"

RSpec.describe TrackerIdScanner do
  # Each planted tree is its own throwaway git repo, so `git ls-files` sees only what the example planted.
  def tracker_scanner_over(files, symlinks = {})
    dir = Dir.mktmpdir("tracker-id-scanner-spec")
    (@tmp_dirs ||= []) << dir

    files.each do |relative_path, content|
      full_path = File.join(dir, relative_path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.binwrite(full_path, content)
    end

    symlinks.each do |relative_path, target|
      full_path = File.join(dir, relative_path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.symlink(target, full_path)
    end

    system("git", "-C", dir, "init", "-q")
    system("git", "-C", dir, "-c", "user.email=spec@example.com", "-c", "user.name=spec", "add", "-A")

    described_class.new(root: Pathname.new(dir))
  end

  # Assembled from pieces so this spec is not a hit against the tree it guards.
  def planted_tracker_id(suffix = "abc12")
    "#{["SW", "AY"].join}-#{suffix}"
  end

  after do
    (@tmp_dirs || []).each { |dir| FileUtils.remove_entry(dir) }
  end

  it "flags a cited tracker id, naming the path and line" do
    scanner = tracker_scanner_over("docs/change.md" => "The rename landed under #{planted_tracker_id}.\n")

    expect(scanner.unexempt.map(&:id)).to eq([planted_tracker_id])
    expect(scanner.unexempt.first.to_s).to match(%r{\Adocs/change\.md:1 })
  end

  it "flags a child id carrying a dot-number suffix" do
    scanner = tracker_scanner_over("notes.md" => "Follow-up work is tracked as #{planted_tracker_id}.3 instead.\n")

    expect(scanner.unexempt.map(&:id)).to eq(["#{planted_tracker_id}.3"])
  end

  it "flags a lowercase id that mixes letters and digits" do
    scanner = tracker_scanner_over("docs/link.md" => "See the heading anchor (#{planted_tracker_id("4bjn5").downcase}).\n")

    expect(scanner.unexempt.map(&:id)).to eq([planted_tracker_id("4bjn5").downcase])
  end

  it "leaves a lowercase prefix followed by a plain word alone, so project and container names are safe" do
    prefix = planted_tracker_id("").downcase
    scanner = tracker_scanner_over(
      "app.css" => ".#{prefix}legislation { color: red; }\n",
      "compose.yml" => "services: #{prefix}test, #{prefix}dev, #{prefix}web, #{prefix}vite, #{prefix}12345678\n"
    )

    expect(scanner.findings).to eq([])
  end

  it "does not enter either of the two directories the export deletes" do
    scanner = tracker_scanner_over(
      "plans/rollout.md" => "Tracked as #{planted_tracker_id}.\n",
      "prompts/review.md" => "Tracked as #{planted_tracker_id}.\n"
    )

    expect(scanner.findings).to eq([])
  end

  it "does not read a binary file type, whatever bytes it happens to hold" do
    scanner = tracker_scanner_over("public/logo.png" => "\x89PNG\r\n\x1A\n#{planted_tracker_id}\n")

    expect(scanner.findings).to eq([])
  end

  it "reports findings inside EXEMPT_PATHS through #findings, but excludes them from #unexempt" do
    stub_const("TrackerIdScanner::EXEMPT_PATHS", {"exempt.py" => "a written reason, for this example only"})
    scanner = tracker_scanner_over("exempt.py" => "ISSUE = \"#{planted_tracker_id}\"\n")

    expect(scanner.findings.map(&:id)).to eq([planted_tracker_id])
    expect(scanner.findings.first.exempt).to be(true)
    expect(scanner.unexempt).to eq([])
  end

  it "skips a symlink rather than reporting its target's citation a second time" do
    scanner = tracker_scanner_over(
      {"cited.md" => "Tracked as #{planted_tracker_id}.\n"},
      {"alias.md" => "cited.md"}
    )

    expect(scanner.unexempt.map(&:path)).to eq(["cited.md"])
  end

  it "skips a line that is not valid UTF-8 rather than raising" do
    invalid_line = "mojibake: \xFF\xFE #{planted_tracker_id}\n"
    invalid_line.force_encoding(Encoding::UTF_8)
    scanner = tracker_scanner_over("mixed.md" => "clean line, nothing here\n#{invalid_line}")

    expect { scanner.unexempt }.not_to raise_error
    expect(scanner.unexempt).to eq([])
  end

  it "memoises #findings and #unexempt so calling either twice does not re-walk the tree" do
    scanner = tracker_scanner_over("clean.md" => "nothing to see here")

    first_findings = scanner.findings
    expect(scanner.findings).to equal(first_findings)

    first_unexempt = scanner.unexempt
    expect(scanner.unexempt).to equal(first_unexempt)
  end

  it "still reaches the tracker integration's own fixtures, so an empty walk is not read as a clean tree" do
    scanner = described_class.new(root: Rails.root)

    expect(scanner.findings.map(&:path)).to include("scripts/agent_hooks/test_issue_titles.py"),
      "the walk produced no hit in the one shipped file known to carry id-shaped fixtures, " \
      "which is what a failed or empty git ls-files looks like from here -- a scan of nothing " \
      "reports no hits and reads exactly like a clean tree"
  end

  # @lat: [[lat.md/explanation/comments-and-docs#Which way a reference points]]
  it "cites no private tracker id anywhere in Sway's own committed tree" do
    scanner = described_class.new(root: Rails.root)

    expect(scanner.unexempt).to eq([]),
      "a private tracker id is cited by a tracked file that ships to the public repository:\n\n" \
      "#{scanner.unexempt.join("\n")}\n\n" \
      "Nobody outside the tracker can resolve one. Name the change and the lat.md/ section it " \
      "belongs to instead, and leave the id in the tracker -- the tracker holds the pointer the " \
      "other way."
  end
end
