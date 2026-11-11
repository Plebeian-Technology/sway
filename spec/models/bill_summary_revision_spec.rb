# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: bill_summary_revisions
# Database name: primary
#
#  id                      :integer          not null, primary key
#  llm_model               :string
#  llm_provider            :string
#  origin                  :string           not null
#  publication_role        :string           not null
#  review_state            :string           not null
#  summary_markdown        :text             not null
#  created_at              :datetime         not null
#  actor_id                :integer
#  bill_id                 :integer          not null
#  news_source_snapshot_id :integer
#  restored_from_id        :integer
#
# Indexes
#
#  index_bill_summary_revisions_on_actor_id                 (actor_id)
#  index_bill_summary_revisions_on_bill_id                  (bill_id)
#  index_bill_summary_revisions_on_bill_id_and_created_at   (bill_id,created_at)
#  index_bill_summary_revisions_on_news_source_snapshot_id  (news_source_snapshot_id)
#  index_bill_summary_revisions_on_restored_from_id         (restored_from_id)
#
# Foreign Keys
#
#  actor_id                 (actor_id => users.id)
#  bill_id                  (bill_id => bills.id)
#  news_source_snapshot_id  (news_source_snapshot_id => news_article_source_snapshots.id) ON DELETE => nullify
#  restored_from_id         (restored_from_id => bill_summary_revisions.id)
#
RSpec.describe BillSummaryRevision, type: :model do
  include_context "Setup"

  let(:sway_locale) { create(:sway_locale) }
  let(:bill) { create(:bill, sway_locale: sway_locale, summary: "Initial bill summary on file") }
  let(:user) { create(:user) }

  describe "validations" do
    it "is valid with required attributes" do
      revision = described_class.new(
        bill: bill,
        summary_markdown: "Summary text",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed"
      )
      expect(revision).to be_valid
    end

    it "requires summary_markdown" do
      revision = described_class.new(
        bill: bill,
        summary_markdown: nil,
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed"
      )
      expect(revision).not_to be_valid
      expect(revision.errors[:summary_markdown]).to be_present
    end

    it "validates origin inclusion" do
      expect {
        described_class.create!(
          bill: bill,
          summary_markdown: "Text",
          origin: "invalid_origin",
          publication_role: "published",
          review_state: "reviewed"
        )
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "validates publication_role inclusion" do
      expect {
        described_class.create!(
          bill: bill,
          summary_markdown: "Text",
          origin: "operator_edit",
          publication_role: "invalid_role",
          review_state: "reviewed"
        )
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "validates review_state inclusion" do
      expect {
        described_class.create!(
          bill: bill,
          summary_markdown: "Text",
          origin: "operator_edit",
          publication_role: "published",
          review_state: "invalid_state"
        )
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "refuses restored_from referencing a revision on a different bill" do
      other_bill = create(:bill, sway_locale: sway_locale, scheduled_release_date_utc: 2.weeks.from_now)
      other_revision = described_class.create!(
        bill: other_bill,
        summary_markdown: "Other summary",
        origin: "model_generation",
        publication_role: "published",
        review_state: "unreviewed"
      )

      revision = described_class.new(
        bill: bill,
        summary_markdown: "Restored text",
        origin: "restoration",
        publication_role: "published",
        review_state: "unreviewed",
        restored_from: other_revision
      )

      expect(revision).not_to be_valid
      expect(revision.errors[:restored_from]).to include("must belong to the same bill")
    end
  end

  describe "immutability" do
    let!(:revision) do
      described_class.create!(
        bill: bill,
        summary_markdown: "Original text",
        origin: "model_generation",
        publication_role: "published",
        review_state: "unreviewed"
      )
    end

    it "marks persisted records as readonly" do
      expect(revision).to be_readonly
    end

    it "raises ActiveRecord::ReadOnlyRecord on update attempt" do
      expect {
        revision.update(summary_markdown: "Tampered text")
      }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises ActiveRecord::ReadOnlyRecord on update! attempt" do
      expect {
        revision.update!(summary_markdown: "Tampered text")
      }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises ActiveRecord::ReadOnlyRecord on destroy attempt" do
      expect {
        revision.destroy
      }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe "baseline preservation" do
    it "captures the existing bill summary as initial_baseline before recording the first revision" do
      expect(bill.bill_summary_revisions.count).to eq(0)
      expect(bill.summary).to eq("Initial bill summary on file")

      new_rev = described_class.record_revision!(
        bill: bill,
        summary_markdown: "Brand new summary",
        origin: "operator_edit",
        actor: user,
        publication_role: "published",
        review_state: "reviewed"
      )

      revisions = bill.bill_summary_revisions.order(:id)
      expect(revisions.count).to eq(2)

      baseline = revisions.first
      expect(baseline.origin).to eq("initial_baseline")
      expect(baseline.summary_markdown).to eq("Initial bill summary on file")
      expect(baseline.publication_role).to eq("published")
      expect(baseline.review_state).to eq("unknown")
      expect(baseline.actor).to be_nil

      expect(revisions.last).to eq(new_rev)
      expect(new_rev.origin).to eq("operator_edit")
      expect(new_rev.summary_markdown).to eq("Brand new summary")
      expect(new_rev.actor).to eq(user)
    end

    it "does not capture baseline if bill summary is empty or placeholder" do
      empty_bill = create(:bill, sway_locale: sway_locale, summary: Bill::SUMMARY_PLACEHOLDER)
      rev = described_class.record_revision!(
        bill: empty_bill,
        summary_markdown: "First real summary",
        origin: "model_generation",
        publication_role: "published",
        review_state: "unreviewed"
      )

      expect(empty_bill.bill_summary_revisions.count).to eq(1)
      expect(empty_bill.bill_summary_revisions.first).to eq(rev)
    end

    it "captures distinct published baseline and legacy draft baseline with model provenance" do
      bill.update!(summary: "Human public text A")
      gen_time = 2.days.ago.change(usec: 0)
      prov = create(:bill_llm_provisioning,
        bill: bill,
        llm_summary: "Legacy model draft B",
        llm_provider: "claude",
        llm_model: "claude-3-5-sonnet",
        llm_generated_at: gen_time)

      described_class.ensure_baseline!(bill, provisioning: prov)

      revisions = bill.bill_summary_revisions.order(:id)
      expect(revisions.count).to eq(2)

      pub_baseline = revisions.first
      expect(pub_baseline.origin).to eq("initial_baseline")
      expect(pub_baseline.summary_markdown).to eq("Human public text A")
      expect(pub_baseline.publication_role).to eq("published")
      expect(pub_baseline.review_state).to eq("unknown")

      draft_baseline = revisions.second
      expect(draft_baseline.origin).to eq("model_generation")
      expect(draft_baseline.summary_markdown).to eq("Legacy model draft B")
      expect(draft_baseline.publication_role).to eq("draft")
      expect(draft_baseline.review_state).to eq("unreviewed")
      expect(draft_baseline.llm_provider).to eq("claude")
      expect(draft_baseline.llm_model).to eq("claude-3-5-sonnet")
    end

    it "captures legacy paste draft with operator_paste origin and unknown review_state" do
      bill.update!(summary: "Human public text A")
      prov = create(:bill_llm_provisioning,
        bill: bill,
        llm_summary: "Legacy pasted draft B",
        llm_provider: BillLlmProvisioning::OPERATOR_PASTE_PROVIDER)

      described_class.ensure_baseline!(bill, provisioning: prov)

      revisions = bill.bill_summary_revisions.order(:id)
      expect(revisions.count).to eq(2)

      draft_baseline = revisions.second
      expect(draft_baseline.origin).to eq("operator_paste")
      expect(draft_baseline.summary_markdown).to eq("Legacy pasted draft B")
      expect(draft_baseline.publication_role).to eq("draft")
      expect(draft_baseline.review_state).to eq("unknown")
    end

    it "is idempotent on retry and does not duplicate baselines" do
      bill.update!(summary: "Public text")
      prov = create(:bill_llm_provisioning, bill: bill, llm_summary: "Draft text")

      described_class.ensure_baseline!(bill, provisioning: prov)
      expect {
        described_class.ensure_baseline!(bill, provisioning: prov)
      }.not_to change { bill.bill_summary_revisions.count }
    end
  end

  describe "idempotency" do
    it "returns the existing revision without creating a duplicate when identical attributes are provided" do
      rev1 = described_class.record_revision!(
        bill: bill,
        summary_markdown: "Summary text",
        origin: "model_generation",
        publication_role: "published",
        review_state: "unreviewed",
        llm_provider: "claude",
        llm_model: "claude-3-5-sonnet-20241022"
      )

      rev2 = described_class.record_revision!(
        bill: bill,
        summary_markdown: "Summary text",
        origin: "model_generation",
        publication_role: "published",
        review_state: "unreviewed",
        llm_provider: "claude",
        llm_model: "claude-3-5-sonnet-20241022"
      )

      expect(rev1.id).to eq(rev2.id)
    end

    it "creates a new revision when text or metadata changes" do
      rev1 = described_class.record_revision!(
        bill: bill,
        summary_markdown: "Summary text 1",
        origin: "model_generation",
        publication_role: "published",
        review_state: "unreviewed"
      )

      rev2 = described_class.record_revision!(
        bill: bill,
        summary_markdown: "Summary text 2",
        origin: "model_generation",
        publication_role: "published",
        review_state: "unreviewed"
      )

      expect(rev1.id).not_to eq(rev2.id)
    end
  end

  describe "#actor_name" do
    it "returns actor full name when available" do
      user.update!(full_name: "Senator Jane")
      rev = described_class.new(bill: bill, actor: user, summary_markdown: "S", origin: "operator_edit", publication_role: "published", review_state: "reviewed")
      expect(rev.actor_name).to eq("Senator Jane")
    end

    it "returns actor email when full name is blank" do
      user.update!(full_name: nil, email: "senator@example.com")
      rev = described_class.new(bill: bill, actor: user, summary_markdown: "S", origin: "operator_edit", publication_role: "published", review_state: "reviewed")
      expect(rev.actor_name).to eq("senator@example.com")
    end

    it "returns nil when actor is nil" do
      rev = described_class.new(bill: bill, actor: nil, summary_markdown: "S", origin: "model_generation", publication_role: "published", review_state: "unreviewed")
      expect(rev.actor_name).to be_nil
    end
  end

  describe "news_source_snapshot association" do
    let(:snapshot) { create(:news_article_source_snapshot, bill: bill) }

    it "optionally associates with a NewsArticleSourceSnapshot belonging to the same bill" do
      revision = described_class.create!(
        bill: bill,
        summary_markdown: "Summary citing approved news.",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed",
        news_source_snapshot: snapshot
      )

      expect(revision.news_source_snapshot).to eq(snapshot)
    end

    it "rejects news_source_snapshot belonging to a different bill" do
      other_bill = create(:bill, sway_locale: sway_locale)
      foreign_snapshot = create(:news_article_source_snapshot, bill: other_bill)

      expect {
        described_class.create!(
          bill: bill,
          summary_markdown: "Summary citing foreign news.",
          origin: "operator_edit",
          publication_role: "published",
          review_state: "reviewed",
          news_source_snapshot: foreign_snapshot
        )
      }.to raise_error(ActiveRecord::RecordInvalid, /must belong to the same bill/)
    end

    it "persists news_source_snapshot via BillSummaryRevision.record_revision!" do
      rev = described_class.record_revision!(
        bill: bill,
        summary_markdown: "Recorded summary markdown.",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed",
        news_source_snapshot: snapshot
      )

      expect(rev.news_source_snapshot_id).to eq(snapshot.id)
    end

    it "treats different snapshots as new revisions during record_revision! deduplication" do
      rev1 = described_class.record_revision!(
        bill: bill,
        summary_markdown: "Recorded summary markdown.",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed",
        news_source_snapshot: snapshot
      )

      snapshot2 = create(:news_article_source_snapshot, bill: bill)
      rev2 = described_class.record_revision!(
        bill: bill,
        summary_markdown: "Recorded summary markdown.",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed",
        news_source_snapshot: snapshot2
      )

      expect(rev1.id).not_to eq(rev2.id)
      expect(rev2.news_source_snapshot_id).to eq(snapshot2.id)
    end
  end

  describe "bill deletion cascade" do
    it "allows deleting a bill with revisions via dependent: :delete_all" do
      described_class.record_revision!(
        bill: bill,
        summary_markdown: "Summary text",
        origin: "model_generation",
        publication_role: "published",
        review_state: "unreviewed"
      )

      expect(bill.bill_summary_revisions.count).to be >= 1
      expect { bill.destroy! }.not_to raise_error
      expect(described_class.where(bill_id: bill.id).count).to eq(0)
    end
  end

  describe "BillSummaryRevisionResource serializer contract" do
    it "emits the exact 13-key whitelist with news_source_snapshot_id and has_snapshot" do
      snapshot = create(:news_article_source_snapshot, bill: bill)
      snap_rev = described_class.create!(
        bill: bill,
        summary_markdown: "Snapshot revision",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed",
        news_source_snapshot: snapshot
      )
      legacy_rev = described_class.create!(
        bill: bill,
        summary_markdown: "Legacy revision",
        origin: "operator_edit",
        publication_role: "draft",
        review_state: "reviewed",
        news_source_snapshot: nil
      )

      expected_keys = %w[
        id bill_id summary_markdown origin actor_name llm_provider llm_model
        publication_role review_state restored_from_id news_source_snapshot_id
        has_snapshot created_at
      ]
      snap_hash = JSON.parse(BillSummaryRevisionResource.new(snap_rev).serialize)
      legacy_hash = JSON.parse(BillSummaryRevisionResource.new(legacy_rev).serialize)

      expect(snap_hash.keys).to match_array(expected_keys)
      expect(snap_hash["has_snapshot"]).to be(true)
      expect(snap_hash["news_source_snapshot_id"]).to eq(snapshot.id)

      expect(legacy_hash.keys).to match_array(expected_keys)
      expect(legacy_hash["has_snapshot"]).to be(false)
      expect(legacy_hash["news_source_snapshot_id"]).to be_nil
    end
  end

  # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Planned recoverable summary history]]
  describe "atomic rollback and PasteSummaryService baseline capture" do
    it "rolls back bill.summary update completely if record_revision! raises RecordInvalid inside with_lock" do
      bill.update!(summary: "Original pristine summary")
      initial_rev_count = bill.bill_summary_revisions.count

      allow(described_class).to receive(:record_revision!).and_wrap_original do |m, **kwargs|
        if kwargs[:origin] == "operator_edit"
          raise ActiveRecord::RecordInvalid.new(described_class.new)
        else
          m.call(**kwargs)
        end
      end

      expect {
        bill.with_lock do
          described_class.ensure_baseline!(bill)
          bill.update!(summary: "Illegitimately modified summary")
          described_class.record_revision!(
            bill: bill,
            summary_markdown: "Illegitimately modified summary",
            origin: "operator_edit",
            actor: user,
            publication_role: "published",
            review_state: "reviewed"
          )
        end
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(bill.reload.summary).to eq("Original pristine summary")
      expect(bill.bill_summary_revisions.count).to eq(initial_rev_count)
    end

    it "captures both public and draft baselines before paste replacement via PasteSummaryService" do
      bill.update!(summary: "Public summary X")
      create(:bill_llm_provisioning,
        bill: bill,
        llm_summary: "Legacy draft Y",
        llm_provider: "claude",
        llm_model: "claude-haiku",
        generation_status: "completed")

      paste_service = PasteSummaryService.new(
        bill: bill,
        actor: user,
        summary_json: JSON.generate({
          "summary_markdown" => "## Summary\nOperator pasted Z",
          "full_breakdown_markdown" => "## Breakdown\nBreakdown Z",
          "draft_org_positions" => []
        })
      )

      expect(paste_service.call).to be_truthy

      revisions = bill.bill_summary_revisions.order(:id)
      expect(revisions.count).to eq(3)
      expect(revisions.first.summary_markdown).to eq("Public summary X")
      expect(revisions.first.origin).to eq("initial_baseline")
      expect(revisions.second.summary_markdown).to eq("Legacy draft Y")
      expect(revisions.second.origin).to eq("model_generation")
      expect(revisions.second.llm_model).to eq("claude-haiku")
      expect(revisions.third.summary_markdown).to eq("## Summary\nOperator pasted Z")
      expect(revisions.third.origin).to eq("operator_paste")
      expect(revisions.third.publication_role).to eq("draft")
    end
  end
end
