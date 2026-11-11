# frozen_string_literal: true

require "rails_helper"
require "json"
require "fileutils"

# Specs for GenerateDiffsService. A diff means law BEFORE vs AFTER the
# operations apply, not bill version N vs N+1. Writes go to a temp dir
# (LEGISLATION_DIFFS_ROOT), never a real diffs/ folder.
module GenerateDiffsServiceSpecHelpers
  TMP_DIFFS_DIR = LegislationTestArtifacts.root_for("generate_diffs_spec").freeze

  # @lat: [[generate-diffs-service-spec-fixture-uniqueness#Why the diff-spec bill fixture counts offsets instead of picking a random day]]
  @release_date_offset = 0

  def self.next_release_date_offset
    @release_date_offset += 1
  end

  def self.build_op(operation:, anchor_text: nil, replacement_text: nil)
    BillAmendmentOperation.new(
      operation: operation,
      source: :text_pattern,
      anchor_text: anchor_text,
      replacement_text: replacement_text,
      char_start: 0,
      char_end: (anchor_text || replacement_text).to_s.length,
      ordinal: 0
    )
  end

  def self.make_bill(sway_locale:, legislator:, external_id:, parsing_target: "charter")
    bill = FactoryBot.create(:bill,
      sway_locale: sway_locale, legislator: legislator,
      external_id: external_id,
      scheduled_release_date_utc: 7.days.ago - next_release_date_offset.days)
    bill.update!(parsing_target: parsing_target, parsed_at: Time.current)
    bill.reload
  end
end

RSpec.describe GenerateDiffsService do
  around do |example|
    FileUtils.rm_rf(GenerateDiffsServiceSpecHelpers::TMP_DIFFS_DIR)
    FileUtils.mkdir_p(GenerateDiffsServiceSpecHelpers::TMP_DIFFS_DIR)
    with_app_config(:legislation, legislation_diffs_root: GenerateDiffsServiceSpecHelpers::TMP_DIFFS_DIR) {
      example.run
    }
  ensure
    FileUtils.rm_rf(GenerateDiffsServiceSpecHelpers::TMP_DIFFS_DIR)
  end

  describe described_class::ApplyOperations do
    it "STRIKE removes first occurrence when anchor is present" do
      result = described_class.call("foo bar baz\n", [GenerateDiffsServiceSpecHelpers.build_op(operation: :strike, anchor_text: "bar ")])
      expect(result.after_text).to eq("foo baz\n")
      expect(result.warnings).to eq([])
    end

    it "STRIKE warns when anchor is absent" do
      result = described_class.call("foo baz\n", [GenerateDiffsServiceSpecHelpers.build_op(operation: :strike, anchor_text: "MISSING")])
      expect(result.after_text).to eq("foo baz\n")
      expect(result.warnings).to eq(["STRIKE text not found: \"MISSING\""])
    end

    it "INSERT appends payload prefixed with newline" do
      result = described_class.call("foo\n", [GenerateDiffsServiceSpecHelpers.build_op(operation: :insert, replacement_text: "bar")])
      expect(result.after_text).to eq("foo\n\nbar")
      expect(result.warnings).to eq([])
    end

    it "REPLACE happy path substitutes anchor -> replacement" do
      op = GenerateDiffsServiceSpecHelpers.build_op(operation: :replace, anchor_text: "old", replacement_text: "new")
      result = described_class.call("AAA old BBB", [op])
      expect(result.after_text).to eq("AAA new BBB")
      expect(result.warnings).to eq([])
    end

    it "REPLACE warns when text-pattern source omits ' -> ' separator (Pitfall 2 — DO NOT FIX)" do
      op = GenerateDiffsServiceSpecHelpers.build_op(operation: :replace, anchor_text: "striking foo and inserting", replacement_text: nil)
      result = described_class.call("striking foo and inserting", [op])
      expect(result.after_text).to eq("striking foo and inserting")
      expect(result.warnings.first).to start_with("REPLACE missing ' -> ' separator:")
    end

    it "REPLACE warns when source text is absent" do
      op = GenerateDiffsServiceSpecHelpers.build_op(operation: :replace, anchor_text: "old", replacement_text: "new")
      result = described_class.call("nothing to match here", [op])
      expect(result.after_text).to eq("nothing to match here")
      expect(result.warnings.first).to start_with("REPLACE source not found:")
    end

    it "String#sub semantics (Pitfall 4) — STRIKE removes only the first occurrence" do
      result = described_class.call("foo foo foo", [GenerateDiffsServiceSpecHelpers.build_op(operation: :strike, anchor_text: "foo")])
      expect(result.after_text).to eq(" foo foo")
    end
  end

  describe described_class::DiffRenderer do
    it "returns empty string when inputs are identical" do
      expect(described_class.make_diff_block("a\nb\n", "a\nb\n")).to eq("")
    end

    it "renders a pure-insert hunk" do
      block = described_class.make_diff_block("a\n", "a\nb\n")
      expect(block).to start_with("```diff\n")
      expect(block).to end_with("\n```")
      expect(block).to include("+b")
    end

    it "renders a pure-delete hunk" do
      block = described_class.make_diff_block("a\nb\n", "a\n")
      expect(block).to include("-b")
      expect(block).not_to include("+b")
    end

    it "expands replace sdiff action into adjacent - and + lines" do
      block = described_class.make_diff_block("foo\n", "bar\n")
      expect(block).to include("-foo")
      expect(block).to include("+bar")
    end

    it "preserves trailing newline via String#lines (Pitfall 6)" do
      block = described_class.make_diff_block("foo\n", "foo\nbar\n")
      # Each line's text (for example "foo\n") is part of the diff string, and
      # the unchanged-line marker " foo" keeps the trailing newline that
      # String#lines preserved.
      expect(block).to include(" foo")
      expect(block).to include("+bar")
    end
  end

  # A disk failure must cost one bill, not the run. Errno::ENOSPC and friends
  # are SystemCallErrors, not BillProcessingErrors, so they used to reach the
  # catch-all and force-fail every remaining bill.
  describe described_class::ResultWriter do
    let(:sway_locale) { create(:sway_locale) }
    let(:legislator) { create(:legislator, district: create(:district, sway_locale: sway_locale)) }

    it "turns a full disk during the JSON write into a per-bill BillProcessingError" do
      bill = GenerateDiffsServiceSpecHelpers.make_bill(
        sway_locale: sway_locale, legislator: legislator, external_id: "DISK-JSON"
      )
      allow_any_instance_of(Pathname).to receive(:write).and_raise(Errno::ENOSPC, "No space left on device")

      expect { described_class.write_json(bill, {"a" => 1}) }
        .to raise_error(BillProcessingError, /generate_diffs: artifact write failed.*ENOSPC/m)
    end

    it "turns a full disk during the Markdown write into a per-bill BillProcessingError" do
      bill = GenerateDiffsServiceSpecHelpers.make_bill(
        sway_locale: sway_locale, legislator: legislator, external_id: "DISK-MD"
      )
      allow_any_instance_of(Pathname).to receive(:write).and_raise(Errno::EROFS, "Read-only file system")

      expect { described_class.write_markdown(bill, "# body") }
        .to raise_error(BillProcessingError, /generate_diffs: artifact write failed.*EROFS/m)
    end

    # The type check in front of the Markdown write is a programming-error
    # guard, not a disk condition, so it must keep its own class.
    it "still raises ArgumentError for a non-String body" do
      bill = GenerateDiffsServiceSpecHelpers.make_bill(
        sway_locale: sway_locale, legislator: legislator, external_id: "DISK-ARG"
      )

      expect { described_class.write_markdown(bill, {a: 1}) }
        .to raise_error(ArgumentError, /must be a String/)
    end

    it "writes the JSON via a same-directory temp file renamed into place" do
      bill = GenerateDiffsServiceSpecHelpers.make_bill(
        sway_locale: sway_locale, legislator: legislator, external_id: "DISK-JSON-RENAME"
      )
      final_path = Legislation::Paths.diff_json_file(bill.external_id, sway_locale: bill.sway_locale&.name)
      seen_tmp_path = nil #: Pathname?
      expect(File).to receive(:rename).and_wrap_original do |original, from, to|
        tmp_path = Pathname(from)
        seen_tmp_path = tmp_path
        expect(to.to_s).to eq(final_path.to_s)
        expect(tmp_path.dirname).to eq(final_path.dirname)
        expect(tmp_path).not_to eq(final_path)
        original.call(from, to)
      end

      described_class.write_json(bill, {"a" => 1})

      expect(seen_tmp_path).not_to be_nil
      expect(JSON.parse(final_path.read)).to eq({"a" => 1})
      expect(final_path.dirname.children.map(&:to_s)).to eq([final_path.to_s])
    end
  end

  describe "#call orchestration (law-vs-amended-law)" do
    let(:sway_locale) { create(:sway_locale) }
    let(:legislator) { create(:legislator, district: create(:district, sway_locale: sway_locale)) }

    it "happy path — single section, single STRIKE produces JSON + Markdown + correct stats" do
      bill = GenerateDiffsServiceSpecHelpers.make_bill(sway_locale: sway_locale, legislator: legislator, external_id: "TEST-HAPPY")
      law = create(:law_section, sway_locale: sway_locale,
        key: "art_1__sec_5", article: "1", section: "5",
        title: "Quiet Title", body: "A\nB\nC\n")
      ref = BillSectionReference.create!(
        bill: bill, key: "art_1__sec_5", article: "1", section: "5",
        anchor: "§ 1-5", resolution: :exact, ordinal: 0
      )
      BillAmendmentOperation.create!(
        bill: bill, bill_section_reference: ref, target_law_section: law,
        operation: :strike, source: :text_pattern,
        anchor_text: "B\n", replacement_text: nil,
        char_start: 0, char_end: 2, ordinal: 0
      )

      result = described_class.new(bill: bill).call

      expect(result.sections_modified).to eq(1)
      expect(result.sections_not_found).to eq(0)
      expect(result.total_operations).to eq(1)
      expect(result.diff_result_path.basename.to_s).to eq("TEST-HAPPY.json")
      expect(result.diff_markdown_path.basename.to_s).to eq("TEST-HAPPY.md")
      expect(result.diff_result_path.exist?).to be(true)
      expect(result.diff_markdown_path.exist?).to be(true)

      json = JSON.parse(result.diff_result_path.read)
      expect(json.keys.sort).to eq(%w[file_id generated_at sections stats summary target title])
      expect(json["generated_at"]).to end_with("+00:00")
      expect(json["target"]).to eq("charter")
      expect(json["stats"]["sections_modified"]).to eq(1)
      expect(json["stats"]["total_operations"]).to eq(1)
      expect(json["sections"].first["status"]).to eq("modified")

      md = result.diff_markdown_path.read
      expect(md).to include("## 1")
      expect(md).to include("### Section Quiet Title")
      expect(md).to include("```diff")
      expect(md).to include("-B")
    end

    it "section_not_found — unresolved reference renders the Python blockquote" do
      bill = GenerateDiffsServiceSpecHelpers.make_bill(sway_locale: sway_locale, legislator: legislator, external_id: "TEST-NOTFOUND")
      BillSectionReference.create!(
        bill: bill, key: "art_9__sec_99", article: "9", section: "99",
        anchor: "§ 9-99", resolution: :unresolved, ordinal: 0
      )
      # Add a stray bill-level operation so the empty-parse check does not fire.
      BillAmendmentOperation.create!(
        bill: bill, operation: :strike, source: :text_pattern,
        anchor_text: "x", char_start: 0, char_end: 1, ordinal: 0
      )

      result = described_class.new(bill: bill).call
      expect(result.sections_not_found).to eq(1)

      json = JSON.parse(result.diff_result_path.read)
      expect(json["sections"].first["status"]).to eq("section_not_found")

      md = result.diff_markdown_path.read
      expect(md).to include("## Unresolved References")
      expect(md).to include("> **Section not found:**")
    end

    it "referenced_only — section resolved but no ops emits no-amendments blockquote + raw fence" do
      bill = GenerateDiffsServiceSpecHelpers.make_bill(sway_locale: sway_locale, legislator: legislator, external_id: "TEST-REFONLY")
      create(:law_section, sway_locale: sway_locale,
        key: "art_1__sec_5", article: "1", section: "5",
        title: "T", body: "untouched law text")
      BillSectionReference.create!(
        bill: bill, key: "art_1__sec_5", article: "1", section: "5",
        anchor: "§ 1-5", resolution: :exact, ordinal: 0
      )
      # No operations are attached to the section reference, but a bill-level
      # operation exists so the empty-parse check does not fire.
      BillAmendmentOperation.create!(
        bill: bill, operation: :strike, source: :text_pattern,
        anchor_text: "x", char_start: 0, char_end: 1, ordinal: 0
      )

      result = described_class.new(bill: bill).call
      json = JSON.parse(result.diff_result_path.read)
      expect(json["sections"].first["status"]).to eq("referenced_only")

      md = result.diff_markdown_path.read
      expect(md).to include("> Bill references this section but no specific amendments were detected.")
      expect(md).to include("untouched law text")
    end

    it "operation_failed — when every op warns, status is operation_failed and the warning blockquote renders" do
      bill = GenerateDiffsServiceSpecHelpers.make_bill(sway_locale: sway_locale, legislator: legislator, external_id: "TEST-OPFAILED")
      law = create(:law_section, sway_locale: sway_locale,
        key: "art_1__sec_5", article: "1", section: "5",
        title: "T", body: "real law content")
      ref = BillSectionReference.create!(
        bill: bill, key: "art_1__sec_5", article: "1", section: "5",
        anchor: "§ 1-5", resolution: :exact, ordinal: 0
      )
      # A text-pattern REPLACE is stored with anchor_text only and no
      # replacement_text, so apply_operations warns about the missing separator.
      BillAmendmentOperation.create!(
        bill: bill, bill_section_reference: ref, target_law_section: law,
        operation: :replace, source: :text_pattern,
        anchor_text: "striking nothing here matches", replacement_text: nil,
        char_start: 0, char_end: 28, ordinal: 0
      )

      result = described_class.new(bill: bill).call
      json = JSON.parse(result.diff_result_path.read)
      expect(json["sections"].first["status"]).to eq("operation_failed")

      md = result.diff_markdown_path.read
      expect(md).to include("> **Warning:** Some operations could not be applied to this section.")
    end

    # A bill with no references and no operations amends nothing (a
    # resolution, appointment, naming), not a parse failure. This used to
    # raise; it now returns all-zero instead.
    it "returns a zero-result when the bill is non-amending (no section refs, no operations)" do
      bill = GenerateDiffsServiceSpecHelpers.make_bill(sway_locale: sway_locale, legislator: legislator, external_id: "TEST-EMPTY")

      result = described_class.new(bill: bill).call

      expect(result).to be_a(described_class::Result)
      expect(result.sections_modified).to eq(0)
      expect(result.sections_not_found).to eq(0)
      expect(result.total_operations).to eq(0)
      expect(result.diff_result_path).to be_nil
      expect(result.diff_markdown_path).to be_nil
    end

    it "regression — two bills with same law section diff against the SAME LawSection.body (not each other's parsed_sections)" do
      law = create(:law_section, sway_locale: sway_locale,
        key: "art_1__sec_5", article: "1", section: "5",
        title: "T", body: "shared\nlaw\nbody\n")

      bill_a = GenerateDiffsServiceSpecHelpers.make_bill(sway_locale: sway_locale, legislator: legislator, external_id: "TEST-D41-A")
      ref_a = BillSectionReference.create!(
        bill: bill_a, key: "art_1__sec_5", article: "1", section: "5",
        anchor: "§ 1-5", resolution: :exact, ordinal: 0
      )
      BillAmendmentOperation.create!(
        bill: bill_a, bill_section_reference: ref_a, target_law_section: law,
        operation: :strike, source: :text_pattern,
        anchor_text: "law\n", replacement_text: nil,
        char_start: 0, char_end: 4, ordinal: 0
      )

      bill_b = GenerateDiffsServiceSpecHelpers.make_bill(sway_locale: sway_locale, legislator: legislator, external_id: "TEST-D41-B")
      ref_b = BillSectionReference.create!(
        bill: bill_b, key: "art_1__sec_5", article: "1", section: "5",
        anchor: "§ 1-5", resolution: :exact, ordinal: 0
      )
      BillAmendmentOperation.create!(
        bill: bill_b, bill_section_reference: ref_b, target_law_section: law,
        operation: :strike, source: :text_pattern,
        anchor_text: "body\n", replacement_text: nil,
        char_start: 0, char_end: 5, ordinal: 0
      )

      described_class.new(bill: bill_a).call
      described_class.new(bill: bill_b).call

      # Each bill's diff sits under ITS OWN jurisdiction, read separately
      # rather than from one shared directory — two bills must not write over
      # each other.
      json_a = JSON.parse(
        Legislation::Paths.diff_json_file("TEST-D41-A", sway_locale: bill_a.sway_locale.name).read
      )
      json_b = JSON.parse(
        Legislation::Paths.diff_json_file("TEST-D41-B", sway_locale: bill_b.sway_locale.name).read
      )

      # Both bills were compared against the SAME LawSection.body, so each diff
      # block shows that bill's own STRIKE rather than a comparison against the
      # other bill's operations.
      expect(json_a["sections"].first["status"]).to eq("modified")
      expect(json_b["sections"].first["status"]).to eq("modified")
      expect(json_a["stats"]["sections_modified"]).to eq(1)
      expect(json_b["stats"]["sections_modified"]).to eq(1)
    end
  end

  # ArtifactPresence.generate_diffs? reads diff_content in the DB, but this
  # used to write only to disk, reporting bills missing. It now writes the
  # column on disk writes and the no-op path too.
  describe "writes bill_llm_provisioning.diff_content" do
    let(:sway_locale) { create(:sway_locale) }
    let(:legislator) { create(:legislator, district: create(:district, sway_locale: sway_locale)) }

    it "populates diff_content + diff_generated_at after a successful section run" do
      bill = GenerateDiffsServiceSpecHelpers.make_bill(
        sway_locale: sway_locale, legislator: legislator, external_id: "TEST-DBSYNC"
      )
      create(:law_section, sway_locale: sway_locale,
        key: "art_1__sec_5", article: "1", section: "5",
        title: "Quiet Title", body: "A\nB\nC\n")
      ref = BillSectionReference.create!(
        bill: bill, key: "art_1__sec_5", article: "1", section: "5",
        anchor: "§ 1-5", resolution: :exact, ordinal: 0
      )
      BillAmendmentOperation.create!(
        bill: bill, bill_section_reference: ref,
        operation: :strike, source: :text_pattern,
        anchor_text: "B\n", char_start: 0, char_end: 2, ordinal: 0
      )

      expect {
        described_class.new(bill: bill).call
      }.to change { bill.reload.bill_llm_provisioning&.diff_content }.from(nil).to(be_present)

      expect(bill.bill_llm_provisioning.diff_generated_at).to be_within(5.seconds).of(Time.current)
      json = JSON.parse(bill.bill_llm_provisioning.diff_content)
      expect(json["file_id"]).to eq("TEST-DBSYNC")
      expect(json["stats"]["sections_modified"]).to eq(1)
    end

    it "populates diff_content with empty-sections sentinel for non-amending bills" do
      bill = GenerateDiffsServiceSpecHelpers.make_bill(
        sway_locale: sway_locale, legislator: legislator, external_id: "TEST-NOAMEND"
      )
      # No references and no operations, so the amends-nothing early return runs.
      expect(bill.bill_section_references).to be_empty
      expect(bill.bill_amendment_operations).to be_empty

      described_class.new(bill: bill).call

      bill.reload
      expect(bill.bill_llm_provisioning).to be_present
      expect(bill.bill_llm_provisioning.diff_content).to be_present
      json = JSON.parse(bill.bill_llm_provisioning.diff_content)
      expect(json["file_id"]).to eq("TEST-NOAMEND")
      expect(json["sections"]).to eq([])
      expect(json["stats"]["sections_modified"]).to eq(0)
      expect(bill.bill_llm_provisioning.diff_generated_at).to be_within(5.seconds).of(Time.current)
    end

    it "reuses an existing bill_llm_provisioning row (upsert, not duplicate)" do
      bill = GenerateDiffsServiceSpecHelpers.make_bill(
        sway_locale: sway_locale, legislator: legislator, external_id: "TEST-UPSERT"
      )
      original = create(:bill_llm_provisioning, bill: bill, llm_summary: "earlier")
      create(:law_section, sway_locale: sway_locale,
        key: "art_1__sec_5", article: "1", section: "5",
        title: "Quiet Title", body: "A\nB\nC\n")
      ref = BillSectionReference.create!(
        bill: bill, key: "art_1__sec_5", article: "1", section: "5",
        anchor: "§ 1-5", resolution: :exact, ordinal: 0
      )
      BillAmendmentOperation.create!(
        bill: bill, bill_section_reference: ref,
        operation: :strike, source: :text_pattern,
        anchor_text: "B\n", char_start: 0, char_end: 2, ordinal: 0
      )

      described_class.new(bill: bill).call

      bill.reload
      updated = bill.bill_llm_provisioning
      # Safe navigation (&.) everywhere: Steep can't follow a conditional raise
      # across an `it` block, so it still believes the value may be nil.
      expect(updated).not_to be_nil
      expect(updated&.id).to eq(original.id) # same row
      expect(updated&.llm_summary).to eq("earlier") # untouched
      expect(updated&.diff_content).to be_present
    end

    it "makes Pipeline::ArtifactPresence.present?('generate-diffs', bill:) return true (cross-cutting contract)" do
      bill = GenerateDiffsServiceSpecHelpers.make_bill(
        sway_locale: sway_locale, legislator: legislator, external_id: "TEST-PREDCROSS"
      )
      # Bills that amend nothing used to report false forever, since no service
      # wrote the column. The empty placeholder payload now satisfies what the
      # check means: generate-diffs ran to completion.
      expect(Pipeline::ArtifactPresence.present?("generate-diffs", bill: bill)).to be false

      described_class.new(bill: bill).call

      expect(Pipeline::ArtifactPresence.present?("generate-diffs", bill: bill.reload)).to be true
    end
  end

  describe "markup_modified diff rendering" do
    let(:sway_locale) { create(:sway_locale) }
    let(:legislator) { create(:legislator, sway_locale: sway_locale) }

    it "renders diff block for markup ops even when law_section is nil" do
      bill = GenerateDiffsServiceSpecHelpers.make_bill(sway_locale: sway_locale, legislator: legislator, external_id: "TEST-MARKUP")
      bill.update!(extracted_text: <<~TXT)
        EXPLANATION: CAPITALS indicate matter added to existing law.
        [Brackets] indicate matter deleted from existing law.

        Section § 1-5. An offender must register with [Commissioner of Police.] POLICE COMMISSIONER OF BALTIMORE CITY.
      TXT
      ref = BillSectionReference.create!(
        bill: bill, key: "art_1__sec_5", article: "1", section: "5",
        anchor: "§ 1-5", resolution: :unresolved, ordinal: 0
      )
      BillAmendmentOperation.create!(
        bill: bill, bill_section_reference: ref,
        operation: :strike, source: :markup,
        anchor_text: "Commissioner of Police.", char_start: 180, char_end: 205, ordinal: 0
      )
      BillAmendmentOperation.create!(
        bill: bill, bill_section_reference: ref,
        operation: :insert, source: :markup,
        replacement_text: "POLICE COMMISSIONER OF BALTIMORE CITY", char_start: 206, char_end: 243, ordinal: 1
      )

      result = described_class.new(bill: bill).call

      expect(result.sections_modified).to eq(1)
      expect(result.sections_not_found).to eq(0)
      expect(result.total_operations).to eq(2)

      json = JSON.parse(result.diff_result_path.read)
      sec = json["sections"].first
      expect(sec["status"]).to eq("markup_modified")
      expect(sec["operations_applied"]).to eq(2)
      expect(sec).not_to have_key("_diff_block")

      md = result.diff_markdown_path.read
      expect(md).to include("```diff")
      expect(md).to include("-")
      expect(md).to include("+")
    end
  end

  describe "unattributed markup amendments group" do
    let(:sway_locale) { create(:sway_locale) }
    let(:legislator) { create(:legislator, sway_locale: sway_locale) }

    it "renders unattributed amendments diff and does not double count total_operations" do
      bill = GenerateDiffsServiceSpecHelpers.make_bill(sway_locale: sway_locale, legislator: legislator, external_id: "TEST-UNATTRIB")
      bill.update!(extracted_text: <<~TXT)
        EXPLANATION: CAPITALS indicate matter added to existing law.
        [Brackets] indicate matter deleted from existing law.

        Preamble: [Old text removed.] NEW TEXT ADDED HERE.
      TXT
      BillAmendmentOperation.create!(
        bill: bill, bill_section_reference_id: nil,
        operation: :strike, source: :markup,
        anchor_text: "Old text removed.", char_start: 140, char_end: 159, ordinal: 0
      )

      result = described_class.new(bill: bill).call

      expect(result.sections_modified).to eq(1)
      expect(result.total_operations).to eq(1)

      md = result.diff_markdown_path.read
      expect(md).to include("## Unattributed Amendments")
    end
  end
end
