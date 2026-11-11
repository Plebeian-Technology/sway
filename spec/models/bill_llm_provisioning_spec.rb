# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_llm_provisionings
# Database name: primary
#
#  id                               :integer          not null, primary key
#  categories_unmatched_at          :datetime
#  citations_valid                  :boolean
#  cleaned_testimony                :text
#  cleaned_testimony_at             :datetime
#  diff_content                     :text
#  diff_generated_at                :datetime
#  draft_org_positions              :text
#  extracted_testimony              :text
#  generation_error                 :text
#  generation_status                :string
#  hearings_fetched_at              :datetime
#  individual_campaign_draft_hashes :text
#  invalid_citations                :text
#  invalid_news_urls                :text
#  llm_full_breakdown               :text
#  llm_generated_at                 :datetime
#  llm_model                        :string
#  llm_provider                     :string
#  llm_summary                      :text
#  news_articles                    :text
#  news_articles_fetched_at         :datetime
#  news_urls_valid                  :boolean
#  rejected_campaign_draft_hashes   :text
#  summary_batch_expires_at         :datetime
#  summary_batch_testimony_digest   :string
#  supplemental_testimony           :text
#  testimony_attachments            :text
#  testimony_fetched_at             :datetime
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  bill_id                          :integer          not null
#  summary_batch_id                 :string
#  summary_run_id                   :string
#
# Indexes
#
#  index_bill_llm_provisionings_on_bill_id                  (bill_id) UNIQUE
#  index_bill_llm_provisionings_on_categories_unmatched_at  (categories_unmatched_at) WHERE categories_unmatched_at IS NOT NULL
#  index_bill_llm_provisionings_on_llm_generated_at         (llm_generated_at)
#  index_bill_llm_provisionings_on_summary_batch_id         (summary_batch_id)
#  index_bill_llm_provisionings_on_summary_run_id           (summary_run_id) UNIQUE WHERE summary_run_id IS NOT NULL
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#
RSpec.describe BillLlmProvisioning do
  describe "associations" do
    it "belongs to a bill" do
      provisioning = build(:bill_llm_provisioning)
      expect(provisioning.bill).to be_a(Bill)
    end
  end

  describe "#stale?" do
    it "returns false when llm_generated_at is nil" do
      provisioning =
        build(
          :bill_llm_provisioning,
          llm_generated_at: nil,
          diff_generated_at: Time.zone.now
        )
      expect(provisioning.stale?).to be(false)
    end

    it "returns false when diff_generated_at is nil" do
      provisioning =
        build(
          :bill_llm_provisioning,
          llm_generated_at: Time.zone.now,
          diff_generated_at: nil
        )
      expect(provisioning.stale?).to be(false)
    end

    it "returns false when both are nil" do
      provisioning = build(:bill_llm_provisioning)
      expect(provisioning.stale?).to be(false)
    end

    it "returns true when diff is newer than llm generation" do
      provisioning =
        build(
          :bill_llm_provisioning,
          llm_generated_at: 1.hour.ago,
          diff_generated_at: Time.zone.now
        )
      expect(provisioning.stale?).to be(true)
    end

    it "returns false when llm generation is newer than diff" do
      provisioning =
        build(
          :bill_llm_provisioning,
          llm_generated_at: Time.zone.now,
          diff_generated_at: 1.hour.ago
        )
      expect(provisioning.stale?).to be(false)
    end

    # testimony_fetched_at follows the same rule as the diff above: both are
    # compared against the same llm_generated_at.
    context "testimony stale" do
      it "returns true when testimony is fetched after llm generation" do
        provisioning =
          build(
            :bill_llm_provisioning,
            llm_generated_at: 1.hour.ago,
            testimony_fetched_at: 1.hour.after(1.hour.ago)
          )
        expect(provisioning.stale?).to be(true)
      end

      it "returns false when testimony was fetched before llm generation" do
        provisioning =
          build(
            :bill_llm_provisioning,
            llm_generated_at: Time.zone.now,
            testimony_fetched_at: 1.hour.ago
          )
        expect(provisioning.stale?).to be(false)
      end

      it "returns false when llm_generated_at is nil, regardless of testimony_fetched_at" do
        provisioning =
          build(
            :bill_llm_provisioning,
            llm_generated_at: nil,
            testimony_fetched_at: Time.zone.now
          )
        expect(provisioning.stale?).to be(false)
      end

      it "still returns true on the preserved diff branch when testimony is not newer" do
        provisioning =
          build(
            :bill_llm_provisioning,
            llm_generated_at: 1.hour.ago,
            diff_generated_at: Time.zone.now,
            testimony_fetched_at: 2.hours.ago
          )
        expect(provisioning.stale?).to be(true)
      end
    end
  end

  # @lat: [[stale-change-detection#The two change-kind words are spelled once on each side]]
  # Every fixture that matters here makes the two columns disagree — a fixture that
  # moves them together cannot tell "names the real cause" apart from "always says
  # the diff".
  describe "#stale_change" do
    it "names testimony and the testimony moment when testimony alone overtook the summary" do
      testimony_at = 1.hour.ago
      provisioning =
        build(
          :bill_llm_provisioning,
          llm_generated_at: 1.day.ago,
          testimony_fetched_at: testimony_at,
          diff_generated_at: 21.days.ago
        )

      kind, at = provisioning.stale_change

      expect(kind).to eq(BillLlmProvisioning::TESTIMONY_CHANGE)
      expect(at).to be_within(1.second).of(testimony_at)
    end

    it "names pipeline data and the diff moment when the diff alone overtook the summary" do
      diff_at = 1.hour.ago
      provisioning =
        build(
          :bill_llm_provisioning,
          llm_generated_at: 1.day.ago,
          testimony_fetched_at: 21.days.ago,
          diff_generated_at: diff_at
        )

      kind, at = provisioning.stale_change

      expect(kind).to eq(BillLlmProvisioning::PIPELINE_DATA_CHANGE)
      expect(at).to be_within(1.second).of(diff_at)
    end

    # When both overtook the summary, the newer one is the most recent thing to
    # do so, and that is what an operator wants named.
    it "names the newer of the two when both overtook the summary" do
      newer = 1.hour.ago
      provisioning =
        build(
          :bill_llm_provisioning,
          llm_generated_at: 2.days.ago,
          testimony_fetched_at: newer,
          diff_generated_at: 1.day.ago
        )

      kind, at = provisioning.stale_change

      expect(kind).to eq(BillLlmProvisioning::TESTIMONY_CHANGE)
      expect(at).to be_within(1.second).of(newer)
    end

    it "names the diff when it is the newer of the two" do
      newer = 1.hour.ago
      provisioning =
        build(
          :bill_llm_provisioning,
          llm_generated_at: 2.days.ago,
          testimony_fetched_at: 1.day.ago,
          diff_generated_at: newer
        )

      kind, at = provisioning.stale_change

      expect(kind).to eq(BillLlmProvisioning::PIPELINE_DATA_CHANGE)
      expect(at).to be_within(1.second).of(newer)
    end

    # A diff newer than the testimony can still be OLDER than the summary. It
    # overtook nothing, so it must not be named — which is why the comparison
    # needs llm_generated_at and cannot be "whichever column is newer".
    it "names nothing when the newer of the two columns still predates the summary" do
      provisioning =
        build(
          :bill_llm_provisioning,
          llm_generated_at: Time.zone.now,
          testimony_fetched_at: 2.days.ago,
          diff_generated_at: 1.day.ago
        )

      expect(provisioning.stale_change).to be_nil
      expect(provisioning.stale?).to be(false)
    end

    it "names nothing when the summary has never been generated" do
      provisioning =
        build(
          :bill_llm_provisioning,
          llm_generated_at: nil,
          testimony_fetched_at: Time.zone.now,
          diff_generated_at: Time.zone.now
        )

      expect(provisioning.stale_change).to be_nil
    end
  end

  describe "#testimony_present?" do
    it "returns true when extracted_testimony is present" do
      provisioning =
        build(:bill_llm_provisioning, extracted_testimony: "Some testimony")
      expect(provisioning.testimony_present?).to be(true)
    end

    it "returns true when supplemental_testimony is present" do
      provisioning =
        build(
          :bill_llm_provisioning,
          supplemental_testimony: "Admin-typed testimony"
        )
      expect(provisioning.testimony_present?).to be(true)
    end

    it "returns false when both are blank" do
      provisioning =
        build(
          :bill_llm_provisioning,
          extracted_testimony: nil,
          supplemental_testimony: nil
        )
      expect(provisioning.testimony_present?).to be(false)
    end
  end

  # What a retry of a summary run reads to find out whether it still owes the
  # positions call. The purchase marker on the row cannot say which of the two
  # calls it paid for, because both write the same value.
  describe "#positions_owed?" do
    it "is true for testimony with no stored positions" do
      provisioning = build(
        :bill_llm_provisioning,
        extracted_testimony: "Testimony from the hearing.",
        draft_org_positions: nil
      )
      expect(provisioning.positions_owed?).to be(true)
    end

    # An empty list is an answer: the call ran and named no organization. Asking
    # again buys the same nothing a second time.
    it "is false once an empty list has been stored" do
      provisioning = build(
        :bill_llm_provisioning,
        extracted_testimony: "Testimony from the hearing.",
        draft_org_positions: []
      )
      expect(provisioning.positions_owed?).to be(false)
    end

    it "is false once positions have been stored" do
      provisioning = build(
        :bill_llm_provisioning, :with_drafts, draft_org_positions: [
          {"org_name" => "Test Org", "stance" => "support", "summary" => "Test position"}
        ]
      )
      expect(provisioning.positions_owed?).to be(false)
    end

    # No testimony means the call never fires at all, so nothing is owed.
    it "is false without testimony" do
      provisioning = build(
        :bill_llm_provisioning,
        extracted_testimony: nil,
        supplemental_testimony: nil,
        draft_org_positions: nil
      )
      expect(provisioning.positions_owed?).to be(false)
    end

    it "is true when approved news article with usable text exists even without hearing testimony" do
      bill = create(:bill)
      news_article = create(:news_article)
      tv = create(:news_article_text_version, :extracted, news_article: news_article, text: "Detailed news report text.")
      create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: tv)
      provisioning = create(
        :bill_llm_provisioning,
        bill: bill,
        extracted_testimony: nil,
        supplemental_testimony: nil,
        draft_org_positions: nil
      )

      expect(provisioning.positions_owed?).to be(true)
    end
  end

  describe "state machine" do
    it "has nil initial generation_status" do
      provisioning = create(:bill_llm_provisioning)
      expect(provisioning.generation_status).to be_nil
    end

    it "transitions from nil to pending via enqueue!" do
      provisioning = create(:bill_llm_provisioning)
      provisioning.enqueue!
      expect(provisioning.generation_status).to eq("pending")
    end

    it "transitions from completed to pending via enqueue! (Regenerate)" do
      provisioning = create(:bill_llm_provisioning, :completed)
      provisioning.enqueue!
      expect(provisioning.generation_status).to eq("pending")
    end

    it "transitions from failed to pending via enqueue! (Retry)" do
      provisioning = create(:bill_llm_provisioning, :failed)
      provisioning.enqueue!
      expect(provisioning.generation_status).to eq("pending")
    end

    it "transitions from pending to generating via start_generating!" do
      provisioning = create(:bill_llm_provisioning, :pending)
      provisioning.start_generating!
      expect(provisioning.generation_status).to eq("generating")
    end

    it "transitions from generating to completed via mark_completed!" do
      provisioning = create(:bill_llm_provisioning, :generating)
      provisioning.mark_completed!
      expect(provisioning.generation_status).to eq("completed")
    end

    it "transitions from generating to failed via mark_failed!" do
      provisioning = create(:bill_llm_provisioning, :generating)
      provisioning.mark_failed!
      expect(provisioning.generation_status).to eq("failed")
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#Why the reclaim judgement lives on the row]]
    it "transitions from pending to skipped via mark_skipped!" do
      provisioning = create(:bill_llm_provisioning, :pending)
      provisioning.mark_skipped!
      expect(provisioning.generation_status).to eq("skipped")
    end

    it "transitions from skipped to pending via enqueue! (re-arm after stale skip)" do
      provisioning = create(:bill_llm_provisioning, :skipped)
      provisioning.enqueue!
      expect(provisioning.generation_status).to eq("pending")
    end

    it "raises when mark_skipped! called on generating (skipped only from pending)" do
      provisioning = create(:bill_llm_provisioning, :generating)
      expect { provisioning.mark_skipped! }.to raise_error(
        StateMachines::InvalidTransition
      )
    end

    it "#can_mark_skipped? is true only for pending rows" do
      expect(create(:bill_llm_provisioning, :pending).can_mark_skipped?).to be(true)
      expect(create(:bill_llm_provisioning, :generating).can_mark_skipped?).to be(false)
      expect(create(:bill_llm_provisioning, :completed).can_mark_skipped?).to be(false)
    end

    it "raises when enqueue! called on pending (cannot double-enqueue)" do
      provisioning = create(:bill_llm_provisioning, :pending)
      expect { provisioning.enqueue! }.to raise_error(
        StateMachines::InvalidTransition
      )
    end

    it "raises when enqueue! called on generating (cannot enqueue while generating)" do
      provisioning = create(:bill_llm_provisioning, :generating)
      expect { provisioning.enqueue! }.to raise_error(
        StateMachines::InvalidTransition
      )
    end

    it "#pending? returns true when generation_status is 'pending'" do
      provisioning = build(:bill_llm_provisioning, :pending)
      expect(provisioning.pending?).to be(true)
    end

    it "#generating? returns true when generation_status is 'generating'" do
      provisioning = build(:bill_llm_provisioning, :generating)
      expect(provisioning.generating?).to be(true)
    end
  end

  describe "draft_org_positions serialization" do
    it "serializes draft_org_positions as JSON" do
      positions = [
        {
          "org_name" => "Test Org",
          "stance" => "support",
          "summary" => "Test"
        }
      ]
      provisioning =
        create(:bill_llm_provisioning, draft_org_positions: positions)
      provisioning.reload
      expect(provisioning.draft_org_positions).to be_an(Array)
      expect(provisioning.draft_org_positions.first["org_name"]).to eq(
        "Test Org"
      )
    end

    # @lat: [[bill-llm-provisioning-factory-design#:with_testimony and why :with_drafts pulls it in automatically]]
    it "the :with_drafts trait's draft_org_positions satisfy the positions schema" do
      provisioning = create(:bill_llm_provisioning, :with_drafts)

      errors = BILL_POSITIONS_SCHEMA
        .validate({"draft_org_positions" => provisioning.draft_org_positions})
        .to_a

      expect(errors).to be_empty
      expect(provisioning.draft_org_positions.first["stance"]).to eq("support")
    end

    # @lat: [[bill-llm-provisioning-factory-design#:with_testimony and why :with_drafts pulls it in automatically]]
    it ":completed seeds no drafts — a finished summary is not a position" do
      expect(create(:bill_llm_provisioning, :completed).draft_org_positions).to be_nil
    end

    it ":with_drafts carries the testimony its drafts were drawn from" do
      expect(create(:bill_llm_provisioning, :with_drafts).testimony_present?).to be(true)
    end
  end

  # The identifier the Bill Creator card sends back when an admin approves or
  # rejects a draft. The card can only send it if it arrived with the bill's
  # props, and BillsController#bill_creator_props builds those props through
  # `to_sway_json` and then `to_builder`, so these examples pin the whole path.
  describe ".draft_token / draft_org_positions serialization (B2-IN-01)" do
    let(:duplicate_names) do
      [
        {"org_name" => "Renters United", "stance" => "support", "summary" => "The coalition supports."},
        {"org_name" => "Renters United", "stance" => "oppose", "summary" => "A member testified against."}
      ]
    end

    it "distinguishes two drafts that share an org_name" do
      tokens = duplicate_names.map { |entry| described_class.draft_token(entry) }

      expect(tokens.uniq.length).to eq(2)
      expect(tokens).to all(match(/\A[0-9a-f]{16}\z/))
    end

    it "is stable across JSON key order, so a round-trip does not invalidate it" do
      reordered = {"summary" => "The coalition supports.", "org_name" => "Renters United", "stance" => "support"}

      expect(described_class.draft_token(reordered)).to eq(described_class.draft_token(duplicate_names.first))
    end

    it "has no identity for a non-Hash entry" do
      expect(described_class.draft_token("not a draft")).to be_nil
      expect(described_class.draft_token(nil)).to be_nil
    end

    it "reaches the client through to_sway_json, matching .draft_token for each entry" do
      provisioning = create(:bill_llm_provisioning, draft_org_positions: duplicate_names)

      served = provisioning.reload.to_sway_json["draft_org_positions"]

      expect(served.pluck("draft_token")).to eq(
        duplicate_names.map { |entry| described_class.draft_token(entry) }
      )
    end

    it "does not persist the token — the stored array stays the wire shape" do
      provisioning = create(:bill_llm_provisioning, draft_org_positions: duplicate_names)
      provisioning.to_sway_json

      expect(provisioning.reload.draft_org_positions).to eq(duplicate_names)
    end

    it "serializes a nil column as nil rather than raising" do
      provisioning = create(:bill_llm_provisioning, draft_org_positions: nil)

      expect(provisioning.reload.to_sway_json["draft_org_positions"]).to be_nil
    end
  end

  # @lat: [[hearing-testimony-census#Retracting evidence retires the conclusions drawn from it]]
  describe ".drafts_with_evidence_retracted (B4-CR-02)" do
    it "stamps every Hash entry with an ISO-8601 timestamp" do
      at = Time.utc(2026, 7, 1, 12, 30)
      marked = described_class.drafts_with_evidence_retracted(
        [{"org_name" => "ACME"}, {"org_name" => "Beta"}], at: at
      )

      expect(marked.pluck(described_class::DRAFT_EVIDENCE_RETRACTED_KEY)).to eq(
        ["2026-07-01T12:30:00Z", "2026-07-01T12:30:00Z"]
      )
      expect(marked.pluck("org_name")).to eq(%w[ACME Beta])
    end

    it "keeps the FIRST retraction's timestamp when re-marked" do
      once = described_class.drafts_with_evidence_retracted(
        [{"org_name" => "ACME"}], at: Time.utc(2026, 7, 1)
      )
      twice = described_class.drafts_with_evidence_retracted(once, at: Time.utc(2026, 7, 9))

      expect(twice.first[described_class::DRAFT_EVIDENCE_RETRACTED_KEY]).to eq("2026-07-01T00:00:00Z")
    end

    it "passes a nil column and non-Hash entries through untouched" do
      expect(described_class.drafts_with_evidence_retracted(nil)).to be_nil
      expect(described_class.drafts_with_evidence_retracted([{"rejected" => true}, "junk"]).last).to eq("junk")
    end

    it "reads the mark back off an entry" do
      marked = described_class.drafts_with_evidence_retracted([{"org_name" => "ACME"}]).first

      expect(described_class.draft_evidence_retracted?(marked)).to be(true)
      expect(described_class.draft_evidence_retracted?({"org_name" => "ACME"})).to be(false)
      expect(described_class.draft_evidence_retracted?("not a draft")).to be(false)
    end

    # The Bill Creator can only explain why it refused if the mark reaches it in
    # the bill's props, which are built through to_sway_json and then to_builder.
    it "reaches the client through to_sway_json alongside the identity token" do
      provisioning = create(:bill_llm_provisioning, draft_org_positions:
        described_class.drafts_with_evidence_retracted([{"org_name" => "ACME", "stance" => "support", "summary" => "x"}]))

      served = provisioning.reload.to_sway_json["draft_org_positions"].first

      expect(served[described_class::DRAFT_EVIDENCE_RETRACTED_KEY]).to be_present
      expect(served["draft_token"]).to match(/\A[0-9a-f]{16}\z/)
    end
  end

  # @lat: [[internal-draft-marks#Carrying marks through a paste]]
  describe ".draft_org_positions_preserving_marks" do
    # The regression case: one stored entry carrying BOTH marks at once,
    # which is real production shape — BillDraftOrgPositionsController stamps
    # the edit mark on an operator's summary edit, and FetchHearingsService
    # stamps the retraction independently on the same entry.
    it "carries BOTH marks forward when a stored entry holds both" do
      retracted_at = 2.days.ago.utc.iso8601
      edited_at = 1.day.ago.utc.iso8601
      stored = [
        {
          "org_name" => "Maryland Tenants Union",
          "stance" => "support",
          "summary" => "Spoke in favor at the hearing.",
          described_class::DRAFT_EVIDENCE_RETRACTED_KEY => retracted_at,
          described_class::DRAFT_SUMMARY_EDITED_KEY => edited_at
        }
      ]
      # A pasted entry never carries either internal key — the schema
      # forbids it (additionalProperties: false).
      pasted = [
        {"org_name" => "Maryland Tenants Union", "stance" => "support", "summary" => "Spoke in favor at the hearing."}
      ]

      result = described_class.draft_org_positions_preserving_marks(stored, pasted)

      expect(result.first[described_class::DRAFT_EVIDENCE_RETRACTED_KEY]).to eq(retracted_at)
      expect(result.first[described_class::DRAFT_SUMMARY_EDITED_KEY]).to eq(edited_at)
    end

    it "carries forward a summary-edited mark alone, with no retraction present" do
      edited_at = 1.day.ago.utc.iso8601
      stored = [
        {
          "org_name" => "ACLU",
          "stance" => "oppose",
          "summary" => "Testified against the bill.",
          described_class::DRAFT_SUMMARY_EDITED_KEY => edited_at
        }
      ]
      pasted = [{"org_name" => "ACLU", "stance" => "oppose", "summary" => "Testified against the bill."}]

      result = described_class.draft_org_positions_preserving_marks(stored, pasted)

      expect(result.first[described_class::DRAFT_SUMMARY_EDITED_KEY]).to eq(edited_at)
      expect(result.first).not_to have_key(described_class::DRAFT_EVIDENCE_RETRACTED_KEY)
    end

    it "inherits no mark when the pasted entry's content changed — a new claim" do
      edited_at = 1.day.ago.utc.iso8601
      retracted_at = 2.days.ago.utc.iso8601
      stored = [
        {
          "org_name" => "ACLU",
          "stance" => "oppose",
          "summary" => "Testified against the bill.",
          described_class::DRAFT_SUMMARY_EDITED_KEY => edited_at,
          described_class::DRAFT_EVIDENCE_RETRACTED_KEY => retracted_at
        }
      ]
      pasted = [{"org_name" => "ACLU", "stance" => "support", "summary" => "Changed position."}]

      result = described_class.draft_org_positions_preserving_marks(stored, pasted)

      expect(result.first).not_to have_key(described_class::DRAFT_SUMMARY_EDITED_KEY)
      expect(result.first).not_to have_key(described_class::DRAFT_EVIDENCE_RETRACTED_KEY)
    end

    it "passes non-Array stored or pasted values through untouched" do
      expect(described_class.draft_org_positions_preserving_marks(nil, [{"org_name" => "x"}]))
        .to eq([{"org_name" => "x"}])
      expect(described_class.draft_org_positions_preserving_marks([{"org_name" => "x"}], nil)).to be_nil
    end
  end

  # The BillArtifactMirror table was dropped. The other half of the old rule —
  # "any cached copy is out of date" — read from that table and is no longer
  # tracked. The `stale` field in the JSON now comes only from #stale?, which
  # means the diff is newer than the summary.
  describe "#to_builder stale field" do
    it "returns stale=false when llm is newer than diff (or both are nil)" do
      provisioning = create(:bill_llm_provisioning,
        llm_generated_at: 1.hour.ago,
        diff_generated_at: 2.hours.ago)
      props = JSON.parse(provisioning.to_builder.target!)
      expect(props["stale"]).to be(false)
    end

    it "returns stale=true when diff is newer than llm" do
      provisioning = create(:bill_llm_provisioning,
        llm_generated_at: 1.day.ago,
        diff_generated_at: Time.current)
      props = JSON.parse(provisioning.to_builder.target!)
      expect(props["stale"]).to be(true)
    end

    # @lat: [[bill-creator-summary-tab#What the staleness marker quotes]]
    it "sends the testimony moment and reason when testimony alone overtook the summary" do
      testimony_at = 1.hour.ago
      provisioning = create(:bill_llm_provisioning,
        llm_generated_at: 1.day.ago,
        testimony_fetched_at: testimony_at,
        diff_generated_at: 21.days.ago)

      props = JSON.parse(provisioning.to_builder.target!)

      expect(props["stale"]).to be(true)
      expect(props["stale_change_kind"]).to eq("testimony")
      expect(Time.zone.parse(props["stale_change_at"])).to be_within(1.second).of(testimony_at)
    end

    it "sends no reason and no moment on a summary nothing has overtaken" do
      provisioning = create(:bill_llm_provisioning,
        llm_generated_at: Time.current,
        testimony_fetched_at: 1.day.ago,
        diff_generated_at: 1.day.ago)

      props = JSON.parse(provisioning.to_builder.target!)

      expect(props["stale"]).to be(false)
      expect(props["stale_change_kind"]).to be_nil
      expect(props["stale_change_at"]).to be_nil
    end
  end

  # @lat: [[abandoned-run-reclaim#Why ReclaimAbandonedSummaryRunsJob exists]]
  describe "#reclaimable?" do
    # Named off the vocabulary summary_run_arm_decision_spec already uses, so the
    # two files cannot be read for each other: this is `updated_at`, the
    # abandonment clock, and not the stale gate's `enqueued_at`.
    let(:abandoned_clock) { (GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER + 1.minute).ago }

    # update_all rather than the factory, because updated_at is the input under
    # test and any callback would bump it back to now.
    def reclaimable_row_with(status, updated_at:, llm_summary: "A summary", llm_generated_at: nil,
      summary_batch_expires_at: nil, bill: nil)
      row = create(:bill_llm_provisioning, bill: bill || create(:bill),
        llm_summary: llm_summary, llm_generated_at: llm_generated_at)
      BillLlmProvisioning.where(id: row.id).update_all(
        generation_status: status, updated_at: updated_at, summary_batch_expires_at: summary_batch_expires_at
      )
      row.reload
    end

    it "answers true for the row #stale? cannot speak for at all" do
      row = reclaimable_row_with("generating", updated_at: abandoned_clock,
        llm_summary: nil, llm_generated_at: nil)

      expect(row.stale?).to be(false)
      expect(row.reclaimable?).to be(true)
    end

    it "covers a stranded pending row too, not only generating" do
      expect(reclaimable_row_with("pending", updated_at: abandoned_clock).reclaimable?).to be(true)
    end

    it "answers false for a run that is still writing" do
      expect(reclaimable_row_with("generating", updated_at: 1.minute.ago).reclaimable?).to be(false)
    end

    it "answers false for a settled row however old" do
      expect(reclaimable_row_with("completed", updated_at: abandoned_clock).reclaimable?).to be(false)
    end

    # @lat: [[abandoned-run-reclaim#nil updated_at is NOT reclaimable]]
    it "answers false when the row carries no timestamp at all" do
      expect(described_class.new(generation_status: "generating").reclaimable?).to be(false)
    end

    it "goes out on the prop, so the surface can offer the exit" do
      row = reclaimable_row_with("generating", updated_at: abandoned_clock)

      expect(JSON.parse(row.to_builder.target!)["reclaimable"]).to be(true)
    end

    it "offers the same rows as candidates that the predicate would call reclaimable" do
      dates = (1..6).map { |n| n.days.ago }
      quiet = reclaimable_row_with("generating", updated_at: abandoned_clock,
        bill: create(:bill, scheduled_release_date_utc: dates[0]))
      busy = reclaimable_row_with("generating", updated_at: 1.minute.ago,
        bill: create(:bill, scheduled_release_date_utc: dates[1]))
      done = reclaimable_row_with("completed", updated_at: abandoned_clock,
        bill: create(:bill, scheduled_release_date_utc: dates[2]))
      awaited = reclaimable_row_with("generating", updated_at: abandoned_clock,
        summary_batch_expires_at: 1.hour.from_now, bill: create(:bill, scheduled_release_date_utc: dates[3]))
      expired_batch = reclaimable_row_with("generating", updated_at: abandoned_clock,
        summary_batch_expires_at: 1.minute.ago, bill: create(:bill, scheduled_release_date_utc: dates[4]))
      nil_batch_expiry = reclaimable_row_with("pending", updated_at: abandoned_clock,
        summary_batch_expires_at: nil, bill: create(:bill, scheduled_release_date_utc: dates[5]))

      candidates = described_class.reclaimable_candidates.to_a

      expect(candidates).to include(quiet, expired_batch, nil_batch_expiry)
      expect(candidates).not_to include(busy, done, awaited)
    end
  end

  describe "batch exemption from the abandoned sweep" do
    let(:abandoned_clock) { (GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER + 1.minute).ago }

    def quiet_batch_row(summary_batch_expires_at:, status: "generating")
      row = create(:bill_llm_provisioning)
      BillLlmProvisioning.where(id: row.id).update_all(
        generation_status: status, updated_at: abandoned_clock, summary_batch_expires_at: summary_batch_expires_at
      )
      row.reload
    end

    it "is not reclaimable while quiet and the batch has not expired" do
      row = quiet_batch_row(summary_batch_expires_at: 1.hour.from_now)
      expect(row.reclaimable?).to be(false)
    end

    it "is not offered as a reclaimable_candidates row while the batch has not expired" do
      row = quiet_batch_row(summary_batch_expires_at: 1.hour.from_now)
      expect(described_class.reclaimable_candidates).not_to include(row)
    end

    it "is reclaimable once quiet past the batch's own expiry" do
      row = quiet_batch_row(summary_batch_expires_at: 1.minute.ago)
      expect(row.reclaimable?).to be(true)
    end

    it "is offered as a reclaimable_candidates row once quiet past the batch's own expiry" do
      row = quiet_batch_row(summary_batch_expires_at: 1.minute.ago)
      expect(described_class.reclaimable_candidates).to include(row)
    end

    it "treats a nil batch expiry as reclaimable rather than waiting forever" do
      row = quiet_batch_row(summary_batch_expires_at: nil)
      expect(row.reclaimable?).to be(true)
      expect(described_class.reclaimable_candidates).to include(row)
    end

    it "still exempts a pending row, not only a generating one" do
      row = quiet_batch_row(status: "pending", summary_batch_expires_at: 1.hour.from_now)
      expect(row.reclaimable?).to be(false)
    end
  end

  describe "#summary_batch_awaited?" do
    it "is true while the batch expiry has not passed" do
      row = build(:bill_llm_provisioning, summary_batch_expires_at: 1.hour.from_now)
      expect(row).to be_summary_batch_awaited
    end

    it "is false once the expiry has passed" do
      row = build(:bill_llm_provisioning, summary_batch_expires_at: 1.minute.ago)
      expect(row).not_to be_summary_batch_awaited
    end

    it "is false when no expiry was recorded" do
      row = build(:bill_llm_provisioning, summary_batch_expires_at: nil)
      expect(row).not_to be_summary_batch_awaited
    end
  end

  # Adds the testimony and citation fields to the set of keys sent to the
  # browser. The raw extracted_testimony must never be one of them.
  describe "#to_builder testimony/citation key-set" do
    it "includes has_testimony, testimony_attachments, citations_valid, invalid_citations" do
      provisioning =
        create(
          :bill_llm_provisioning,
          extracted_testimony: "Some testimony",
          testimony_attachments: [
            {"filename" => "a.pdf", "download_status" => "success"}
          ],
          citations_valid: false,
          invalid_citations: ["art_99__sec_1"]
        )
      props = JSON.parse(provisioning.to_builder.target!)

      expect(props["has_testimony"]).to be(true)
      expect(props["testimony_attachments"]).to eq(
        [{"filename" => "a.pdf", "download_status" => "success"}]
      )
      expect(props["citations_valid"]).to be(false)
      expect(props["invalid_citations"]).to eq(["art_99__sec_1"])
    end

    it "excludes extracted_testimony" do
      provisioning =
        create(:bill_llm_provisioning, extracted_testimony: "Some testimony")
      props = JSON.parse(provisioning.to_builder.target!)

      expect(props).not_to have_key("extracted_testimony")
    end
  end

  # @lat: [[abandoned-run-reclaim#Which writer owns a reclaimable row#Why llm_provider alone got this wrong]]
  describe "#to_builder paste_owns_summary_run" do
    it "is true for the row SummaryRunRelease hands off" do
      provisioning = create(:bill_llm_provisioning, llm_provider: "operator_paste")
      BillLlmProvisioning.where(id: provisioning.id)
        .update_all(summary_run_id: SummaryRunMarker.operator_paste)

      props = JSON.parse(provisioning.reload.to_builder.target!)

      expect(props["paste_owns_summary_run"]).to be(true)
    end

    # THE ROW WHERE THE TWO COLUMNS DISAGREE. Both fixtures written for the
    # branch that reads this moved llm_provider and summary_run_id together, so
    # nothing could say which one an answer came from.
    it "is false when llm_provider still says paste but the arm cleared the marker" do
      provisioning = create(:bill_llm_provisioning, llm_provider: "operator_paste")
      BillLlmProvisioning.where(id: provisioning.id).update_all(summary_run_id: nil)

      props = JSON.parse(provisioning.reload.to_builder.target!)

      expect(props["llm_provider"]).to eq("operator_paste")
      expect(props["paste_owns_summary_run"]).to be(false)
    end

    # @lat: [[run-marker-column-semantics#Why not llm_provider == "operator_paste"]]
    it "is false for a run claim and for a purchase receipt" do
      provisioning = create(:bill_llm_provisioning)

      BillLlmProvisioning.where(id: provisioning.id)
        .update_all(summary_run_id: SummaryRunMarker.run_claim("job-1"))
      expect(JSON.parse(provisioning.reload.to_builder.target!)["paste_owns_summary_run"]).to be(false)

      BillLlmProvisioning.where(id: provisioning.id).update_all(summary_run_id: "job-1")
      expect(JSON.parse(provisioning.reload.to_builder.target!)["paste_owns_summary_run"]).to be(false)
    end
  end

  # @lat: [[bill-provisioning-payload#Why four testimony/citation fields stay on the older Jbuilder path]]
  # This is the exact key-set request spec CLAUDE.md asks for. summary_run_id stays
  # OUT — it carries job ids; the browser gets the derived paste_owns_summary_run
  # boolean instead.
  describe "#to_builder key set" do
    it "sends exactly these keys and no others" do
      provisioning = create(:bill_llm_provisioning, extracted_testimony: "Some testimony")

      props = JSON.parse(provisioning.to_builder.target!)

      expect(props.keys).to match_array(
        %w[
          id generation_status generation_error llm_summary llm_full_breakdown
          supplemental_testimony draft_org_positions llm_provider llm_model
          llm_generated_at stale stale_change_kind stale_change_at reclaimable
          paste_owns_summary_run has_testimony testimony_attachments
          citations_valid invalid_citations
        ]
      )
    end

    # @lat: [[bill-provisioning-payload#diff_content is not sent]]
    it "does not grow with the size of the bill diff" do
      provisioning = create(:bill_llm_provisioning, diff_content: nil)
      without_diff = provisioning.to_builder.target!.bytesize

      provisioning.update_columns(diff_content: "x" * 20_000)

      expect(provisioning.reload.to_builder.target!.bytesize).to eq(without_diff)
    end
  end

  describe "news articles persistence" do
    it "serializes news_articles as JSON" do
      articles = [
        {"url" => "https://thebanner.com/art1", "title" => "Title 1", "cited_text" => "Excerpt 1"}
      ]
      provisioning = create(:bill_llm_provisioning, news_articles: articles)
      expect(provisioning.reload.news_articles).to eq(articles)
      expect(provisioning.news_articles_list).to eq(articles)
    end

    it "returns empty array for news_articles_list when nil" do
      provisioning = build(:bill_llm_provisioning, news_articles: nil)
      expect(provisioning.news_articles_list).to eq([])
    end

    it "serializes invalid_news_urls as JSON" do
      urls = ["https://unlisted.com/1", "https://unlisted.com/2"]
      provisioning = create(:bill_llm_provisioning, invalid_news_urls: urls, news_urls_valid: false)
      expect(provisioning.reload.invalid_news_urls).to eq(urls)
      expect(provisioning.news_urls_valid).to be(false)
    end
  end

  # @lat: [[evidence-retraction#Reading the mark]]
  describe ".draft_news_sourced? and .news_sourced_draft?" do
    it "returns true when entry contains bill_news_article_id" do
      expect(described_class.draft_news_sourced?({"bill_news_article_id" => 123, "org_name" => "ACLU"})).to be(true)
      expect(described_class.draft_news_sourced?({bill_news_article_id: 123, org_name: "ACLU"})).to be(true)
    end

    it "returns true when entry contains text_version_id" do
      expect(described_class.draft_news_sourced?({"text_version_id" => 456, "org_name" => "ACLU"})).to be(true)
      expect(described_class.draft_news_sourced?({text_version_id: 456, org_name: "ACLU"})).to be(true)
    end

    it "returns true when entry contains evidence_excerpt" do
      expect(described_class.draft_news_sourced?({"evidence_excerpt" => "Direct quote", "org_name" => "ACLU"})).to be(true)
      expect(described_class.draft_news_sourced?({evidence_excerpt: "Direct quote", org_name: "ACLU"})).to be(true)
    end

    it "returns false for hearing testimony drafts with no news fields" do
      expect(described_class.draft_news_sourced?({"org_name" => "ACLU", "stance" => "support", "summary" => "Testified"})).to be(false)
      expect(described_class.draft_news_sourced?({org_name: "ACLU", stance: "support", summary: "Testified"})).to be(false)
    end

    it "returns false when news fields are nil or blank" do
      expect(described_class.draft_news_sourced?({"bill_news_article_id" => nil, "text_version_id" => "", "evidence_excerpt" => nil})).to be(false)
    end

    it "returns false for non-Hash elements" do
      expect(described_class.draft_news_sourced?(nil)).to be(false)
      expect(described_class.draft_news_sourced?("not a hash")).to be(false)
      expect(described_class.draft_news_sourced?([1, 2, 3])).to be(false)
      expect(described_class.draft_news_sourced?(123)).to be(false)
    end

    it "is aliased as .news_sourced_draft?" do
      news_entry = {"bill_news_article_id" => 10, "org_name" => "ACME"}
      hearing_entry = {"org_name" => "ACME", "stance" => "support"}
      expect(described_class.news_sourced_draft?(news_entry)).to be(true)
      expect(described_class.news_sourced_draft?(hearing_entry)).to be(false)
    end
  end

  # @lat: [[evidence-retraction#Marking a draft's evidence as retracted#Selective retraction between testimony and news evidence]]
  describe ".drafts_with_evidence_retracted (hearing testimony isolation)" do
    it "stamps hearing drafts but leaves news-sourced drafts untouched" do
      at = Time.utc(2026, 10, 26, 12, 0)
      hearing_draft = {"org_name" => "MD Food Bank", "stance" => "support", "summary" => "Testified"}
      news_draft = {
        "org_name" => "Chamber of Commerce",
        "stance" => "oppose",
        "summary" => "President quoted opposing",
        "bill_news_article_id" => 42,
        "text_version_id" => 10,
        "evidence_excerpt" => "We strongly oppose this measure"
      }

      marked = described_class.drafts_with_evidence_retracted([hearing_draft, news_draft], at: at)

      expect(marked.first[described_class::DRAFT_EVIDENCE_RETRACTED_KEY]).to eq("2026-10-26T12:00:00Z")
      expect(marked.last[described_class::DRAFT_EVIDENCE_RETRACTED_KEY]).to be_nil
      expect(marked.last).to eq(news_draft)
    end

    it "leaves all entries untouched when all drafts are news-sourced" do
      news_drafts = [
        {"org_name" => "Org A", "bill_news_article_id" => 1, "evidence_excerpt" => "Quote 1"},
        {"org_name" => "Org B", "bill_news_article_id" => 2, "evidence_excerpt" => "Quote 2"}
      ]

      marked = described_class.drafts_with_evidence_retracted(news_drafts)
      expect(marked).to eq(news_drafts)
    end
  end

  # @lat: [[evidence-retraction#Marking a draft's evidence as retracted#Selective retraction between testimony and news evidence]]
  describe ".drafts_with_news_evidence_retracted" do
    context "when approval is withdrawn (text_version_id: nil)" do
      it "stamps all news drafts matching bill_news_article_id and leaves other drafts untouched" do
        at = Time.utc(2026, 10, 26, 15, 30)
        hearing_draft = {"org_name" => "Hearing Org", "stance" => "support", "summary" => "Testified at hearing"}
        news_draft_art1_v1 = {
          "org_name" => "News Org 1",
          "stance" => "oppose",
          "summary" => "Quoted in article",
          "bill_news_article_id" => 101,
          "text_version_id" => 1,
          "evidence_excerpt" => "We oppose section 2"
        }
        news_draft_art2_v1 = {
          "org_name" => "News Org 2",
          "stance" => "neutral",
          "summary" => "Different article",
          "bill_news_article_id" => 202,
          "text_version_id" => 1,
          "evidence_excerpt" => "Neutral stance statement"
        }
        raw = [hearing_draft, news_draft_art1_v1, news_draft_art2_v1]
        result = described_class.drafts_with_news_evidence_retracted(
          raw,
          bill_news_article_id: 101,
          text_version_id: nil,
          at: at
        )

        expect(result[0][described_class::DRAFT_EVIDENCE_RETRACTED_KEY]).to be_nil
        expect(result[1][described_class::DRAFT_EVIDENCE_RETRACTED_KEY]).to eq("2026-10-26T15:30:00Z")
        expect(result[2][described_class::DRAFT_EVIDENCE_RETRACTED_KEY]).to be_nil
      end
    end

    context "when article text version changes (text_version_id provided)" do
      it "stamps matching news drafts whose text_version_id differs from the active version" do
        at = Time.utc(2026, 10, 26, 15, 30)
        hearing_draft = {"org_name" => "Hearing Org", "stance" => "support", "summary" => "Testified at hearing"}
        news_draft_art1_v1 = {
          "org_name" => "News Org 1",
          "stance" => "oppose",
          "summary" => "Quoted in article",
          "bill_news_article_id" => 101,
          "text_version_id" => 1,
          "evidence_excerpt" => "We oppose section 2"
        }
        news_draft_art1_v2 = {
          "org_name" => "News Org 1 Updated",
          "stance" => "support",
          "summary" => "Quoted in version 2",
          "bill_news_article_id" => 101,
          "text_version_id" => 2,
          "evidence_excerpt" => "We now support section 2"
        }
        news_draft_art2_v1 = {
          "org_name" => "News Org 2",
          "stance" => "neutral",
          "summary" => "Different article",
          "bill_news_article_id" => 202,
          "text_version_id" => 1,
          "evidence_excerpt" => "Neutral stance statement"
        }
        raw = [hearing_draft, news_draft_art1_v1, news_draft_art1_v2, news_draft_art2_v1]
        result = described_class.drafts_with_news_evidence_retracted(
          raw,
          bill_news_article_id: 101,
          text_version_id: 2,
          at: at
        )

        expect(result[0][described_class::DRAFT_EVIDENCE_RETRACTED_KEY]).to be_nil
        expect(result[1][described_class::DRAFT_EVIDENCE_RETRACTED_KEY]).to eq("2026-10-26T15:30:00Z")
        expect(result[2][described_class::DRAFT_EVIDENCE_RETRACTED_KEY]).to be_nil
        expect(result[3][described_class::DRAFT_EVIDENCE_RETRACTED_KEY]).to be_nil
      end

      it "handles integer and string representation equivalence for IDs" do
        at = Time.utc(2026, 10, 26, 15, 30)
        news_draft_art1_v1 = {
          "org_name" => "News Org 1",
          "stance" => "oppose",
          "summary" => "Quoted in article",
          "bill_news_article_id" => 101,
          "text_version_id" => 1,
          "evidence_excerpt" => "We oppose section 2"
        }
        raw = [news_draft_art1_v1]
        result = described_class.drafts_with_news_evidence_retracted(
          raw,
          bill_news_article_id: "101",
          text_version_id: "1",
          at: at
        )

        expect(result[0][described_class::DRAFT_EVIDENCE_RETRACTED_KEY]).to be_nil
      end
    end

    context "preservation of existing retraction timestamps" do
      it "keeps the original evidence_retracted_at timestamp when already marked" do
        at = Time.utc(2026, 10, 26, 15, 30)
        news_draft_art1_v1 = {
          "org_name" => "News Org 1",
          "stance" => "oppose",
          "summary" => "Quoted in article",
          "bill_news_article_id" => 101,
          "text_version_id" => 1,
          "evidence_excerpt" => "We oppose section 2"
        }
        prior_time = "2026-07-01T10:00:00Z"
        already_retracted = news_draft_art1_v1.merge(
          described_class::DRAFT_EVIDENCE_RETRACTED_KEY => prior_time
        )

        result = described_class.drafts_with_news_evidence_retracted(
          [already_retracted],
          bill_news_article_id: 101,
          text_version_id: nil,
          at: at
        )

        expect(result.first[described_class::DRAFT_EVIDENCE_RETRACTED_KEY]).to eq(prior_time)
      end
    end

    context "edge cases and input tolerance" do
      it "passes nil and non-Array raw values through untouched" do
        expect(described_class.drafts_with_news_evidence_retracted(nil, bill_news_article_id: 101)).to be_nil
        expect(described_class.drafts_with_news_evidence_retracted("not-an-array", bill_news_article_id: 101)).to eq("not-an-array")
      end

      it "passes non-Hash entries through untouched" do
        at = Time.utc(2026, 10, 26, 15, 30)
        news_draft_art1_v1 = {
          "org_name" => "News Org 1",
          "stance" => "oppose",
          "summary" => "Quoted in article",
          "bill_news_article_id" => 101,
          "text_version_id" => 1,
          "evidence_excerpt" => "We oppose section 2"
        }
        raw = ["string-entry", 123, news_draft_art1_v1]
        result = described_class.drafts_with_news_evidence_retracted(raw, bill_news_article_id: 101, at: at)

        expect(result[0]).to eq("string-entry")
        expect(result[1]).to eq(123)
        expect(result[2][described_class::DRAFT_EVIDENCE_RETRACTED_KEY]).to eq("2026-10-26T15:30:00Z")
      end

      it "does nothing if bill_news_article_id is blank" do
        news_draft_art1_v1 = {
          "org_name" => "News Org 1",
          "stance" => "oppose",
          "summary" => "Quoted in article",
          "bill_news_article_id" => 101,
          "text_version_id" => 1,
          "evidence_excerpt" => "We oppose section 2"
        }
        raw = [news_draft_art1_v1]
        expect(described_class.drafts_with_news_evidence_retracted(raw, bill_news_article_id: nil)).to eq(raw)
        expect(described_class.drafts_with_news_evidence_retracted(raw, bill_news_article_id: "")).to eq(raw)
      end

      it "supports entries with symbol keys" do
        at = Time.utc(2026, 10, 26, 15, 30)
        sym_entry = {
          org_name: "Sym Org",
          stance: "support",
          bill_news_article_id: 101,
          text_version_id: 1,
          evidence_excerpt: "Symbol quote"
        }

        result = described_class.drafts_with_news_evidence_retracted(
          [sym_entry],
          bill_news_article_id: 101,
          text_version_id: nil,
          at: at
        )

        expect(result.first[described_class::DRAFT_EVIDENCE_RETRACTED_KEY]).to eq("2026-10-26T15:30:00Z")
      end
    end
  end

  describe "campaign draft status management" do
    let(:bill) { create(:bill) }
    let(:provisioning) { create(:bill_llm_provisioning, bill: bill) }

    describe "#individual_campaign_draft_hash_list" do
      it "returns empty array when individual_campaign_draft_hashes is nil" do
        provisioning.update!(individual_campaign_draft_hashes: nil)
        expect(provisioning.individual_campaign_draft_hash_list).to eq([])
      end

      it "returns string elements" do
        provisioning.update!(individual_campaign_draft_hashes: ["hash1", 123])
        expect(provisioning.individual_campaign_draft_hash_list).to eq(["hash1", "123"])
      end
    end

    # @lat: [[campaign-draft-rejection#Releasing drafts to individual letters]]
    describe "#mark_campaign_draft_individual!" do
      it "returns false on blank content hash without mutating" do
        expect(provisioning.mark_campaign_draft_individual!("")).to be(false)
        expect(provisioning.mark_campaign_draft_individual!("   ")).to be(false)
        expect(provisioning.mark_campaign_draft_individual!(nil)).to be(false)
      end

      it "adds the content hash to individual_campaign_draft_hashes" do
        expect(provisioning.mark_campaign_draft_individual!("grp1")).to be(true)
        expect(provisioning.reload.individual_campaign_draft_hash_list).to eq(["grp1"])
      end

      it "is idempotent and returns false if already individual" do
        expect(provisioning.mark_campaign_draft_individual!("grp1")).to be(true)
        expect(provisioning.mark_campaign_draft_individual!("grp1")).to be(false)
        expect(provisioning.reload.individual_campaign_draft_hash_list).to eq(["grp1"])
      end

      it "removes content hash from rejected_campaign_draft_hashes when marking individual (mutual exclusivity)" do
        provisioning.reject_campaign_draft!("grp1")
        expect(provisioning.rejected_campaign_draft_hash_list).to eq(["grp1"])

        expect(provisioning.mark_campaign_draft_individual!("grp1")).to be(true)
        provisioning.reload
        expect(provisioning.individual_campaign_draft_hash_list).to eq(["grp1"])
        expect(provisioning.rejected_campaign_draft_hash_list).to eq([])
      end
    end

    describe "#reject_campaign_draft!" do
      it "returns false on blank content hash without mutating" do
        expect(provisioning.reject_campaign_draft!("")).to be(false)
        expect(provisioning.reject_campaign_draft!("   ")).to be(false)
        expect(provisioning.reject_campaign_draft!(nil)).to be(false)
      end

      it "adds the content hash to rejected_campaign_draft_hashes" do
        expect(provisioning.reject_campaign_draft!("grp1")).to be(true)
        expect(provisioning.reload.rejected_campaign_draft_hash_list).to eq(["grp1"])
      end

      it "is idempotent and returns false if already rejected" do
        expect(provisioning.reject_campaign_draft!("grp1")).to be(true)
        expect(provisioning.reject_campaign_draft!("grp1")).to be(false)
        expect(provisioning.reload.rejected_campaign_draft_hash_list).to eq(["grp1"])
      end

      it "removes content hash from individual_campaign_draft_hashes when rejecting (mutual exclusivity)" do
        provisioning.mark_campaign_draft_individual!("grp1")
        expect(provisioning.individual_campaign_draft_hash_list).to eq(["grp1"])

        expect(provisioning.reject_campaign_draft!("grp1")).to be(true)
        provisioning.reload
        expect(provisioning.rejected_campaign_draft_hash_list).to eq(["grp1"])
        expect(provisioning.individual_campaign_draft_hash_list).to eq([])
      end
    end

    describe "#restore_campaign_draft!" do
      it "returns false on blank content hash without mutating" do
        expect(provisioning.restore_campaign_draft!("")).to be(false)
        expect(provisioning.restore_campaign_draft!("   ")).to be(false)
        expect(provisioning.restore_campaign_draft!(nil)).to be(false)
      end

      it "returns false if content hash was in neither list" do
        expect(provisioning.restore_campaign_draft!("grp1")).to be(false)
      end

      it "removes content hash from rejected_campaign_draft_hashes" do
        provisioning.reject_campaign_draft!("grp1")
        expect(provisioning.restore_campaign_draft!("grp1")).to be(true)
        expect(provisioning.reload.rejected_campaign_draft_hash_list).to eq([])
      end

      it "removes content hash from individual_campaign_draft_hashes" do
        provisioning.mark_campaign_draft_individual!("grp1")
        expect(provisioning.restore_campaign_draft!("grp1")).to be(true)
        expect(provisioning.reload.individual_campaign_draft_hash_list).to eq([])
      end

      it "clears the content hash from both lists if present in both" do
        provisioning.update!(
          rejected_campaign_draft_hashes: ["grp1", "grp2"],
          individual_campaign_draft_hashes: ["grp1", "grp3"]
        )
        expect(provisioning.restore_campaign_draft!("grp1")).to be(true)
        provisioning.reload
        expect(provisioning.rejected_campaign_draft_hash_list).to eq(["grp2"])
        expect(provisioning.individual_campaign_draft_hash_list).to eq(["grp3"])
      end
    end
  end
end
