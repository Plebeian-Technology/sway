# frozen_string_literal: true

require "rails_helper"

# Unit tests for the parse/validate/save logic pulled out of
# BillsController#paste_summary. The request spec covers HTTP; these pin
# what the service returns and changes.
RSpec.describe PasteSummaryService do
  # Each example writes its own schema-valid summary body matching
  # bill_summary.json, instead of a shared helper def — Steep types the
  # group body as a plain object and can't resolve one.
  it "persists accepted output and returns [:persisted, []]" do
    bill = create(:bill)
    summary_json = {
      summary_markdown: "## Summary\nConcise overview.",
      full_breakdown_markdown: "## Full\nDetailed breakdown.",
      draft_org_positions: [] #: Array[untyped]
    }.to_json

    outcome, errors = described_class.new(
      bill: bill, actor: create(:user), summary_json: summary_json
    ).call

    expect(outcome).to eq(:persisted)
    expect(errors).to eq([])
    provisioning = bill.reload.bill_llm_provisioning #: BillLlmProvisioning
    expect(provisioning.llm_summary).to eq("## Summary\nConcise overview.")
    expect(provisioning.llm_provider).to eq("operator_paste")
    expect(provisioning.llm_generated_at).to be_present
  end

  # A paste replaces the summary BODY, so every column DESCRIBING it must
  # change too. llm_model didn't: a Claude row later hand-pasted showed
  # operator_paste beside claude-sonnet.
  it "clears the prior run's llm_model — an operator paste ran no model" do
    bill = create(:bill)
    create(
      :bill_llm_provisioning, :completed,
      bill: bill, llm_provider: "anthropic", llm_model: "claude-sonnet-4-6"
    )

    described_class.new(
      bill: bill, actor: create(:user), summary_json: {summary_markdown: "## Pasted"}.to_json
    ).call

    provisioning = bill.reload.bill_llm_provisioning #: BillLlmProvisioning
    expect(provisioning.llm_provider).to eq("operator_paste")
    expect(provisioning.llm_model).to be_nil
  end

  it "captures public baseline and legacy model draft before appending pasted draft" do
    bill = create(:bill, summary: "Human public summary A")
    create(
      :bill_llm_provisioning, :completed,
      bill: bill,
      llm_summary: "Legacy model draft B",
      llm_provider: "claude",
      llm_model: "claude-3-5-sonnet"
    )
    expect(bill.bill_summary_revisions.count).to eq(0)

    described_class.new(
      bill: bill, actor: create(:user), summary_json: {summary_markdown: "## Pasted draft C"}.to_json
    ).call

    revisions = bill.bill_summary_revisions.order(:id)
    expect(revisions.count).to eq(3)

    expect(revisions.first.summary_markdown).to eq("Human public summary A")
    expect(revisions.first.origin).to eq("initial_baseline")
    expect(revisions.first.publication_role).to eq("published")

    expect(revisions.second.summary_markdown).to eq("Legacy model draft B")
    expect(revisions.second.origin).to eq("model_generation")
    expect(revisions.second.publication_role).to eq("draft")
    expect(revisions.second.llm_model).to eq("claude-3-5-sonnet")

    expect(revisions.third.summary_markdown).to eq("## Pasted draft C")
    expect(revisions.third.origin).to eq("operator_paste")
    expect(revisions.third.publication_role).to eq("draft")
  end

  it "logs a paste_summary_accepted audit entry on success" do
    bill = create(:bill)
    summary_json = {
      summary_markdown: "## Summary",
      full_breakdown_markdown: "## Full",
      draft_org_positions: [] #: Array[untyped]
    }.to_json

    expect {
      described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call
    }.to change(PipelineActivityLogEntry, :count).by(1)

    entry = PipelineActivityLogEntry.order(created_at: :desc).first #: PipelineActivityLogEntry
    expect(entry.event_type).to eq("paste_summary_accepted")
  end

  it "returns [:invalid_json, errors] and logs a rejection when the body is not JSON" do
    bill = create(:bill)

    expect {
      outcome, errors = described_class.new(
        bill: bill, actor: create(:user), summary_json: "not json{"
      ).call
      expect(outcome).to eq(:invalid_json)
      expect(errors.first[:path]).to eq("/")
      expect(errors.first[:message]).to start_with("Invalid JSON:")
    }.to change(PipelineActivityLogEntry, :count).by(1)

    expect(bill.reload.bill_llm_provisioning).to be_nil
  end

  it "returns [:schema_invalid, errors] when the JSON fails schema validation" do
    bill = create(:bill)

    outcome, errors = described_class.new(
      bill: bill, actor: create(:user), summary_json: {wrong_key: "x"}.to_json
    ).call

    expect(outcome).to eq(:schema_invalid)
    expect(errors).not_to be_empty
    expect(bill.reload.bill_llm_provisioning).to be_nil
  end

  # LlmSummaryCitationWarning reads citation columns directly.
  # GenerateBillSummaryJob was the only writer, so a paste left the
  # PREVIOUS verdict behind — false all-clear or a stale alarm.
  describe "citation verdict on paste (C-CR-02)" do
    it "revalidates cited_section_keys against the bill's parsed sections" do
      bill = create(:bill)
      create(:bill_section_reference, bill: bill, key: "art_14__sec_301")

      summary_json = {
        summary_markdown: "## Summary",
        full_breakdown_markdown: "## Full",
        cited_section_keys: ["art_14__sec_301", "art_99__sec_1"]
      }.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      provisioning = bill.reload.bill_llm_provisioning #: BillLlmProvisioning
      expect(provisioning.citations_valid).to be(false)
      expect(provisioning.invalid_citations).to eq(["art_99__sec_1"])
    end

    it "records a clean verdict when every cited key resolves" do
      bill = create(:bill)
      create(:bill_section_reference, bill: bill, key: "art_14__sec_301")
      bill.create_bill_llm_provisioning!(citations_valid: false, invalid_citations: ["art_1__sec_1"])

      summary_json = {
        summary_markdown: "## Summary",
        full_breakdown_markdown: "## Full",
        cited_section_keys: ["art_14__sec_301"]
      }.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      provisioning = bill.reload.bill_llm_provisioning #: BillLlmProvisioning
      expect(provisioning.citations_valid).to be(true)
      expect(provisioning.invalid_citations).to eq([])
    end

    it "clears a stale prior verdict to 'not validated' when the paste omits cited_section_keys" do
      # The risky direction: a previously clean row must not keep claiming
      # citations verified for an unchecked summary, and a previously failed
      # row must not keep naming a key the paste dropped.
      bill = create(:bill)
      bill.create_bill_llm_provisioning!(citations_valid: false, invalid_citations: ["art_14__sec_301"])

      summary_json = {
        summary_markdown: "## Summary",
        full_breakdown_markdown: "## Full"
      }.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      provisioning = bill.reload.bill_llm_provisioning #: BillLlmProvisioning
      expect(provisioning.citations_valid).to be_nil
      expect(provisioning.invalid_citations).to be_nil
    end

    # This service and GenerateBillSummaryJob write citations_valid and
    # meant OPPOSITE things when cited_section_keys was missing. They now
    # share ONE entry point so they can't drift apart again.
    it "derives the verdict through the same entry point GenerateBillSummaryJob uses" do
      bill = create(:bill)
      allow(SummaryCitationValidator).to receive(:verdict_attrs).and_call_original

      body = {summary_markdown: "## Summary", cited_section_keys: ["art_14__sec_301"]}

      described_class.new(bill: bill, actor: create(:user), summary_json: body.to_json).call

      expect(SummaryCitationValidator).to have_received(:verdict_attrs)
        .with(bill: bill, payload: hash_including("cited_section_keys" => ["art_14__sec_301"]))
    end

    it "persists news_urls_valid and invalid_news_urls from pasted payload" do
      bill = create(:bill)
      news_url = "https://www.thebaltimorebanner.com/story-1"
      bill.create_bill_llm_provisioning!(
        news_articles: [{"url" => news_url, "title" => "Banner story", "cited_text" => "snippet"}]
      )

      valid_json = {
        summary_markdown: "## Summary with [Banner](#{news_url})",
        cited_news_urls: [news_url]
      }.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: valid_json).call

      provisioning = bill.reload.bill_llm_provisioning #: BillLlmProvisioning
      expect(provisioning.news_urls_valid).to be(true)
      expect(provisioning.invalid_news_urls).to eq([])

      unlisted_json = {
        summary_markdown: "## Summary with [Other](https://unlisted.org/story)",
        cited_news_urls: ["https://unlisted.org/story"]
      }.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: unlisted_json).call

      provisioning.reload
      expect(provisioning.news_urls_valid).to be(false)
      expect(provisioning.invalid_news_urls).to eq(["https://unlisted.org/story"])
    end
  end

  # Categories included in the pasted payload.
  describe "categories in pasted payload (WR-04)" do
    it "assigns matching active categories when pasted body includes a non-empty categories array" do
      bill = create(:bill)
      cat_health = create(:category, name: "Health", active: true)
      _cat_inactive = create(:category, name: "Archived", active: false)

      summary_json = {
        summary_markdown: "## Summary\nConcise overview.",
        full_breakdown_markdown: "## Full\nDetailed breakdown.",
        draft_org_positions: [], #: Array[untyped]
        categories: ["Health"]
      }.to_json

      outcome, errors = described_class.new(
        bill: bill, actor: create(:user), summary_json: summary_json
      ).call

      expect(outcome).to eq(:persisted)
      expect(errors).to eq([])
      expect(bill.reload.categories).to include(cat_health)
    end

    it "succeeds and assigns no categories when pasted body omits the categories key" do
      bill = create(:bill)
      create(:category, name: "Health", active: true)

      summary_json = {
        summary_markdown: "## Summary",
        full_breakdown_markdown: "## Full",
        draft_org_positions: [] #: Array[untyped]
      }.to_json

      outcome, errors = described_class.new(
        bill: bill, actor: create(:user), summary_json: summary_json
      ).call

      expect(outcome).to eq(:persisted)
      expect(errors).to eq([])
      expect(bill.reload.categories.count).to eq(0)
    end

    it "succeeds and assigns no categories when pasted body has an empty categories array" do
      bill = create(:bill)
      create(:category, name: "Health", active: true)

      summary_json = {
        summary_markdown: "## Summary",
        full_breakdown_markdown: "## Full",
        draft_org_positions: [], #: Array[untyped]
        categories: []
      }.to_json

      outcome, errors = described_class.new(
        bill: bill, actor: create(:user), summary_json: summary_json
      ).call

      expect(outcome).to eq(:persisted)
      expect(errors).to eq([])
      expect(bill.reload.categories.count).to eq(0)
    end

    # The example above pastes an empty array onto a bill with NO
    # categories, so it can't tell cleared from never had any. This gives
    # it a category first.
    it "leaves categories already on the bill alone, and says the empty list did nothing" do
      bill = create(:bill)
      cat_health = create(:category, name: "Health", active: true)
      BillCategory.create!(bill: bill, category: cat_health)
      allow(SwayLogging).to receive(:warn)

      summary_json = {
        summary_markdown: "## Summary",
        full_breakdown_markdown: "## Full",
        draft_org_positions: [], #: Array[untyped]
        categories: []
      }.to_json

      outcome, errors = described_class.new(
        bill: bill, actor: create(:user), summary_json: summary_json
      ).call

      expect(outcome).to eq(:persisted)
      expect(errors).to eq([])
      expect(bill.reload.categories).to include(cat_health)
      expect(SwayLogging).to have_received(:warn).with(
        "paste_summary.empty_categories_ignored", hash_including(bill_id: bill.id)
      )
    end

    # A paste must never fail over category names was enforced for one
    # error class. BillCategoryAssigner also raises three other errors,
    # none rescued — a 500 over a summary already live on the bill.
    it "still accepts the paste when the category write hits a locked database" do
      bill = create(:bill)
      create(:category, name: "Health", active: true)
      allow(SwayLogging).to receive(:warn)
      allow_any_instance_of(BillCategoryAssigner).to receive(:call)
        .and_raise(ActiveRecord::LockWaitTimeout.new("database is locked"))

      summary_json = {
        summary_markdown: "## Summary",
        full_breakdown_markdown: "## Full",
        draft_org_positions: [], #: Array[untyped]
        categories: ["Health"]
      }.to_json

      outcome, errors = described_class.new(
        bill: bill, actor: create(:user), summary_json: summary_json
      ).call

      expect(outcome).to eq(:persisted)
      expect(errors).to eq([])
      expect(PipelineActivityLogEntry.where(event_type: "paste_summary_accepted").count).to eq(1)
      expect(SwayLogging).to have_received(:warn).with(
        "paste_summary.categories_assignment_failed",
        hash_including(bill_id: bill.id, error_class: "ActiveRecord::LockWaitTimeout")
      )
    end

    # The rule applied one statement later: the audit write was the last
    # unguarded post-commit write. A BusyException there told the operator
    # the paste failed over a summary that WAS live (A20-03).
    it "leaves nothing live on the bill when the audit entry cannot be written" do
      bill = create(:bill)
      allow(PipelineActivityLogger).to receive(:log_paste_summary_accepted!)
        .and_raise(ActiveRecord::LockWaitTimeout.new("database is locked"))

      summary_json = {
        summary_markdown: "## Summary",
        full_breakdown_markdown: "## Full",
        draft_org_positions: [] #: Array[untyped]
      }.to_json

      expect {
        described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call
      }.to raise_error(ActiveRecord::LockWaitTimeout)

      provisioning = bill.reload.bill_llm_provisioning
      expect(provisioning&.llm_summary).to be_nil
      expect(provisioning&.generation_status).to be_nil
      expect(PipelineActivityLogEntry.where(event_type: "paste_summary_accepted").count).to eq(0)
    end

    # B21-03/B22-05: the statement A20-03 skipped: settle_pasted_row! runs
    # right after commit, unrescued. A retry now guarantees a duplicate
    # audit entry.
    it "accepts the paste when settling the row hits a locked database, and says it is unsettled" do
      bill = create(:bill)
      allow(SwayLogging).to receive(:warn)
      # Fail the SETTLE step by name, not the with_lock mechanism it shares
      # with the pasted-body write — stubbing the mechanism failed whichever
      # step reached it first, losing the point of the example.
      allow_any_instance_of(described_class).to receive(:settle_pasted_row!)
        .and_raise(ActiveRecord::LockWaitTimeout.new("database is locked"))

      summary_json = {
        summary_markdown: "## Summary",
        full_breakdown_markdown: "## Full",
        draft_org_positions: [] #: Array[untyped]
      }.to_json

      outcome, errors = described_class.new(
        bill: bill, actor: create(:user), summary_json: summary_json
      ).call

      expect(outcome).to eq(:persisted_unsettled)
      expect(errors).to eq([])
      expect(bill.reload.bill_llm_provisioning&.llm_summary).to eq("## Summary")
      expect(PipelineActivityLogEntry.where(event_type: "paste_summary_accepted").count).to eq(1)
      expect(SwayLogging).to have_received(:warn).with(
        "paste_summary.settle_failed",
        hash_including(bill_id: bill.id, error_class: "ActiveRecord::LockWaitTimeout")
      )
    end

    # The case the finding calls worst: a failure is exactly WHY someone
    # pastes, and the completed view draws the REAL badge over a terminal
    # row — a red Failed over saved text (B22-05).
    it "says so when the settle fails on a failed row, the case an operator pastes onto" do
      bill = create(:bill)
      provisioning = create(
        :bill_llm_provisioning, bill: bill,
        generation_status: "failed", generation_error: "claude transport: 429"
      )
      allow(SwayLogging).to receive(:warn)
      # Same reason as the settle-failure example above: fail the SETTLE step
      # by name, not the with_lock mechanism it shares with the pasted-body write.
      allow_any_instance_of(described_class).to receive(:settle_pasted_row!)
        .and_raise(ActiveRecord::LockWaitTimeout.new("database is locked"))

      outcome, = described_class.new(
        bill: bill, actor: create(:user),
        summary_json: {summary_markdown: "## Written by hand after the failure"}.to_json
      ).call

      expect(outcome).to eq(:persisted_unsettled)
      expect(provisioning.reload.llm_summary).to eq("## Written by hand after the failure")
      expect(provisioning.generation_status).to eq("failed")
    end

    # The other side, so the warning can't widen into every rescued
    # settle. A row still in flight is DELIBERATELY left alone
    # (settle_pasted_row!'s ordinary branch), not a status nobody will move.
    it "reports a plain success when the row a job still owns cannot be settled" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :generating, bill: bill)
      allow(SwayLogging).to receive(:warn)
      # Same reason as the settle-failure example above: fail the SETTLE step
      # by name, not the with_lock mechanism it shares with the pasted-body write.
      allow_any_instance_of(described_class).to receive(:settle_pasted_row!)
        .and_raise(ActiveRecord::LockWaitTimeout.new("database is locked"))

      outcome, = described_class.new(
        bill: bill, actor: create(:user),
        summary_json: {summary_markdown: "## Written by hand mid-run"}.to_json
      ).call

      expect(outcome).to eq(:persisted)
    end

    it "succeeds (returns :persisted) even when pasted categories have no active-set match" do
      bill = create(:bill)
      create(:category, name: "Health", active: true)
      allow(SwayLogging).to receive(:warn)

      summary_json = {
        summary_markdown: "## Summary",
        full_breakdown_markdown: "## Full",
        draft_org_positions: [], #: Array[untyped]
        categories: ["UnknownCategory"]
      }.to_json

      outcome, errors = described_class.new(
        bill: bill, actor: create(:user), summary_json: summary_json
      ).call

      expect(outcome).to eq(:persisted)
      expect(errors).to eq([])
      expect(bill.reload.categories.count).to eq(0)
    end
  end

  # Only TWO places ADD a draft org position: the job's gated positions
  # call, and this service, which used to take any pasted array as-is — an
  # ungated path to a stance drawn from bill text.
  describe "draft_org_positions testimony gate (B4-CR-01 / REAS-01)" do
    it "ignores a non-empty pasted draft_org_positions when the bill has no testimony" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, extracted_testimony: nil, supplemental_testimony: nil)
      allow(SwayLogging).to receive(:warn)

      summary_json = {
        summary_markdown: "## Summary",
        full_breakdown_markdown: "## Full",
        draft_org_positions: [
          {org_name: "ACLU", stance: "support", summary: "Derived from the bill text, not testimony."}
        ]
      }.to_json

      outcome, errors = described_class.new(
        bill: bill, actor: create(:user), summary_json: summary_json
      ).call

      expect(outcome).to eq(:persisted)
      expect(errors).to eq([])
      provisioning = bill.reload.bill_llm_provisioning #: BillLlmProvisioning
      expect(provisioning.llm_summary).to eq("## Summary")
      expect(provisioning.draft_org_positions).to be_nil
    end

    it "logs the ignored positions so the operator paste is not silently dropped" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, extracted_testimony: nil, supplemental_testimony: nil)
      allow(SwayLogging).to receive(:warn)

      summary_json = {
        summary_markdown: "## Summary",
        draft_org_positions: [
          {org_name: "ACLU", stance: "support", summary: "Derived from the bill text."}
        ]
      }.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      expect(SwayLogging).to have_received(:warn).with(
        "paste_summary.positions_ignored_no_testimony", hash_including(bill_id: bill.id)
      )
    end

    it "does NOT clobber operator-curated drafts when the gate rejects the pasted array" do
      bill = create(:bill)
      curated = [{"org_name" => "Maryland Tenants Union", "stance" => "support", "summary" => "Triaged."}]
      create(
        :bill_llm_provisioning,
        bill: bill,
        draft_org_positions: curated,
        extracted_testimony: nil,
        supplemental_testimony: nil
      )
      allow(SwayLogging).to receive(:warn)

      summary_json = {
        summary_markdown: "## Summary",
        draft_org_positions: [
          {org_name: "ACLU", stance: "oppose", summary: "Ungrounded."}
        ]
      }.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      expect(bill.reload.bill_llm_provisioning&.draft_org_positions).to eq(curated)
    end

    it "persists pasted positions when extracted_testimony is present" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, extracted_testimony: "Testimony of the Maryland Tenants Union...")

      summary_json = {
        summary_markdown: "## Summary",
        draft_org_positions: [
          {org_name: "ACLU", stance: "support", summary: "Spoke in favor at the hearing."}
        ]
      }.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      provisioning = bill.reload.bill_llm_provisioning #: BillLlmProvisioning
      expect(provisioning.draft_org_positions&.length).to eq(1)
    end

    it "persists pasted positions when only supplemental_testimony is present" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, supplemental_testimony: "Operator-pasted hearing testimony.")

      summary_json = {
        summary_markdown: "## Summary",
        draft_org_positions: [
          {org_name: "ACLU", stance: "support", summary: "Spoke in favor at the hearing."}
        ]
      }.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      provisioning = bill.reload.bill_llm_provisioning #: BillLlmProvisioning
      expect(provisioning.draft_org_positions&.length).to eq(1)
    end

    it "still honors an explicit empty-array clear on a testimony-less bill" do
      # An empty array claims nothing about any organization, so there is no
      # risk in honoring it — and it is the operator's only way to retire drafts
      # that an older run had derived from the bill text.
      bill = create(:bill)
      create(
        :bill_llm_provisioning,
        bill: bill,
        draft_org_positions: [{"org_name" => "ACLU", "stance" => "support", "summary" => "Stale."}],
        extracted_testimony: nil,
        supplemental_testimony: nil
      )

      summary_json = {
        summary_markdown: "## Summary",
        draft_org_positions: [] #: Array[untyped]
      }.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      expect(bill.reload.bill_llm_provisioning&.draft_org_positions).to eq([])
    end

    it "persists grounded news-sourced positions without hearing testimony when backing reporting is approved" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, extracted_testimony: nil, supplemental_testimony: nil)
      news_article = create(:news_article, outlet_name: "The Baltimore Banner", title: "Housing Story", canonical_url: "https://example.com/housing")
      article_text = "Jane Doe, executive director of the Baltimore Tenants Union, said: \"We need this protection now.\""
      text_version = create(:news_article_text_version, :extracted, news_article: news_article, text: article_text)
      bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)

      NewsArticleSourceSnapshotService.capture!(
        bill: bill,
        purpose: "summary",
        run_receipt: "test_receipt",
        sources: [bna]
      )

      summary_json = {
        summary_markdown: "## Summary",
        draft_org_positions: [
          {
            org_name: "Baltimore Tenants Union",
            stance: "support",
            summary: "Initial",
            bill_news_article_id: bna.id,
            text_version_id: text_version.id,
            evidence_excerpt: "said: \"We need this protection now.\"",
            speaker_name: "Jane Doe",
            speaker_role: "executive director"
          }
        ]
      }.to_json

      initial_org_count = Organization.count
      initial_pos_count = OrganizationBillPosition.count

      outcome, errors = described_class.new(
        bill: bill, actor: create(:user), summary_json: summary_json
      ).call

      expect(outcome).to eq(:persisted)
      expect(errors).to eq([])
      expect(Organization.count).to eq(initial_org_count)
      expect(OrganizationBillPosition.count).to eq(initial_pos_count)

      drafts = bill.reload.bill_llm_provisioning&.draft_org_positions
      expect(drafts).to be_present
      expect(drafts.length).to eq(1)
      first_draft = drafts.first
      expect(first_draft["org_name"]).to eq("Baltimore Tenants Union")
      expect(first_draft["source_url"]).to eq("https://example.com/housing")
      expect(first_draft["summary"]).to include("\"We need this protection now.\"")
    end

    it "drops ungrounded news-sourced positions on paste and preserves existing curated drafts" do
      bill = create(:bill)
      curated = [{"org_name" => "Curated Org", "stance" => "support", "summary" => "Triaged."}]
      create(
        :bill_llm_provisioning,
        bill: bill,
        draft_org_positions: curated,
        extracted_testimony: nil,
        supplemental_testimony: nil
      )
      news_article = create(:news_article, outlet_name: "The Baltimore Banner", title: "Housing Story")
      text_version = create(:news_article_text_version, :extracted, news_article: news_article, text: "Some article text without the quote.")
      bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)

      NewsArticleSourceSnapshotService.capture!(
        bill: bill,
        purpose: "summary",
        run_receipt: "test_receipt",
        sources: [bna]
      )
      allow(SwayLogging).to receive(:warn)

      summary_json = {
        summary_markdown: "## Summary",
        draft_org_positions: [
          {
            org_name: "Baltimore Tenants Union",
            stance: "support",
            summary: "Initial",
            bill_news_article_id: bna.id,
            text_version_id: text_version.id,
            evidence_excerpt: "said: \"Quote not in article text.\"",
            speaker_name: "Jane Doe",
            speaker_role: "executive director"
          }
        ]
      }.to_json

      outcome, errors = described_class.new(
        bill: bill, actor: create(:user), summary_json: summary_json
      ).call

      expect(outcome).to eq(:persisted)
      expect(errors).to eq([])
      expect(bill.reload.bill_llm_provisioning&.draft_org_positions).to eq(curated)
      expect(SwayLogging).to have_received(:warn).with(
        "paste_summary.positions_ignored_no_testimony", hash_including(bill_id: bill.id)
      )
    end
  end

  # @lat: [[hearing-testimony-census#The marks live on each draft, not on the bill]]
  describe "preserving evidence_retracted_at across a wholesale replace" do
    it "carries a stored mark forward onto a pasted entry with the same content" do
      bill = create(:bill)
      retracted_at = 2.days.ago.utc.iso8601
      create(
        :bill_llm_provisioning,
        bill: bill,
        extracted_testimony: "Testimony of the Maryland Tenants Union...",
        draft_org_positions: [
          {
            "org_name" => "Maryland Tenants Union",
            "stance" => "support",
            "summary" => "Spoke in favor at the hearing.",
            "evidence_retracted_at" => retracted_at
          }
        ]
      )

      # A pasted body never carries evidence_retracted_at — an internal fact
      # the operator's source text couldn't know — so an ordinary
      # paste-back-the-same-JSON looks exactly like this.
      summary_json = {
        summary_markdown: "## Summary",
        draft_org_positions: [
          {org_name: "Maryland Tenants Union", stance: "support", summary: "Spoke in favor at the hearing."}
        ]
      }.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      drafts = bill.reload.bill_llm_provisioning&.draft_org_positions
      expect(drafts&.length).to eq(1)
      expect(drafts&.first&.fetch("evidence_retracted_at")).to eq(retracted_at)
    end

    # The example above proves marks carry forward; this asks WHICH list
    # they carry forward FROM. A change between load and write was
    # invisible, since the merge read the copy loaded at start.
    it "carries marks forward from the list as it stands at the WRITE, not as it stood at the read" do
      bill = create(:bill)
      provisioning = create(
        :bill_llm_provisioning,
        bill: bill,
        extracted_testimony: "Testimony of the Maryland Tenants Union...",
        draft_org_positions: [
          {
            "org_name" => "Maryland Tenants Union",
            "stance" => "support",
            "summary" => "Spoke in favor at the hearing."
          }
        ]
      )
      retracted_at = 1.hour.ago.utc.iso8601

      allow(SummaryCitationValidator).to receive(:verdict_attrs).and_wrap_original do |original, **kwargs|
        # The array, not its JSON: draft_org_positions is serialized, and
        # update_all runs a string through that serializer a SECOND time —
        # a shape no writer here produces.
        BillLlmProvisioning.where(id: provisioning.id).update_all(
          draft_org_positions: [
            {
              "org_name" => "Maryland Tenants Union",
              "stance" => "support",
              "summary" => "Spoke in favor at the hearing.",
              "evidence_retracted_at" => retracted_at
            }
          ]
        )
        original.call(**kwargs)
      end

      summary_json = {
        summary_markdown: "## Summary",
        draft_org_positions: [
          {org_name: "Maryland Tenants Union", stance: "support", summary: "Spoke in favor at the hearing."}
        ]
      }.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      drafts = bill.reload.bill_llm_provisioning&.draft_org_positions
      expect(drafts&.length).to eq(1)
      expect(drafts&.first&.fetch("evidence_retracted_at")).to eq(retracted_at)
    end

    it "does not mark a pasted entry whose content changed — it is a new claim, not the retracted one" do
      bill = create(:bill)
      create(
        :bill_llm_provisioning,
        bill: bill,
        extracted_testimony: "Testimony of the Maryland Tenants Union...",
        draft_org_positions: [
          {
            "org_name" => "Maryland Tenants Union",
            "stance" => "support",
            "summary" => "Spoke in favor at the hearing.",
            "evidence_retracted_at" => 2.days.ago.utc.iso8601
          }
        ]
      )

      summary_json = {
        summary_markdown: "## Summary",
        draft_org_positions: [
          {org_name: "Maryland Tenants Union", stance: "oppose", summary: "Changed position at the hearing."}
        ]
      }.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      drafts = bill.reload.bill_llm_provisioning&.draft_org_positions
      expect(drafts&.first).not_to be_nil
      expect(drafts&.first).not_to have_key("evidence_retracted_at")
    end

    # @lat: [[hearing-testimony-census#The marks live on each draft, not on the bill]]
    it "carries BOTH internal marks forward when a stored entry holds both" do
      bill = create(:bill)
      retracted_at = 2.days.ago.utc.iso8601
      edited_at = 1.day.ago.utc.iso8601
      create(
        :bill_llm_provisioning,
        bill: bill,
        extracted_testimony: "Testimony of the Maryland Tenants Union...",
        draft_org_positions: [
          {
            "org_name" => "Maryland Tenants Union",
            "stance" => "support",
            "summary" => "Spoke in favor at the hearing.",
            "evidence_retracted_at" => retracted_at,
            "summary_edited_at" => edited_at
          }
        ]
      )

      summary_json = {
        summary_markdown: "## Summary",
        draft_org_positions: [
          {org_name: "Maryland Tenants Union", stance: "support", summary: "Spoke in favor at the hearing."}
        ]
      }.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      drafts = bill.reload.bill_llm_provisioning&.draft_org_positions
      expect(drafts&.first&.fetch("evidence_retracted_at")).to eq(retracted_at)
      expect(drafts&.first&.fetch("summary_edited_at")).to eq(edited_at)
    end

    it "still honors an explicit empty-array clear — nothing pasted means nothing to mark" do
      bill = create(:bill)
      create(
        :bill_llm_provisioning,
        bill: bill,
        extracted_testimony: "Testimony of the Maryland Tenants Union...",
        draft_org_positions: [
          {
            "org_name" => "Maryland Tenants Union",
            "stance" => "support",
            "summary" => "Spoke in favor at the hearing.",
            "evidence_retracted_at" => 2.days.ago.utc.iso8601
          }
        ]
      )

      summary_json = {
        summary_markdown: "## Summary",
        draft_org_positions: [] #: Array[untyped]
      }.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      expect(bill.reload.bill_llm_provisioning&.draft_org_positions).to eq([])
    end
  end

  # PasteSummaryService wrote the summary BODY but did not touch
  # generation_status, so a paste onto a nil/pending/failed row stayed
  # invisible.
  describe "settling the row so a paste is visible (B4-WR-03)" do
    it "completes a row that never had a status" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, generation_status: nil)

      described_class.new(
        bill: bill, actor: create(:user), summary_json: {summary_markdown: "## Pasted"}.to_json
      ).call

      expect(bill.reload.bill_llm_provisioning&.generation_status).to eq("completed")
    end

    it "completes a row whose generation FAILED — the state a paste exists for" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :failed, bill: bill)

      described_class.new(
        bill: bill, actor: create(:user), summary_json: {summary_markdown: "## Pasted"}.to_json
      ).call

      expect(bill.reload.bill_llm_provisioning&.generation_status).to eq("completed")
    end

    # This used to assert the OPPOSITE, pinning the bug in place: pending
    # means a job is queued but hasn't started. GenerateBillSummaryService
    # treats pending/generating as ONE state everywhere.
    it "leaves a row still sitting in pending alone — a queued job owns it" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :pending, bill: bill)

      described_class.new(
        bill: bill, actor: create(:user), summary_json: {summary_markdown: "## Pasted"}.to_json
      ).call

      provisioning = bill.reload.bill_llm_provisioning
      expect(provisioning&.generation_status).to eq("pending")
      # The BODY is always saved. Only the status change waits for the process
      # that owns the row.
      expect(provisioning&.llm_summary).to eq("## Pasted")
    end

    # Refusing to change the status must not be silent. The operator pasted, and
    # the Bill Creator will keep showing the in-flight view, so the reason has
    # to be somewhere a reader can find it.
    it "logs the deferred settle rather than declining silently" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :pending, bill: bill)
      allow(SwayLogging).to receive(:warn)

      described_class.new(
        bill: bill, actor: create(:user), summary_json: {summary_markdown: "## Pasted"}.to_json
      ).call

      expect(SwayLogging).to have_received(:warn).with(
        "paste_summary.settle_deferred_run_in_flight",
        hash_including(bill_id: bill.id, generation_status: "pending")
      )
    end

    # @lat: [[explanation/llm-summaries#Stand-downs are reported, not swallowed]]
    it "stamps an operator-paste marker on summary_run_id so a queued job can stand down" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :pending, bill: bill)

      described_class.new(
        bill: bill, actor: create(:user), summary_json: {summary_markdown: "## Pasted"}.to_json
      ).call

      provisioning = bill.reload.bill_llm_provisioning #: BillLlmProvisioning
      expect(SummaryRunMarker.operator_paste?(provisioning.summary_run_id)).to be(true)
    end

    # The column has a unique index over its non-null values, so one shared
    # placeholder would collide as soon as two bills were pasted onto.
    it "stamps a marker unique to the row" do
      first = create(:bill, external_id: "PASTE-A")
      second = create(:bill, external_id: "PASTE-B")
      actor = create(:user)
      body = {summary_markdown: "## Pasted"}.to_json

      described_class.new(bill: first, actor: actor, summary_json: body).call
      described_class.new(bill: second, actor: actor, summary_json: body).call

      expect(first.reload.bill_llm_provisioning&.summary_run_id)
        .not_to eq(second.reload.bill_llm_provisioning&.summary_run_id)
    end

    it "completes a row a stale-backlog drain left skipped" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :skipped, bill: bill)

      described_class.new(
        bill: bill, actor: create(:user), summary_json: {summary_markdown: "## Pasted"}.to_json
      ).call

      expect(bill.reload.bill_llm_provisioning&.generation_status).to eq("completed")
    end

    it "creates a self-provisioned row already settled" do
      bill = create(:bill)

      described_class.new(
        bill: bill, actor: create(:user), summary_json: {summary_markdown: "## Pasted"}.to_json
      ).call

      expect(bill.reload.bill_llm_provisioning&.generation_status).to eq("completed")
    end

    it "leaves an already-completed row completed" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :completed, bill: bill)

      described_class.new(
        bill: bill, actor: create(:user), summary_json: {summary_markdown: "## Pasted"}.to_json
      ).call

      expect(bill.reload.bill_llm_provisioning&.generation_status).to eq("completed")
    end

    # A running generation owns the row. Taking it over mid-run would mark
    # a generation finished while it's still writing, and the job itself
    # already refuses to touch a row it no longer owns.
    it "does not settle a row with a generation in flight" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :generating, bill: bill)

      described_class.new(
        bill: bill, actor: create(:user), summary_json: {summary_markdown: "## Pasted"}.to_json
      ).call

      expect(bill.reload.bill_llm_provisioning&.generation_status).to eq("generating")
    end

    it "still persists the pasted body on that in-flight row" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :generating, bill: bill)

      described_class.new(
        bill: bill, actor: create(:user), summary_json: {summary_markdown: "## Pasted"}.to_json
      ).call

      expect(bill.reload.bill_llm_provisioning&.llm_summary).to eq("## Pasted")
    end
  end

  # PasteSummaryService is the THIRD writer of the summary body, and the
  # only one that never cleared generation_error. Both generate paths
  # clear it first.
  describe "generation_error on paste (B2-WR-01)" do
    it "clears a stale positions-failure error the paste replaces" do
      bill = create(:bill)
      provisioning = create(
        :bill_llm_provisioning,
        bill: bill,
        generation_status: "completed",
        generation_error: "positions call failed (the summary is valid): 429 rate limited",
        # This example is about clearing generation_error, not the testimony
        # check. A positions call hitting a rate limit can only run on a
        # bill that HAS testimony, so the fixture says so outright.
        extracted_testimony: "Testimony of the Maryland Tenants Union in support."
      )
      summary_json = {
        summary_markdown: "## Summary\nReplacement body.",
        full_breakdown_markdown: "## Full",
        draft_org_positions: [
          {org_name: "Maryland Tenants Union", stance: "support", summary: "Pasted rationale."}
        ]
      }.to_json

      outcome, = described_class.new(
        bill: bill, actor: create(:user), summary_json: summary_json
      ).call

      expect(outcome).to eq(:persisted)
      provisioning.reload
      # Without this the notice kept saying "Draft org positions were not
      # generated" directly above the pasted cards.
      expect(provisioning.generation_error).to be_nil
      expect(provisioning.draft_org_positions.length).to eq(1)
    end

    it "clears the error even when the paste omits draft_org_positions" do
      bill = create(:bill)
      provisioning = create(
        :bill_llm_provisioning,
        bill: bill,
        generation_status: "completed",
        generation_error: "positions call failed (the summary is valid): 500 upstream"
      )
      summary_json = {
        summary_markdown: "## Summary\nReplacement body.",
        full_breakdown_markdown: "## Full"
      }.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      expect(provisioning.reload.generation_error).to be_nil
    end
  end

  # @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
  describe "the record of what the last run read" do
    it "deletes it, because a pasted summary read nothing" do
      bill = create(:bill)
      create(:bill_summary_prompt_snapshot, bill: bill)
      summary_json = {summary_markdown: "## Summary\nHand written."}.to_json

      described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      expect(bill.reload.bill_summary_prompt_snapshot).to be_nil
    end

    it "leaves it alone when the paste is refused before anything is written" do
      bill = create(:bill)
      create(:bill_summary_prompt_snapshot, bill: bill)

      outcome, _errors = described_class.new(
        bill: bill, actor: create(:user), summary_json: "{not json"
      ).call

      expect(outcome).to eq(:invalid_json)
      expect(bill.reload.bill_summary_prompt_snapshot).not_to be_nil
    end
  end

  describe "summary revision tracking" do
    it "records an accepted paste as an operator_paste draft revision with unknown review state" do
      bill = create(:bill, summary: Bill::SUMMARY_PLACEHOLDER)
      actor = create(:user)
      summary_json = {
        summary_markdown: "## Pasted Summary\nHand-crafted content.",
        full_breakdown_markdown: "## Breakdown",
        draft_org_positions: []
      }.to_json

      expect {
        described_class.new(bill: bill, actor: actor, summary_json: summary_json).call
      }.to change { bill.bill_summary_revisions.count }.by(1)

      rev = bill.bill_summary_revisions.last
      expect(rev.origin).to eq("operator_paste")
      expect(rev.actor).to eq(actor)
      expect(rev.publication_role).to eq("draft")
      expect(rev.review_state).to eq("unknown")
      expect(rev.llm_provider).to be_nil
      expect(rev.llm_model).to be_nil
      expect(rev.summary_markdown).to eq("## Pasted Summary\nHand-crafted content.")
    end

    it "preserves existing published summary as initial baseline when first paste occurs" do
      bill = create(:bill, summary: "Existing published bill text")
      actor = create(:user)
      summary_json = {summary_markdown: "## New Pasted Draft"}.to_json

      described_class.new(bill: bill, actor: actor, summary_json: summary_json).call

      revisions = bill.bill_summary_revisions.order(:id)
      expect(revisions.count).to eq(2)
      expect(revisions.first.origin).to eq("initial_baseline")
      expect(revisions.first.summary_markdown).to eq("Existing published bill text")
      expect(revisions.last.origin).to eq("operator_paste")
      expect(revisions.last.summary_markdown).to eq("## New Pasted Draft")
    end
  end

  describe "news_usage and source_uses validation" do
    it "rejects news_usage: 'none' when source_uses is non-empty" do
      bill = create(:bill)
      news_article = create(:news_article, canonical_url: "https://baltimoresun.com/report")
      text_version = create(:news_article_text_version, :extracted, news_article: news_article, text: "Report text verbatim.")
      bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)

      summary_json = {
        summary_markdown: "## Summary\nNo news links here.",
        news_usage: "none",
        source_uses: [
          {
            bill_news_article_id: bna.id,
            text_version_id: text_version.id,
            claim_text: "No news links here.",
            evidence_excerpt: "Report text verbatim.",
            citation_url: "https://baltimoresun.com/report"
          }
        ]
      }.to_json

      outcome, errors = described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      expect(outcome).to eq(:invalid_news_usage)
      expect(errors.first[:message]).to include("Declared no-news usage but source-use manifest is not empty")
      expect(bill.reload.bill_llm_provisioning).to be_nil
    end

    it "rejects news_usage: 'cited' with invalid source_uses without raising a 500 or persisting partial state" do
      bill = create(:bill)
      other_bill = create(:bill)
      news_article = create(:news_article, canonical_url: "https://baltimoresun.com/report")
      text_version = create(:news_article_text_version, :extracted, news_article: news_article, text: "Report text verbatim.")
      other_bna = create(:bill_news_article, :approved, bill: other_bill, news_article: news_article, current_text_version: text_version)

      summary_json = {
        summary_markdown: "## Summary\nClaim text [Source](https://baltimoresun.com/report).",
        news_usage: "cited",
        source_uses: [
          {
            bill_news_article_id: other_bna.id,
            text_version_id: text_version.id,
            claim_text: "Claim text",
            evidence_excerpt: "Report text verbatim.",
            citation_url: "https://baltimoresun.com/report"
          }
        ]
      }.to_json

      outcome, errors = described_class.new(bill: bill, actor: create(:user), summary_json: summary_json).call

      expect(outcome).to eq(:invalid_news_usage)
      expect(errors).not_to be_empty
      expect(bill.reload.bill_llm_provisioning).to be_nil
      expect(PipelineActivityLogEntry.where(event_type: "paste_summary_accepted").count).to eq(0)
      expect(PipelineActivityLogEntry.where(event_type: "paste_summary_rejected").count).to eq(1)
    end

    it "captures NewsArticleSourceSnapshot before filtering draft_org_positions when no prior snapshot exists" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, extracted_testimony: nil, supplemental_testimony: nil)
      news_article = create(
        :news_article,
        outlet_name: "The Baltimore Banner",
        title: "Housing Story",
        canonical_url: "https://example.com/housing",
        article_kind: "reporting"
      )
      article_text = "Jane Doe, executive director of the Baltimore Tenants Union, said: \"We need this protection now.\""
      text_version = create(:news_article_text_version, :extracted, news_article: news_article, text: article_text)
      bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)

      expect(bill.news_article_source_snapshots.count).to eq(0)
      allow(NewsOrgPositionGroundingService).to receive(:filter_draft_positions).and_call_original

      summary_json = {
        summary_markdown: "## Summary\nTenants spoke out [Banner](https://example.com/housing).",
        news_usage: "cited",
        source_uses: [
          {
            bill_news_article_id: bna.id,
            text_version_id: text_version.id,
            claim_text: "Tenants spoke out",
            evidence_excerpt: "Jane Doe, executive director of the Baltimore Tenants Union, said: \"We need this protection now.\"",
            citation_url: "https://example.com/housing"
          }
        ],
        draft_org_positions: [
          {
            org_name: "Baltimore Tenants Union",
            stance: "support",
            summary: "Initial",
            bill_news_article_id: bna.id,
            text_version_id: text_version.id,
            evidence_excerpt: "said: \"We need this protection now.\"",
            speaker_name: "Jane Doe",
            speaker_role: "executive director"
          }
        ]
      }.to_json

      outcome, errors = described_class.new(
        bill: bill, actor: create(:user), summary_json: summary_json
      ).call

      expect(outcome).to eq(:persisted)
      expect(errors).to eq([])
      snapshot = bill.news_article_source_snapshots.for_summary.recent_first.first
      expect(snapshot).to be_present
      expect(NewsOrgPositionGroundingService).to have_received(:filter_draft_positions).with(
        hash_including(snapshots: [snapshot])
      )
      drafts = bill.reload.bill_llm_provisioning&.draft_org_positions
      expect(drafts).to be_present
      expect(drafts&.length).to eq(1)
      expect(drafts&.first&.fetch("org_name")).to eq("Baltimore Tenants Union")
    end
  end
end
