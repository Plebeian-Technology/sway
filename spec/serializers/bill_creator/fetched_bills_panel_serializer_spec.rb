# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# @lat: [[bill-creator-artifact-panel-serializers#FetchedBillsPanelSerializer]]
RSpec.describe BillCreator::FetchedBillsPanelSerializer do
  let(:sway_locale) { create(:sway_locale) }

  # Point the root folder at a throwaway temp directory through the
  # legislation setting — the same trick BillCreator::ResourceCachePanelSerializer
  # and GenerateDiffsService::ResultWriter use — so tests never write real files.
  around do |example|
    Dir.mktmpdir do |tmp|
      with_app_config(:legislation, legislation_bills_raw_root: tmp) { example.run }
    end
  end

  # @lat: [[fetched-bills-panel#Why the row carries no attachment count]]
  def seed_bill_dir(external_id, pdf: true, metadata: true, mtime: nil, owner: sway_locale)
    dir = Legislation::Paths.bill_artifact_dir(external_id, sway_locale: owner.name)
    FileUtils.mkdir_p(dir)
    File.write(dir.join("bill.pdf"), "%PDF-1.4 fake") if pdf
    File.write(dir.join("metadata.json"), '{"external_id":"' + external_id + '"}') if metadata
    if mtime
      # Give every file in the tree the requested modification time. The
      # serializer works out fetched_at from the newest modification time
      # across the files it knows about.
      Dir.glob(dir.join("**/*")).each { |p| File.utime(mtime, mtime, p) }
    end
    dir
  end

  describe ".call" do
    context "with an empty bills_raw_root" do
      it "returns an empty array" do
        expect(described_class.call(sway_locale)).to eq([])
      end
    end

    context "when nil is passed for sway_locale" do
      it "returns an empty array" do
        expect(described_class.call(nil)).to eq([])
      end
    end

    context "with a single fetched bill that has a matching Bill row" do
      it "returns one row tying the on-disk dir to the Bill record" do
        bill = create(:bill,
          external_id: "25-0001",
          sway_locale: sway_locale,
          title: "An act about budgets")
        seed_bill_dir("25-0001", mtime: Time.utc(2026, 5, 1, 12, 0, 0))

        rows = described_class.call(sway_locale)

        expect(rows.length).to eq(1)
        row = rows.first
        expect(row[:external_id]).to eq("25-0001")
        expect(row[:bill_id]).to eq(bill.id)
        expect(row[:title]).to eq("An act about budgets")
        expect(row[:pdf_present]).to be true
        expect(row[:metadata_present]).to be true
        expect(row[:bill_row_exists]).to be true
        expect(row[:fetched_at]).to be_within(1.second).of(Time.utc(2026, 5, 1, 12, 0, 0))
      end
    end

    context "the row's key set" do
      # @lat: [[fetched-bills-panel#Why the row carries no attachment count]]
      it "carries exactly the keys FetchedBillRow reads" do
        seed_bill_dir("keys-001")

        expect(described_class.call(sway_locale).first.keys).to contain_exactly(
          :external_id,
          :bill_id,
          :title,
          :fetched_at,
          :pdf_present,
          :metadata_present,
          :bill_row_exists
        )
      end
    end

    context "when a dir has no matching Bill row in this locale (orphan on disk)" do
      it "returns the row with bill_id=nil and bill_row_exists=false" do
        seed_bill_dir("orphaned-on-disk-001", mtime: Time.utc(2026, 5, 2, 9, 0, 0))

        rows = described_class.call(sway_locale)

        expect(rows.length).to eq(1)
        row = rows.first
        expect(row[:external_id]).to eq("orphaned-on-disk-001")
        expect(row[:bill_id]).to be_nil
        expect(row[:title]).to be_nil
        expect(row[:bill_row_exists]).to be false
        expect(row[:pdf_present]).to be true
      end
    end

    context "when pdf or metadata is missing" do
      it "reflects the missing presence flags" do
        seed_bill_dir("partial-001", pdf: false, mtime: Time.utc(2026, 5, 3, 0, 0, 0))
        seed_bill_dir("partial-002", metadata: false, mtime: Time.utc(2026, 5, 3, 0, 0, 0))

        rows = described_class.call(sway_locale).index_by { |r| r[:external_id] }

        expect(rows["partial-001"][:pdf_present]).to be false
        expect(rows["partial-001"][:metadata_present]).to be true
        expect(rows["partial-002"][:pdf_present]).to be true
        expect(rows["partial-002"][:metadata_present]).to be false
      end
    end

    context "with multiple fetched bills" do
      it "returns rows sorted newest fetched_at first" do
        seed_bill_dir("oldest-001", mtime: Time.utc(2026, 1, 1, 0, 0, 0))
        seed_bill_dir("middle-001", mtime: Time.utc(2026, 3, 1, 0, 0, 0))
        seed_bill_dir("newest-001", mtime: Time.utc(2026, 5, 1, 0, 0, 0))

        external_ids = described_class.call(sway_locale).pluck(:external_id)
        expect(external_ids).to eq(%w[newest-001 middle-001 oldest-001])
      end
    end

    context "fetched_at uses the newest mtime across files in the dir" do
      it "picks the latest of the files it knows about" do
        # Create the bill's files, then push one file's modification time
        # forward. fetched_at should follow that newest time, not the oldest.
        dir = seed_bill_dir("bumped-001", mtime: Time.utc(2026, 4, 1, 0, 0, 0))
        bumped = Time.utc(2026, 5, 15, 0, 0, 0)
        File.utime(bumped, bumped, dir.join("metadata.json"))

        row = described_class.call(sway_locale).first
        expect(row[:fetched_at]).to be_within(1.second).of(bumped)
      end
    end

    context "with bills from a different sway_locale (locale isolation)" do
      it "still returns on-disk dirs, but matches Bill rows only from the queried locale" do
        # Another locale has a bill with the same external_id. The serializer
        # must not link the on-disk directory to it.
        other_locale = create(:sway_locale, city: "Othertown", state: "maryland", country: "united_states")
        other_bill = create(:bill,
          external_id: "shared-id-001",
          sway_locale: other_locale,
          title: "Other locale bill")
        seed_bill_dir("shared-id-001", mtime: Time.utc(2026, 5, 5, 0, 0, 0))

        row = described_class.call(sway_locale).first
        expect(row[:external_id]).to eq("shared-id-001")
        expect(row[:bill_id]).to be_nil,
          "must not cross-link Bill ##{other_bill.id} from a different locale"
        expect(row[:bill_row_exists]).to be false
      end
    end

    # @lat: [[fetched-bills-panel#Why it is scoped to one locale]]
    context "with files under a different sway_locale's subtree" do
      it "lists none of them" do
        other_locale = create(:sway_locale, city: "Othertown", state: "maryland", country: "united_states")
        seed_bill_dir("only-in-othertown-001", owner: other_locale)

        expect(described_class.call(sway_locale)).to eq([])
      end

      it "lists this sway_locale's own files and no others" do
        other_locale = create(:sway_locale, city: "Othertown", state: "maryland", country: "united_states")
        seed_bill_dir("ours-001")
        seed_bill_dir("theirs-001", owner: other_locale)

        expect(described_class.call(sway_locale).pluck(:external_id)).to eq(%w[ours-001])
      end
    end
  end
end
