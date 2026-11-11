# frozen_string_literal: true

require "rails_helper"

# The acceptance test for the "this summary is out of date" flow. Set
# `diff_generated_at` to now and `llm_generated_at` to a day ago: the stale
# chip and its button show up. Clicking that button enqueues
# `GenerateBillSummaryJob` and writes an Activity Log entry.

RSpec.describe "Bills regenerate_summary admin gate", type: :request do
  include_examples "requires sway admin",
    verb: :post,
    path: "/bills/1/regenerate_summary"
end

RSpec.describe "POST /bills/:id/regenerate_summary", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:user) { sway_locale_and_user.last }

  let(:bill) do
    legislator = sway_locale.legislators.first
    create(:bill, sway_locale: sway_locale, legislator: legislator)
  end

  describe "R23 literal acceptance" do
    # @lat: [[bill-summary-call-preconditions#Why generate_bill_summary_job_spec.rb's default fixture sets bill.extracted_text, not just :with_diff_content]]
    let(:bill) do
      legislator = sway_locale.legislators.first
      create(
        :bill,
        sway_locale: sway_locale,
        legislator: legislator,
        extracted_text: "Section 1. The Mayor shall submit an annual report."
      )
    end

    let!(:provisioning) do
      # Pipeline data is present so the regenerate check does not bail out
      # early. generation_status starts as nil, its initial state, so the
      # "already running" check does not trip either.
      create(:bill_llm_provisioning,
        bill: bill,
        diff_content: "pipeline diff payload",
        diff_generated_at: Time.current,
        llm_generated_at: 1.day.ago)
    end

    it "is in a stale state (provisioning.stale? == true)" do
      expect(provisioning.stale?).to be(true)
    end

    it "enqueues GenerateBillSummaryJob with @bill.id when the CTA is clicked" do
      expect {
        post regenerate_summary_bill_path(bill)
      }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id)
    end

    it "writes a summary_regenerate_triggered Activity Log entry attributed to the admin" do
      expect {
        post regenerate_summary_bill_path(bill)
      }.to change(PipelineActivityLogEntry, :count).by(1)

      entry = PipelineActivityLogEntry.order(created_at: :desc).first #: PipelineActivityLogEntry
      expect(entry.event_type).to eq("summary_regenerate_triggered")
      expect(entry.severity).to eq("info")
      expect(entry.actor_user_id).to eq(user.id)
      expect(entry.subject_type).to eq("Bill")
      expect(entry.subject_id).to eq(bill.id.to_s)
    end

    it "sets the locked flash[:notice] copy and redirects back to edit" do
      post regenerate_summary_bill_path(bill)
      expect(flash[:notice]).to eq("Summary regeneration queued successfully.")
      expect(response).to redirect_to(summary_bill_creator_path(bill))
    end

    it "writes the Activity Log entry AND enqueues the job in the same request (audit follows side-effect — REVIEW-3 #1)" do
      # The log entry is written AFTER the job is enqueued. This example only
      # checks that both happen; the next one proves the order.
      expect {
        post regenerate_summary_bill_path(bill)
      }.to change(PipelineActivityLogEntry, :count).by(1)
        .and(have_enqueued_job(GenerateBillSummaryJob).with(bill.id))
    end

    it "does NOT write the Activity Log entry when GenerateBillSummaryJob.perform_later raises (audit-trail-last — REVIEW-3 #1)" do
      # @lat: [[generate-bill-summary-service-outcomes#GenerateBillSummaryService.call return values]]
      allow(SwayLogging).to receive(:warn)
      allow(SwayLogging).to receive(:log_exception)
      allow(GenerateBillSummaryJob).to receive(:perform_later).and_raise(StandardError, "queue down")

      expect {
        post regenerate_summary_bill_path(bill)
      }.not_to change(PipelineActivityLogEntry, :count)

      expect(response).to redirect_to(summary_bill_creator_path(bill))
      expect(flash[:notice]).to be_nil
    end

    it "leaves the row where the operator's next click can reach it when the queue write fails" do
      allow(SwayLogging).to receive(:warn)
      allow(SwayLogging).to receive(:log_exception)
      allow(GenerateBillSummaryJob).to receive(:perform_later).and_raise(StandardError, "queue down")

      post regenerate_summary_bill_path(bill)

      expect(provisioning.reload.generation_status).to eq("skipped")
      expect(provisioning.can_enqueue?).to be(true)
    end

    it "clears summary_run_id so a stale prior-run summary_generated webhook can't overwrite the new run (REVIEW-2 #4)" do
      provisioning.update!(summary_run_id: "stale-uuid-from-prior-run")
      expect {
        post regenerate_summary_bill_path(bill)
      }.to change { provisioning.reload.summary_run_id }.from("stale-uuid-from-prior-run").to(nil)
    end

    # @lat: [[generate-bill-summary-service-concurrency#Why summary_run_id and generation_error are cleared before enqueue!]]
    it "persists supplemental_testimony supplied with the regenerate request" do
      post regenerate_summary_bill_path(bill),
        params: {supplemental_testimony: "Testimony the extractor could not read."}

      expect(provisioning.reload.supplemental_testimony).to eq("Testimony the extractor could not read.")
    end

    it "makes the pasted testimony visible to the REAS-01 positions gate" do
      expect {
        post regenerate_summary_bill_path(bill),
          params: {supplemental_testimony: "Testimony the extractor could not read."}
      }.to change { provisioning.reload.testimony_present? }.from(false).to(true)
    end

    it "leaves a stored supplemental_testimony alone when the request carries none" do
      # The button in LlmSummaryEmptyState calls this same endpoint with no
      # body, and it must not erase a paste the operator made earlier.
      provisioning.update!(supplemental_testimony: "Previously pasted testimony.")

      post regenerate_summary_bill_path(bill)

      expect(provisioning.reload.supplemental_testimony).to eq("Previously pasted testimony.")
    end

    # @lat: [[supplemental-testimony-write-rule#Why blank never clears]]
    describe "supplemental_testimony blank semantics (B2-WR-03)" do
      it "does not destroy a stored paste when the request carries a blank value" do
        provisioning.update!(supplemental_testimony: "Testimony another operator pasted.")

        post regenerate_summary_bill_path(bill), params: {supplemental_testimony: ""}

        expect(provisioning.reload.supplemental_testimony).to eq("Testimony another operator pasted.")
      end

      it "does not destroy a stored paste on a whitespace-only value either" do
        provisioning.update!(supplemental_testimony: "Testimony another operator pasted.")

        post regenerate_summary_bill_path(bill), params: {supplemental_testimony: "   \n "}

        expect(provisioning.reload.supplemental_testimony).to eq("Testimony another operator pasted.")
      end

      it "still overwrites a stored paste when the request carries real text" do
        provisioning.update!(supplemental_testimony: "Old paste.")

        post regenerate_summary_bill_path(bill), params: {supplemental_testimony: "New paste."}

        expect(provisioning.reload.supplemental_testimony).to eq("New paste.")
      end

      it "clears the column when the caller explicitly asks to" do
        provisioning.update!(supplemental_testimony: "Testimony to remove.")

        post regenerate_summary_bill_path(bill),
          params: {supplemental_testimony: "", clear_supplemental_testimony: "1"}

        expect(provisioning.reload.supplemental_testimony).to be_nil
      end

      it "ignores a non-String supplemental_testimony rather than coercing it into the column" do
        provisioning.update!(supplemental_testimony: "Testimony another operator pasted.")

        post regenerate_summary_bill_path(bill), params: {supplemental_testimony: {"a" => "b"}}

        expect(provisioning.reload.supplemental_testimony).to eq("Testimony another operator pasted.")
      end
    end

    it "clears generation_error when the prior run failed (REVIEW-3 #2)" do
      provisioning.update!(generation_status: "failed", generation_error: "Prior run timeout")
      expect {
        post regenerate_summary_bill_path(bill)
      }.to change { provisioning.reload.generation_error }.from("Prior run timeout").to(nil)
    end
  end

  # @lat: [[bill-summary-call-preconditions#Why generate_bill_summary_job_spec.rb's default fixture sets bill.extracted_text, not just :with_diff_content]]
  describe "guard: missing pipeline data" do
    let!(:provisioning) do
      create(:bill_llm_provisioning,
        bill: bill,
        diff_content: nil,
        diff_generated_at: Time.current,
        llm_generated_at: 1.day.ago)
    end

    it "does not enqueue the job when the bill has no source text and no testimony" do
      expect {
        post regenerate_summary_bill_path(bill)
      }.not_to have_enqueued_job(GenerateBillSummaryJob)
    end

    it "does not write an Activity Log entry when the bill has no source text and no testimony" do
      expect {
        post regenerate_summary_bill_path(bill)
      }.not_to change(PipelineActivityLogEntry, :count)
    end
  end

  # This bill needs real source text. runnable? is checked BEFORE the
  # "already running" check, so a bill with no source returns
  # :no_pipeline_data and both examples below would pass without ever reaching
  # the check they are named after — green tests that measure nothing.
  describe "guard: generation already in progress" do
    let(:bill) do
      legislator = sway_locale.legislators.first
      create(
        :bill,
        sway_locale: sway_locale,
        legislator: legislator,
        extracted_text: "Section 1. The Mayor shall submit an annual report."
      )
    end

    let!(:provisioning) do
      create(:bill_llm_provisioning,
        bill: bill,
        diff_content: "pipeline diff payload",
        diff_generated_at: Time.current,
        llm_generated_at: 1.day.ago,
        generation_status: "generating")
    end

    it "does not enqueue a second job when status is generating" do
      expect {
        post regenerate_summary_bill_path(bill)
      }.not_to have_enqueued_job(GenerateBillSummaryJob)
    end

    it "does not write an Activity Log entry when generation is in flight" do
      expect {
        post regenerate_summary_bill_path(bill)
      }.not_to change(PipelineActivityLogEntry, :count)
    end
  end
end

# The Bill Creator's per-run model picker. AdminSetting still holds the standing
# default; a picked model rides this one request only.
RSpec.describe "POST /bills/:id/regenerate_summary — per-run model choice", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:user) { sway_locale_and_user.last }

  let(:bill) do
    legislator = sway_locale.legislators.first
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      extracted_text: "Section 1. The Mayor shall submit an annual report."
    )
  end

  let!(:provisioning) { create(:bill_llm_provisioning, bill: bill) }

  it "carries a supported model through to the job" do
    expect {
      post "/bills/#{bill.id}/regenerate_summary", params: {summarization_model: "claude-opus-5-5"}
    }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, summarization_model: "claude-opus-5-5")
  end

  it "carries an OpenRouter model choice through to the job without modifying standing settings" do
    expect {
      post "/bills/#{bill.id}/regenerate_summary", params: {summarization_model: "Deepseek Pro Latest"}
    }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, summarization_model: "Deepseek Pro Latest")

    expect(AdminSetting.singleton.reload.summarization_model).not_to eq("Deepseek Pro Latest")
  end

  it "carries a newly seeded OpenRouter Latest model choice through to the job" do
    expect {
      post "/bills/#{bill.id}/regenerate_summary", params: {summarization_model: "Gemini Argon Latest"}
    }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, summarization_model: "Gemini Argon Latest")

    expect(AdminSetting.singleton.reload.summarization_model).not_to eq("Gemini Argon Latest")
  end

  it "carries a dynamically added OpenRouter model through to the job without modifying standing settings" do
    allow(Llm::OpenRouterModelsService).to receive(:lookup).with("openai/gpt-4o").and_return({
      id: "openai/gpt-4o",
      label: "OpenAI: GPT-4o",
      supports_reasoning: false
    })
    AdminSetting.singleton.add_offered_model!("openai/gpt-4o")

    expect {
      post "/bills/#{bill.id}/regenerate_summary", params: {summarization_model: "openai/gpt-4o"}
    }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, summarization_model: "openai/gpt-4o")

    expect(AdminSetting.singleton.reload.summarization_model).not_to eq("openai/gpt-4o")
  end

  it "enqueues nothing and says so when the model is not one Sway offers" do
    expect {
      post "/bills/#{bill.id}/regenerate_summary", params: {summarization_model: "gpt-9"}
    }.not_to have_enqueued_job(GenerateBillSummaryJob)

    follow_redirect!
    expect(response.body).to include("not one Sway offers")
  end

  it "enqueues nothing and says so when a removed model is requested" do
    AdminSetting.singleton.remove_offered_model!("OpenRouter Auto")

    expect {
      post "/bills/#{bill.id}/regenerate_summary", params: {summarization_model: "OpenRouter Auto"}
    }.not_to have_enqueued_job(GenerateBillSummaryJob)

    follow_redirect!
    expect(response.body).to include("not one Sway offers")
  end

  it "leaves the standing AdminSetting default untouched" do
    expect {
      post "/bills/#{bill.id}/regenerate_summary", params: {summarization_model: "claude-opus-5-5"}
    }.not_to change { AdminSetting.singleton.reload.summarization_model }
  end

  # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
  it "leaves concurrent or subsequent bill runs on the global default" do
    other_bill = create(
      :bill,
      sway_locale: sway_locale,
      legislator: sway_locale.legislators.first,
      extracted_text: "Section 2. Another bill source."
    )
    create(:bill_llm_provisioning, bill: other_bill)

    expect {
      post "/bills/#{bill.id}/regenerate_summary", params: {summarization_model: "claude-opus-5-5"}
      post "/bills/#{other_bill.id}/regenerate_summary"
    }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, summarization_model: "claude-opus-5-5")
      .and have_enqueued_job(GenerateBillSummaryJob).with(other_bill.id)
  end
end

RSpec.describe "POST /bills/:id/regenerate_summary — per-run summary instructions", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:user) { sway_locale_and_user.last }

  let(:bill) do
    legislator = sway_locale.legislators.first
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      extracted_text: "Section 1. The Mayor shall submit an annual report."
    )
  end

  let!(:provisioning) { create(:bill_llm_provisioning, bill: bill) }

  it "enqueues the job with both summarization_model and normalized summary_instructions" do
    expect {
      post "/bills/#{bill.id}/regenerate_summary",
        params: {
          summarization_model: "claude-opus-5-5",
          summary_instructions: "Please include the property tax rate of 2.24%."
        }
    }.to have_enqueued_job(GenerateBillSummaryJob).with(
      bill.id,
      summarization_model: "claude-opus-5-5",
      summary_instructions: "Please include the property tax rate of 2.24%."
    )

    expect(response).to redirect_to(summary_bill_creator_path(bill))
  end

  it "trims surrounding ASCII whitespace and preserves internal and non-ASCII characters" do
    input = " \t\r\n\f\vSpecial instructions: note § 5 & \u00A0 preserved.\t\n "
    expected = "Special instructions: note § 5 & \u00A0 preserved."

    expect {
      post "/bills/#{bill.id}/regenerate_summary",
        params: {summary_instructions: input}
    }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, summary_instructions: expected)
  end

  it "preserves non-ASCII whitespace such as U+00A0 alone" do
    expect {
      post "/bills/#{bill.id}/regenerate_summary",
        params: {summary_instructions: "\u00A0"}
    }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, summary_instructions: "\u00A0")
  end

  it "preserves U+00A0 surrounded by ASCII whitespace" do
    expect {
      post "/bills/#{bill.id}/regenerate_summary",
        params: {summary_instructions: " \t\r\n\f\v\u00A0\t\n "}
    }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, summary_instructions: "\u00A0")
  end

  it "enqueues without summary_instructions keyword when input is empty or whitespace-only" do
    expect {
      post "/bills/#{bill.id}/regenerate_summary",
        params: {summary_instructions: "   \t\n\r\f\v  "}
    }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id)
  end

  it "rejects non-string input (nested hash) with an Inertia generation error before enqueuing or logging" do
    expect {
      post "/bills/#{bill.id}/regenerate_summary",
        params: {summary_instructions: {malicious: "payload"}}
    }.not_to have_enqueued_job(GenerateBillSummaryJob)

    expect(response).to redirect_to(summary_bill_creator_path(bill))
    expect(session.dig(:inertia_errors, :generation)).to eq("Instructions must be text up to 2,000 characters.")
    follow_redirect!
    expect(response.body).to include("Instructions must be text up to 2,000 characters.")
    expect(PipelineActivityLogEntry.where(event_type: "summary_regenerate_triggered")).to be_empty
  end

  it "rejects non-string input (array) with an Inertia generation error" do
    expect {
      post "/bills/#{bill.id}/regenerate_summary",
        params: {summary_instructions: ["invalid", "array"]}
    }.not_to have_enqueued_job(GenerateBillSummaryJob)

    expect(response).to redirect_to(summary_bill_creator_path(bill))
    expect(session.dig(:inertia_errors, :generation)).to eq("Instructions must be text up to 2,000 characters.")
    follow_redirect!
    expect(response.body).to include("Instructions must be text up to 2,000 characters.")
  end

  it "accepts exactly 2,000 code points including an astral character" do
    valid_text = ("a" * 1999) + "\u{1F600}"
    expect(valid_text.length).to eq(2000)

    expect {
      post "/bills/#{bill.id}/regenerate_summary",
        params: {summary_instructions: valid_text}
    }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, summary_instructions: valid_text)
  end

  it "rejects 2,001 code points (2,000 ASCII + 1 astral character) with an Inertia generation error" do
    over_limit_text = ("a" * 2000) + "\u{1F600}"
    expect(over_limit_text.length).to eq(2001)

    expect {
      post "/bills/#{bill.id}/regenerate_summary",
        params: {summary_instructions: over_limit_text}
    }.not_to have_enqueued_job(GenerateBillSummaryJob)

    expect(response).to redirect_to(summary_bill_creator_path(bill))
    expect(session.dig(:inertia_errors, :generation)).to eq("Instructions must be text up to 2,000 characters.")
    follow_redirect!
    expect(response.body).to include("Instructions must be text up to 2,000 characters.")
    expect(PipelineActivityLogEntry.where(event_type: "summary_regenerate_triggered")).to be_empty
  end

  it "accepts reasoning_effort and forwards it to GenerateBillSummaryJob" do
    AdminSetting.singleton.update!(summarization_model: "Opus Latest")

    expect {
      post "/bills/#{bill.id}/regenerate_summary",
        params: {reasoning_effort: "high"}
    }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, reasoning_effort: "high")
  end

  it "rejects an unsupported reasoning effort with an Inertia generation error" do
    expect {
      post "/bills/#{bill.id}/regenerate_summary",
        params: {reasoning_effort: "ultra"}
    }.not_to have_enqueued_job(GenerateBillSummaryJob)

    expect(flash[:notice]).to be_nil
    expect(response).to redirect_to(summary_bill_creator_path(bill))
    expect(session.dig(:inertia_errors, :generation)).to eq(
      "That reasoning level is not supported. Choose default, low, medium, or high."
    )
    follow_redirect!
    expect(response.body).to include("That reasoning level is not supported. Choose default, low, medium, or high.")
  end

  it "rejects reasoning_effort for a non-reasoning per-run model with an Inertia generation error" do
    expect {
      post "/bills/#{bill.id}/regenerate_summary",
        params: {reasoning_effort: "high", summarization_model: "claude-haiku-5-5"}
    }.not_to have_enqueued_job(GenerateBillSummaryJob)

    expect(flash[:notice]).to be_nil
    expect(response).to redirect_to(summary_bill_creator_path(bill))
    expect(session.dig(:inertia_errors, :generation)).to eq(
      "That reasoning level is not supported. Choose default, low, medium, or high."
    )
    follow_redirect!
    expect(response.body).to include("That reasoning level is not supported. Choose default, low, medium, or high.")
  end

  it "rejects reasoning_effort when standing model is non-reasoning with an Inertia generation error" do
    AdminSetting.singleton.update!(summarization_model: "claude-haiku-5-5")

    expect {
      post "/bills/#{bill.id}/regenerate_summary",
        params: {reasoning_effort: "high"}
    }.not_to have_enqueued_job(GenerateBillSummaryJob)

    expect(flash[:notice]).to be_nil
    expect(response).to redirect_to(summary_bill_creator_path(bill))
    expect(session.dig(:inertia_errors, :generation)).to eq(
      "That reasoning level is not supported. Choose default, low, medium, or high."
    )
  end

  describe "GET /admin/bill_creator/:id/summary catalog lookups" do
    include_context "with in-memory Rails.cache"

    before do
      catalog = [
        {id: "openai/gpt-4o", label: "OpenAI: GPT-4o", supports_reasoning: false},
        {id: "mistralai/mistral-large", label: "Mistral Large", supports_reasoning: false},
        {id: "qwen/qwen-2.5-72b-instruct", label: "Qwen 2.5 72B", supports_reasoning: true}
      ]
      Rails.cache.write(Llm::OpenRouterModelsService::CACHE_KEY, catalog)
      AdminSetting.singleton.update!(
        offered_models: ["claude-haiku-5-5", "openai/gpt-4o", "mistralai/mistral-large", "qwen/qwen-2.5-72b-instruct"]
      )
    end

    it "calls Llm::OpenRouterModelsService.call at most once when offered models contain multiple dynamic OpenRouter slugs" do
      expect(Llm::OpenRouterModelsService).to receive(:call).at_most(:once).and_call_original

      get summary_bill_creator_path(bill)

      expect(response).to have_http_status(:ok)
    end
  end
end
