# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# @lat: [[bill-creator-artifact-panel-serializers#ResourceCachePanelSerializer]]
RSpec.describe BillCreator::ResourceCachePanelSerializer do
  let(:bill) { create(:bill, external_id: "test-bill-001") }

  # @lat: [[bill-creator-artifact-panel-serializers#ResourceCachePanelSerializer]]
  around do |example|
    Dir.mktmpdir do |tmp|
      with_app_config(:legislation, legislation_bills_raw_root: tmp) { example.run }
    end
  end

  describe ".call" do
    context "when the bill has no pipeline run history, no LLM summary, and no PDF on disk" do
      it "returns an empty array" do
        expect(described_class.call(bill)).to eq([])
      end
    end

    context "when nil is passed" do
      it "returns an empty array" do
        expect(described_class.call(nil)).to eq([])
      end
    end

    context "with a PipelineRunBill that has stage_results for bill-level tiers" do
      let!(:run) { create(:legislation_pipeline_run) }
      let!(:run_bill) do
        create(:pipeline_run_bill,
          legislation_pipeline_run: run,
          bill_external_id: bill.external_id,
          stage_results: {
            # @lat: [[bill-creator-artifact-panel-serializers#ResourceCachePanelSerializer]]
            "extract_text" => {"status" => "succeeded", "at" => "2026-05-13T12:01:00Z"},
            "parse_sections" => {"status" => "succeeded", "at" => "2026-05-13T12:02:00Z"},
            "generate_diffs" => {"status" => "succeeded", "at" => "2026-05-13T12:03:00Z"}
          })
      end

      it "emits one row per succeeded bill-level stage (pdf only when on disk)" do
        rows = described_class.call(bill)
        tiers = rows.pluck(:tier)
        expect(tiers).to match_array(%w[extracted_text parsed_sections diff])
      end

      it "sources last_generated_at from each stage's own \"at\" timestamp" do
        rows = described_class.call(bill)
        by_tier = rows.index_by { |r| r[:tier] }
        expect(by_tier["extracted_text"][:last_generated_at]).to be_within(1.second).of(Time.zone.parse("2026-05-13T12:01:00Z"))
        expect(by_tier["parsed_sections"][:last_generated_at]).to be_within(1.second).of(Time.zone.parse("2026-05-13T12:02:00Z"))
        expect(by_tier["diff"][:last_generated_at]).to be_within(1.second).of(Time.zone.parse("2026-05-13T12:03:00Z"))
      end

      it "carries the locked BillArtifactMirror#to_builder_hash key set on every row" do
        rows = described_class.call(bill)
        expect(rows).to be_present
        rows.each do |row|
          expect(row.keys).to match_array(%i[tier last_generated_at version_id stale source_artifact_id])
        end
      end

      it "marks each row as not stale (the Ruby pipeline does not track staleness)" do
        rows = described_class.call(bill)
        expect(rows.pluck(:stale).uniq).to eq([false])
      end

      it "leaves version_id and source_artifact_id nil (no sidecar-era identities)" do
        rows = described_class.call(bill)
        expect(rows.pluck(:version_id).uniq).to eq([nil])
        expect(rows.pluck(:source_artifact_id).uniq).to eq([nil])
      end

      it "skips stages whose stage_results status is not 'succeeded'" do
        run_bill.update!(stage_results: {
          "extract_text" => {"status" => "failed", "at" => "2026-05-13T12:01:00Z"},
          "parse_sections" => {"status" => "running", "at" => nil}
        })

        rows = described_class.call(bill)
        expect(rows).to eq([])
      end
    end

    # The pdf row comes from the PDF file's modification time, not from
    # stage_results: fetch_bills is a whole-run stage and writes nothing into a
    # PipelineRunBill's stage_results.
    context "with a PDF on disk under legislation/bills/raw/<external_id>/" do
      let(:pdf_mtime) { Time.utc(2026, 5, 13, 11, 30, 0) }
      let(:pdf_path) do
        dir = Pathname.new(Sway::Settings.legislation.legislation_bills_raw_root.to_s)
          .join(bill.sway_locale.name, bill.external_id)
        dir.mkpath
        path = dir.join("bill.pdf")
        path.write("%PDF-1.4 test")
        File.utime(pdf_mtime.to_i, pdf_mtime.to_i, path.to_s)
        path
      end

      before { pdf_path }

      it "emits a pdf row sourced from File.mtime" do
        rows = described_class.call(bill)
        pdf_row = rows.find { |r| r[:tier] == "pdf" }

        expect(pdf_row).to be_present
        expect(pdf_row[:last_generated_at]).to be_within(1.second).of(pdf_mtime)
        expect(pdf_row[:stale]).to be(false)
        expect(pdf_row[:version_id]).to be_nil
        expect(pdf_row[:source_artifact_id]).to be_nil
      end
    end

    context "without a PDF on disk" do
      it "omits the pdf row" do
        rows = described_class.call(bill)
        expect(rows.pluck(:tier)).not_to include("pdf")
      end
    end

    context "with a BillLlmProvisioning that has llm_generated_at" do
      let!(:provisioning) do
        bill.create_bill_llm_provisioning!(
          llm_summary: "Test summary",
          llm_generated_at: Time.utc(2026, 5, 13, 13, 0, 0)
        )
      end

      it "emits a summary row sourced from BillLlmProvisioning.llm_generated_at" do
        rows = described_class.call(bill)
        summary_row = rows.find { |r| r[:tier] == "summary" }

        expect(summary_row).to be_present
        expect(summary_row[:last_generated_at]).to be_within(1.second).of(Time.utc(2026, 5, 13, 13, 0, 0))
        expect(summary_row[:stale]).to be(false)
        expect(summary_row[:version_id]).to be_nil
        expect(summary_row[:source_artifact_id]).to be_nil
      end
    end

    context "with both pipeline runs AND an LLM summary" do
      let!(:run) { create(:legislation_pipeline_run) }
      let!(:run_bill) do
        create(:pipeline_run_bill,
          legislation_pipeline_run: run,
          bill_external_id: bill.external_id,
          stage_results: {
            "extract_text" => {"status" => "succeeded", "at" => "2026-05-13T12:01:00Z"},
            "parse_sections" => {"status" => "succeeded", "at" => "2026-05-13T12:02:00Z"}
          })
      end
      let!(:provisioning) do
        bill.create_bill_llm_provisioning!(
          llm_summary: "Test summary",
          llm_generated_at: Time.utc(2026, 5, 13, 13, 0, 0)
        )
      end

      it "emits the union of pipeline tiers AND the summary tier" do
        rows = described_class.call(bill)
        tiers = rows.pluck(:tier)
        expect(tiers).to match_array(%w[extracted_text parsed_sections summary])
      end
    end

    context "with multiple pipeline runs for the same bill" do
      let!(:older_run) { create(:legislation_pipeline_run, created_at: 1.day.ago) }
      let!(:older_run_bill) do
        create(:pipeline_run_bill,
          legislation_pipeline_run: older_run,
          bill_external_id: bill.external_id,
          stage_results: {
            "extract_text" => {"status" => "succeeded", "at" => "2026-05-12T12:00:00Z"}
          })
      end
      let!(:newer_run) { create(:legislation_pipeline_run, created_at: 1.hour.ago) }
      let!(:newer_run_bill) do
        create(:pipeline_run_bill,
          legislation_pipeline_run: newer_run,
          bill_external_id: bill.external_id,
          stage_results: {
            "parse_sections" => {"status" => "succeeded", "at" => "2026-05-13T11:00:00Z"}
          })
      end

      it "sources from the most recent run only" do
        rows = described_class.call(bill)
        tiers = rows.pluck(:tier)
        expect(tiers).to eq(%w[parsed_sections])
      end
    end
  end
end
