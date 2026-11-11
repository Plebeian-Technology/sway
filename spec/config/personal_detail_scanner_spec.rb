# frozen_string_literal: true

require "rails_helper"
require "support/personal_detail_scanner"

# @lat: [[lat.md/explanation/personal-detail-scanner-design#Why the scanner is proven against an isolated git tree]]
RSpec.describe PersonalDetailScanner do
  # Each planted tree is its own throwaway git repo, not a subdirectory of Sway
  # itself: `git ls-files` only sees what has been `git add`ed, and building a
  # fresh index per example is the only way to prove the scanner catches a
  # *planted* detail rather than something already sitting in the real tree.
  def scanner_over(files)
    dir = Dir.mktmpdir("personal-detail-scanner-spec")
    (@tmp_dirs ||= []) << dir

    files.each do |relative_path, content|
      full_path = File.join(dir, relative_path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.binwrite(full_path, content)
    end

    system("git", "-C", dir, "init", "-q")
    system("git", "-C", dir, "-c", "user.email=spec@example.com", "-c", "user.name=spec", "add", "-A")

    described_class.new(root: Pathname.new(dir))
  end

  after do
    (@tmp_dirs || []).each { |dir| FileUtils.remove_entry(dir) }
  end

  it "flags a planted email address, naming the path and line" do
    scanner = scanner_over("answers/example.json" => %({"body": "contact someone@example.com for details"}))

    expect(scanner.unexempt.map(&:kind)).to eq([:email])
    expect(scanner.unexempt.first.to_s).to match(%r{answers/example\.json:1 email})
  end

  it "flags a planted street address" do
    scanner = scanner_over("notes.md" => "The office moved to 1234 North Charles Street last spring.")

    expect(scanner.unexempt.map(&:kind)).to eq([:street_address])
  end

  it "flags a planted phone number in any of the common written forms" do
    scanner = scanner_over(
      "a.md" => "Call (410) 555-0123 for help.",
      "b.md" => "Or dial 410-555-0123 instead.",
      "c.md" => "Or try 410.555.0123 after five."
    )

    expect(scanner.unexempt.map(&:kind).uniq).to eq([:phone])
    expect(scanner.unexempt.size).to eq(3)
  end

  it "reports no unexempt findings over a clean tree" do
    scanner = scanner_over("report.md" => "The bill passed unanimously with no dissent recorded.")

    expect(scanner.unexempt).to eq([])
  end

  it "reports findings inside EXEMPT_PATHS through #findings, but excludes them from #unexempt" do
    stub_const("PersonalDetailScanner::EXEMPT_PATHS", {"exempt.md" => "a written reason, for this example only"})
    scanner = scanner_over("exempt.md" => "contact someone@example.com")

    expect(scanner.findings.map(&:kind)).to eq([:email])
    expect(scanner.findings.first.exempt).to be(true)
    expect(scanner.unexempt).to eq([])
  end

  it "scans .json files rather than skipping them, unlike EnvCredentialScanner" do
    scanner = scanner_over("eval/answers/25-0064/positions/x.json" => %({"note": "someone@example.com"}))

    expect(scanner.unexempt).not_to be_empty
    expect(scanner.unexempt.first.path).to end_with(".json")
  end

  it "skips a line that is not valid UTF-8 rather than raising" do
    invalid_line = +"mojibake: \xFF\xFE someone@example.com\n"
    invalid_line.force_encoding(Encoding::UTF_8)
    scanner = scanner_over("mixed.md" => "clean line, nothing here\n#{invalid_line}")

    expect { scanner.unexempt }.not_to raise_error
    expect(scanner.unexempt).to eq([])
  end

  # @lat: [[lat.md/explanation/personal-detail-scanner-design#Why one example scans Sway's own tree]]
  it "finds no unexempted personal detail anywhere in Sway's own committed tree" do
    scanner = described_class.new(root: Rails.root)

    expect(scanner.unexempt).to eq([]),
      "unexempted personal detail is committed to this repo:\n\n" \
      "#{scanner.unexempt.join("\n")}\n\n" \
      "Either remove the detail, or -- if it is a placeholder, Sway's own contact, a " \
      "third-party service address or a public official's published contact -- add the " \
      "path to PersonalDetailScanner::EXEMPT_PATHS with the evidence for that claim."
  end

  it "memoises #findings and #unexempt so calling either twice does not re-walk the tree" do
    scanner = scanner_over("clean.md" => "nothing to see here")

    first_findings = scanner.findings
    expect(scanner.findings).to equal(first_findings)

    first_unexempt = scanner.unexempt
    expect(scanner.unexempt).to equal(first_unexempt)
  end
end
