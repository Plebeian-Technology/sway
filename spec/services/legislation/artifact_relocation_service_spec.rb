# frozen_string_literal: true

require "rails_helper"

# @lat: [[rbs-signatures#Why a spec's helpers are invisible to Steep]]
RSpec.describe Legislation::ArtifactRelocationService do
  let(:relocation_root) { Pathname.new(Dir.mktmpdir("legislation-relocation")) }
  let(:sway_locale) { create(:sway_locale, :baltimore) }
  # The raising sibling, so the declared type is String, not String?. Every
  # path assertion below joins this value, and a nil would silently build a
  # path with a hole in it instead of failing.
  let(:locale_segment) { Legislation::Paths.sway_locale_segment!(sway_locale.name) }

  after { FileUtils.remove_entry(relocation_root) if relocation_root.exist? }

  def write_artifact(relative, contents = "x")
    path = relocation_root.join(relative)
    FileUtils.mkdir_p(path.dirname)
    path.write(contents)
    path
  end

  describe "bill-keyed trees" do
    it "moves a bill folder under the jurisdiction its bill belongs to" do
      create(:bill, external_id: "25-0064", sway_locale: sway_locale)
      write_artifact("bills/raw/25-0064/metadata.json", '{"MatterId":1}')

      report = described_class.new(root: relocation_root).call

      expect(relocation_root.join("bills/raw", locale_segment, "25-0064/metadata.json")).to exist
      expect(relocation_root.join("bills/raw/25-0064")).not_to exist
      expect(report.moved).to include("bills/raw/25-0064")
    end

    it "moves the text, hearings and diffs files for the same bill" do
      create(:bill, external_id: "25-0064", sway_locale: sway_locale)
      write_artifact("bills/text/25-0064.md")
      write_artifact("hearings/25-0064.json")
      write_artifact("diffs/25-0064.json")
      write_artifact("diffs/25-0064.md")

      described_class.new(root: relocation_root).call

      expect(relocation_root.join("bills/text", locale_segment, "25-0064.md")).to exist
      expect(relocation_root.join("hearings", locale_segment, "25-0064.json")).to exist
      expect(relocation_root.join("diffs", locale_segment, "25-0064.json")).to exist
      expect(relocation_root.join("diffs", locale_segment, "25-0064.md")).to exist
    end

    # The law corpus belongs to a jurisdiction's whole code rather than to one
    # bill, so Legislation::Paths.law never gained a jurisdiction segment and
    # nothing under it may be touched.
    it "leaves the law corpus alone" do
      write_artifact("law/charter.md")

      described_class.new(root: relocation_root).call

      expect(relocation_root.join("law/charter.md")).to exist
    end
  end

  describe "what it refuses to place" do
    it "leaves a file whose bill number matches nothing, and says so" do
      write_artifact("hearings/99-9999.json")

      report = described_class.new(root: relocation_root).call

      expect(relocation_root.join("hearings/99-9999.json")).to exist
      expect(report.left["hearings/99-9999.json"]).to eq("no bill is numbered 99-9999")
    end

    # The mistake this path change prevents: two cities can both number a
    # bill 25-0064, and a file named after just that number cant say which
    # wrote it. It stays unplaced and named instead of guessed.
    it "leaves a file two jurisdictions both claim, naming both" do
      other_locale = create(:sway_locale, city: "annapolis", state: "maryland", country: "united_states")
      create(:bill, external_id: "25-0064", sway_locale: sway_locale)
      create(:bill, external_id: "25-0064", sway_locale: other_locale)
      write_artifact("hearings/25-0064.json")

      report = described_class.new(root: relocation_root).call

      expect(relocation_root.join("hearings/25-0064.json")).to exist
      expect(report.left["hearings/25-0064.json"]).to include("2 jurisdictions claim it")
    end

    it "never overwrites a file already at the destination" do
      create(:bill, external_id: "25-0064", sway_locale: sway_locale)
      write_artifact("hearings/25-0064.json", "old")
      write_artifact("hearings/#{locale_segment}/25-0064.json", "current")

      report = described_class.new(root: relocation_root).call

      expect(relocation_root.join("hearings", locale_segment, "25-0064.json").read).to eq("current")
      expect(relocation_root.join("hearings/25-0064.json").read).to eq("old")
      expect(report.left["hearings/25-0064.json"]).to include("already at")
    end
  end

  describe "attachments" do
    it "moves an attachment under the jurisdiction of the bill that recorded it" do
      bill = create(:bill, external_id: "25-0064", sway_locale: sway_locale)
      create(
        :bill_llm_provisioning,
        bill: bill,
        testimony_attachments: [
          {"filename" => "BCFD 25-0064.pdf", "attachment_id" => "38897"}
        ]
      )
      write_artifact("attachments/attachment-38897.pdf")
      write_artifact("attachments/attachment-38897.txt")

      described_class.new(root: relocation_root).call

      expect(relocation_root.join("attachments", locale_segment, "attachment-38897.pdf")).to exist
      expect(relocation_root.join("attachments", locale_segment, "attachment-38897.txt")).to exist
    end

    # The id is stored as TEXT on every row. Comparing it as a number matches
    # nothing, silently, leaving an attachment behind under a reason that
    # reads like missing data.
    it "matches the stored id as text, not as a number" do
      bill = create(:bill, external_id: "25-0064", sway_locale: sway_locale)
      create(
        :bill_llm_provisioning,
        bill: bill,
        testimony_attachments: [{"attachment_id" => "38897"}]
      )
      write_artifact("attachments/attachment-38897.pdf")

      report = described_class.new(root: relocation_root).call

      expect(report.left).to be_empty
      expect(report.moved).to eq(["attachments/attachment-38897.pdf"])
    end

    it "leaves an attachment no bill records, and says so" do
      write_artifact("attachments/attachment-11111.pdf")

      report = described_class.new(root: relocation_root).call

      expect(relocation_root.join("attachments/attachment-11111.pdf")).to exist
      expect(report.left["attachments/attachment-11111.pdf"]).to eq("no bill records attachment 11111")
    end
  end

  describe "running it again" do
    it "does nothing the second time" do
      create(:bill, external_id: "25-0064", sway_locale: sway_locale)
      write_artifact("hearings/25-0064.json")

      described_class.new(root: relocation_root).call
      second = described_class.new(root: relocation_root).call

      expect(second.moved).to be_empty
      expect(second.left).to be_empty
      expect(relocation_root.join("hearings", locale_segment, "25-0064.json")).to exist
    end

    # A jurisdiction folder is a destination; the check reads names from the
    # database, not the name shape — else the second pass would treat its
    # own new folder as a bill.
    it "does not sweep a jurisdiction folder into itself" do
      create(:bill, external_id: "25-0064", sway_locale: sway_locale)
      write_artifact("bills/raw/25-0064/metadata.json")

      described_class.new(root: relocation_root).call
      described_class.new(root: relocation_root).call

      expect(relocation_root.join("bills/raw", locale_segment, "25-0064/metadata.json")).to exist
      expect(relocation_root.join("bills/raw", locale_segment, locale_segment)).not_to exist
    end
  end

  it "does nothing at all when there is no legislation directory" do
    empty = Pathname.new(Dir.mktmpdir("legislation-empty"))
    begin
      report = described_class.new(root: empty).call

      expect(report.moved).to be_empty
      expect(report.left).to be_empty
    ensure
      FileUtils.remove_entry(empty)
    end
  end
end
