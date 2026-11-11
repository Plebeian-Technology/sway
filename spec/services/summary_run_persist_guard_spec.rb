# frozen_string_literal: true

require "rails_helper"

# @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
RSpec.describe SummaryRunPersistGuard do
  let(:bill) { create(:bill, summary: Bill::SUMMARY_PLACEHOLDER) }
  let!(:provisioning) { create(:bill_llm_provisioning, :generating, bill: bill) }

  let(:summary_attrs) do
    {
      llm_provider: "claude",
      llm_model: "claude-test",
      llm_summary: "What changed: a new reporting requirement.",
      llm_full_breakdown: "## Section 1\nAdds a reporting requirement.",
      summary_run_id: "some-job-id",
      llm_generated_at: Time.current
    }
  end

  describe ".call — the ordinary write" do
    it "returns :persisted" do
      expect(described_class.call(bill, provisioning, summary_attrs)).to eq(:persisted)
    end

    it "writes attrs onto the row" do
      described_class.call(bill, provisioning, summary_attrs)

      expect(provisioning.reload.llm_summary).to eq(summary_attrs[:llm_summary])
    end

    it "publishes the summary onto the bill's public page" do
      described_class.call(bill, provisioning, summary_attrs)

      expect(bill.reload.summary).to eq(summary_attrs[:llm_summary])
    end

    it "declines to publish over a summary a person wrote, leaving the draft on the row anyway" do
      bill.update!(summary: "An admin wrote this by hand.")

      described_class.call(bill, provisioning, summary_attrs)

      expect(bill.reload.summary).to eq("An admin wrote this by hand.")
      expect(provisioning.reload.llm_summary).to eq(summary_attrs[:llm_summary])
    end

    it "does not touch the bill's summary when attrs carries no :llm_summary" do
      bill.update!(summary: "An admin wrote this by hand.")

      described_class.call(bill, provisioning, {draft_org_positions: [], summary_run_id: "some-job-id"})

      expect(bill.reload.summary).to eq("An admin wrote this by hand.")
    end
  end

  describe ".call — an operator's paste already owns the row" do
    before { provisioning.update_columns(summary_run_id: SummaryRunMarker.operator_paste) }

    it "returns :superseded" do
      expect(described_class.call(bill, provisioning, summary_attrs)).to eq(:superseded)
    end

    it "writes none of attrs onto the row" do
      described_class.call(bill, provisioning, summary_attrs)

      expect(provisioning.reload.llm_summary).to be_blank
    end

    it "leaves the operator-paste marker on the row rather than stamping over it" do
      described_class.call(bill, provisioning, summary_attrs)

      expect(SummaryRunMarker.operator_paste?(provisioning.reload.summary_run_id)).to be(true)
    end

    it "does not settle the row — a :superseded verdict is left for the caller to react to" do
      described_class.call(bill, provisioning, summary_attrs)

      expect(provisioning.reload.generation_status).to eq("generating")
    end
  end

  describe ".call — the testimony behind a positions write moved (evidence_digest)" do
    let!(:provisioning) do
      create(:bill_llm_provisioning, :generating, :with_testimony, bill: bill)
    end
    let(:positions_attrs) do
      {
        draft_org_positions: [{"org_name" => "ACLU", "stance" => "support", "summary" => "x"}],
        summary_run_id: "some-job-id",
        generation_error: nil
      }
    end

    it "returns :evidence_withdrawn when the committed testimony digest no longer matches" do
      outcome = described_class.call(
        bill, provisioning, positions_attrs, evidence_digest: "a-stale-digest-that-does-not-match"
      )

      expect(outcome).to eq(:evidence_withdrawn)
    end

    it "writes nothing onto the row" do
      described_class.call(
        bill, provisioning, positions_attrs, evidence_digest: "a-stale-digest-that-does-not-match"
      )

      expect(provisioning.reload.draft_org_positions).to be_blank
    end

    it "persists when the digest matches the row's committed testimony" do
      outcome = described_class.call(
        bill, provisioning, positions_attrs, evidence_digest: provisioning.testimony_digest
      )

      expect(outcome).to eq(:persisted)
      expect(provisioning.reload.draft_org_positions).to be_present
    end
  end

  describe ".call — the row is deleted while the write is in flight" do
    it "returns :vanished rather than raising or claiming a write that never happened" do
      allow_any_instance_of(BillLlmProvisioning).to receive(:lock!) # rubocop:disable RSpec/AnyInstance
        .and_raise(ActiveRecord::RecordNotFound.new("Couldn't find BillLlmProvisioning"))
      allow(SwayLogging).to receive(:warn)

      expect(described_class.call(bill, provisioning, summary_attrs)).to eq(:vanished)
    end

    it "writes nothing, because there is no row left to write onto" do
      allow_any_instance_of(BillLlmProvisioning).to receive(:lock!) # rubocop:disable RSpec/AnyInstance
        .and_raise(ActiveRecord::RecordNotFound.new("Couldn't find BillLlmProvisioning"))
      allow(SwayLogging).to receive(:warn)

      described_class.call(bill, provisioning, summary_attrs)

      expect(bill.reload.summary).to eq(Bill::SUMMARY_PLACEHOLDER)
    end
  end

  describe "callable directly, standing in for a batch ingest arriving hours later" do
    it "persists a result with no GenerateBillSummaryJob instance and no enqueue-staleness check in the way" do
      outcome = described_class.call(bill, provisioning, summary_attrs)

      expect(outcome).to eq(:persisted)
      expect(provisioning.reload.llm_summary).to eq(summary_attrs[:llm_summary])
    end
  end

  describe "summary revision tracking" do
    it "records an accepted model generation as a published revision when published" do
      expect {
        described_class.call(bill, provisioning, summary_attrs)
      }.to change { bill.bill_summary_revisions.count }.by(1)

      revision = bill.bill_summary_revisions.last
      expect(revision.origin).to eq("model_generation")
      expect(revision.publication_role).to eq("published")
      expect(revision.review_state).to eq("unreviewed")
      expect(revision.summary_markdown).to eq(summary_attrs[:llm_summary])
      expect(revision.llm_provider).to eq("claude")
      expect(revision.llm_model).to eq("claude-test")
    end

    it "records an accepted generation as a draft revision when public summary is operator-owned" do
      bill.update!(summary: "Operator curated summary")

      described_class.call(bill, provisioning, summary_attrs)

      revisions = bill.bill_summary_revisions.order(:id)
      # 1 baseline (Operator curated summary) + 1 draft generation
      expect(revisions.count).to eq(2)

      baseline = revisions.first
      expect(baseline.origin).to eq("initial_baseline")
      expect(baseline.summary_markdown).to eq("Operator curated summary")
      expect(baseline.publication_role).to eq("published")

      draft_rev = revisions.last
      expect(draft_rev.origin).to eq("model_generation")
      expect(draft_rev.publication_role).to eq("draft")
      expect(draft_rev.review_state).to eq("unreviewed")
      expect(draft_rev.summary_markdown).to eq(summary_attrs[:llm_summary])
    end

    it "preserves multiple successive generations with their respective models" do
      described_class.call(bill, provisioning, summary_attrs.merge(llm_model: "model-1", llm_summary: "First generation"))
      described_class.call(bill, provisioning, summary_attrs.merge(llm_model: "model-2", llm_summary: "Second generation"))

      revisions = bill.bill_summary_revisions.where(origin: "model_generation").order(:id)
      expect(revisions.count).to eq(2)
      expect(revisions.first.llm_model).to eq("model-1")
      expect(revisions.first.summary_markdown).to eq("First generation")
      expect(revisions.last.llm_model).to eq("model-2")
      expect(revisions.last.summary_markdown).to eq("Second generation")
    end

    it "does not record revisions when superseded by an operator paste" do
      provisioning.update_columns(summary_run_id: SummaryRunMarker.operator_paste)

      expect {
        described_class.call(bill, provisioning, summary_attrs)
      }.not_to change { bill.bill_summary_revisions.count }
    end

    it "prevents late generation from replacing a restored summary" do
      bill.update!(summary: "Summary B")
      provisioning.update!(llm_summary: "Summary B")

      stale_bill = Bill.find(bill.id)

      historical_rev_a = BillSummaryRevision.record_revision!(
        bill: bill,
        summary_markdown: "Summary A",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed"
      )
      bill.restore_summary_revision!(historical_rev_a, news_usage: "none")
      expect(bill.reload.summary).to eq("Summary A")

      described_class.call(stale_bill, provisioning, summary_attrs.merge(llm_summary: "Generated C"))

      expect(bill.reload.summary).to eq("Summary A")
      expect(provisioning.reload.llm_summary).to eq("Generated C")

      c_rev = bill.bill_summary_revisions.order(:id).last
      expect(c_rev.summary_markdown).to eq("Generated C")
      expect(c_rev.publication_role).to eq("draft")
    end

    it "captures a legacy generated draft before its first replacement" do
      bill.update!(summary: "Human public text A")
      gen_time = 2.days.ago.change(usec: 0)
      provisioning.update!(
        llm_summary: "Legacy model draft B",
        llm_provider: "claude",
        llm_model: "claude-3-5-sonnet",
        llm_generated_at: gen_time
      )
      expect(bill.bill_summary_revisions.count).to eq(0)

      described_class.call(bill, provisioning, summary_attrs.merge(llm_summary: "Generated C"))

      revisions = bill.bill_summary_revisions.order(:id)
      expect(revisions.count).to eq(3)

      expect(revisions.first.summary_markdown).to eq("Human public text A")
      expect(revisions.first.origin).to eq("initial_baseline")
      expect(revisions.first.publication_role).to eq("published")

      expect(revisions.second.summary_markdown).to eq("Legacy model draft B")
      expect(revisions.second.origin).to eq("model_generation")
      expect(revisions.second.publication_role).to eq("draft")
      expect(revisions.second.llm_model).to eq("claude-3-5-sonnet")

      expect(revisions.third.summary_markdown).to eq("Generated C")
      expect(revisions.third.origin).to eq("model_generation")
      expect(revisions.third.publication_role).to eq("draft")
    end

    it "declines publication when stale bill instance has preloaded association cache" do
      bill.update!(summary: "Preloaded old summary")
      stale_bill = Bill.find(bill.id)
      expect(stale_bill.bill_summary_revisions.to_a).to be_empty
      expect(stale_bill.bill_summary_revisions.loaded?).to be(true)

      rev = BillSummaryRevision.record_revision!(
        bill: bill,
        summary_markdown: "Restored from concurrent session",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed"
      )
      bill.restore_summary_revision!(rev, actor: create(:user, :sway_admin), news_usage: "none")
      expect(bill.reload.summary).to eq("Restored from concurrent session")

      described_class.call(stale_bill, provisioning, summary_attrs.merge(llm_summary: "Generated C"))

      expect(bill.reload.summary).to eq("Restored from concurrent session")
    end

    it "survives concurrent restorations and persist guard executions without clobbering" do
      admin = create(:user, :sway_admin)
      bill.update!(summary: "Initial base text")
      rev_target = BillSummaryRevision.record_revision!(
        bill: bill,
        summary_markdown: "Restored golden text",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed"
      )

      errors = []
      threads = []

      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          b = Bill.find(bill.id)
          b.restore_summary_revision!(rev_target, actor: admin, news_usage: "none") if rev_target
        rescue => e
          errors << e
        end
      end

      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          b = Bill.find(bill.id)
          p = b.bill_llm_provisioning
          if p
            described_class.call(b, p, {
              llm_summary: "Late generated draft",
              llm_provider: "claude",
              llm_model: "claude-3-5-sonnet",
              summary_run_id: "thread-run"
            })
          end
        rescue => e
          errors << e
        end
      end

      threads.each(&:join)

      expect(errors).to be_empty
      expect(bill.reload.summary).to eq("Restored golden text")
    end
  end
end
