# frozen_string_literal: true

require "rails_helper"

# Routing isolation at run time: with LLM_PROVIDER=claude the llama.cpp adapter
# is never built, and the other way round. Do NOT assert "Anthropic::Client is
# never created on the Claude path" — ClaudeAdapter builds one inside itself, so
# that assertion is bound to fail.
RSpec.describe GenerateBillSummaryJob do
  # @lat: [[settings-and-secrets#Settings and secrets]]
  after { Sway::Settings.reset! }

  # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Independent inputs for summaries and positions]]
  let(:bill) { create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.") }
  let!(:provisioning) { create(:bill_llm_provisioning, :pending, :with_diff_content, bill: bill) }

  # Active Category records have to exist, so BillCategoryAssigner can find
  # matches in the active set. Named "Health" and "Taxes" to line up with
  # valid_payload["categories"]. Every happy-path example depends on them.
  let!(:cat_health) { create(:category, name: "Health", active: true) }
  let!(:cat_taxes) { create(:category, name: "Taxes", active: true) }

  let(:valid_payload) do
    {
      "summary_markdown" => "What changed: §1 amended to add reporting requirements.",
      "full_breakdown_markdown" => "## Section 1\nAdds quarterly reporting obligation.",
      "draft_org_positions" => [
        {"org_name" => "ACLU", "stance" => "support", "summary" => "Improves transparency."}
      ],
      # The categories key is required. Without it BillCategoryAssigner raises
      # Llm::SchemaError, which becomes DeterministicBillSummaryError, and every
      # happy-path test breaks. The names must match the active Category records
      # above.
      "categories" => ["Health", "Taxes"],
      "news_usage" => "none"
    }
  end

  describe "class structure" do
    it "defines BillSummaryError at the top of the class for backwards compat" do
      expect(described_class::BillSummaryError).to be < StandardError
    end

    it "defines TransientBillSummaryError as a BillSummaryError subclass" do
      expect(described_class::TransientBillSummaryError).to be < described_class::BillSummaryError
    end

    it "defines DeterministicBillSummaryError as a BillSummaryError subclass" do
      expect(described_class::DeterministicBillSummaryError).to be < described_class::BillSummaryError
    end

    it "registers retry_on for TransientBillSummaryError" do
      handler = described_class.rescue_handlers.find { |h| h.first == "GenerateBillSummaryJob::TransientBillSummaryError" }
      expect(handler).not_to be_nil
    end

    it "registers discard_on for DeterministicBillSummaryError" do
      handler = described_class.rescue_handlers.find { |h| h.first == "GenerateBillSummaryJob::DeterministicBillSummaryError" }
      expect(handler).not_to be_nil
    end
  end

  # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Bounded errors preserve the operator instruction]]
  describe "the budget the positions-failed template leaves an adapter message (F18-01)" do
    # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Bounded errors preserve the operator instruction]]
    it "leaves an adapter message room inside the cap" do
      expect(described_class::MAX_POSITIONS_FAILED_REASON_LENGTH).to be >= 200
      expect(described_class::MAX_POSITIONS_FAILED_REASON_LENGTH)
        .to be <= described_class::MAX_GENERATION_ERROR_LENGTH
    end

    # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Bounded errors preserve the operator instruction]]
    it "carries exactly one reason placeholder, which is what the subtraction measures" do
      expect(described_class::NO_SOURCE_TEXT_POSITIONS_FAILED_ERROR.scan("%{reason}").size).to eq(1)
    end

    # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Bounded errors preserve the operator instruction]]
    it "fits the reason slot it is carried into" do
      expect(described_class::POSITIONS_EVIDENCE_WITHDRAWN_REASON.length)
        .to be <= described_class::MAX_POSITIONS_FAILED_REASON_LENGTH
    end

    # The bound above is arithmetic; this is the sentence an operator reads. It
    # fails if the constant is cut at all, wherever the cut lands, and it fails
    # on the ".." the two full stops used to make once the cut stopped hiding
    # them.
    it "carries the withdrawn reason whole into the composed message, closing instruction and all" do
      composed = described_class.new.send(
        :no_source_text_message, provisioning, described_class::POSITIONS_EVIDENCE_WITHDRAWN_REASON
      )

      expect(composed).to include("Generate again to draw positions from the testimony as it stands now.")
      expect(composed).to end_with("or until you paste a summary.")
      expect(composed).not_to include("..")
      expect(composed.length).to be <= described_class::MAX_GENERATION_ERROR_LENGTH
    end
  end

  # The first of the five paths that produce nothing. The pipeline's
  # #resolve_bill! already refuses this case before it reaches here, so the
  # answer is unreachable through that caller — which is exactly why it needs
  # pinning: nothing else notices if it goes back to a bare `return`. (B24-10)
  describe "#perform — no Bill row" do
    it "tells its caller it did not run" do
      expect(described_class.new.perform(-1)).to eq(described_class::NOT_RUN)
    end
  end

  describe "#perform — stale-job guard" do
    it "skips a job (re-)enqueued longer ago than STALE_AFTER without building an LLM client" do
      allow(SwayLogging).to receive(:warn)
      job = described_class.new(bill.id)
      # enqueued_at is a plain accessor; set it directly to imitate a backlog job
      # drained after a restart. Calling #perform, rather than perform_now, runs
      # only the method body and skips the around_perform and retry callbacks.
      job.enqueued_at = (described_class::STALE_AFTER + 1.hour).ago

      expect(Llm::Client).not_to receive(:build)
      expect { job.perform(bill.id) }.not_to raise_error

      expect(SwayLogging).to have_received(:warn).with("generate_bill_summary.skipped_stale", any_args)
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#Why the reclaim judgement lives on the row]]
    it "marks the stranded pending provisioning skipped so a re-trigger is not blocked" do
      allow(SwayLogging).to receive(:warn)
      job = described_class.new(bill.id)
      job.enqueued_at = (described_class::STALE_AFTER + 1.hour).ago

      # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
      expect(job.perform(bill.id)).to eq(described_class::NOT_RUN)

      provisioning.reload
      expect(provisioning.generation_status).to eq("skipped")
      expect(provisioning.pending?).to be(false)
      expect(provisioning.generating?).to be(false)
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
    it "finishes an operator's deferred hand-off instead of skipping the row" do
      allow(SwayLogging).to receive(:warn)
      provisioning.update!(
        llm_summary: "A hand-written summary.",
        llm_provider: "operator_paste",
        summary_run_id: SummaryRunMarker.operator_paste
      )

      job = described_class.new(bill.id)
      job.enqueued_at = (described_class::STALE_AFTER + 1.hour).ago

      expect(Llm::Client).not_to receive(:build)
      job.perform(bill.id)

      provisioning.reload
      expect(provisioning.generation_status).to eq("completed")
      expect(provisioning.llm_summary).to eq("A hand-written summary.")
      expect(SummaryRunMarker.operator_paste?(provisioning.summary_run_id)).to be(true)
    end

    it "preserves a prior completed summary's content when skipping a stale regen" do
      allow(SwayLogging).to receive(:warn)
      # A regenerate flips completed to pending but never clears the summary
      # columns; skipping a stale job must not wipe out the old summary, which
      # is still good.
      provisioning.update!(
        llm_summary: "Prior summary text",
        llm_full_breakdown: "## Section 1\nPrior breakdown",
        llm_generated_at: 2.days.ago
      )
      before_generated_at = provisioning.llm_generated_at

      job = described_class.new(bill.id)
      job.enqueued_at = (described_class::STALE_AFTER + 1.hour).ago
      job.perform(bill.id)

      provisioning.reload
      expect(provisioning.generation_status).to eq("skipped")
      expect(provisioning.llm_summary).to eq("Prior summary text")
      expect(provisioning.llm_full_breakdown).to eq("## Section 1\nPrior breakdown")
      expect(provisioning.llm_generated_at).to be_within(1.second).of(before_generated_at)
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#Why the reclaim judgement lives on the row]]
    it "spends nothing when the row it was going to skip is deleted in that instant" do
      allow(SwayLogging).to receive(:warn)
      job = described_class.new(bill.id)
      job.enqueued_at = (described_class::STALE_AFTER + 1.hour).ago
      allow_any_instance_of(BillLlmProvisioning).to receive(:lock!) # rubocop:disable RSpec/AnyInstance
        .and_raise(ActiveRecord::RecordNotFound.new("Couldn't find BillLlmProvisioning"))

      expect(Llm::Client).not_to receive(:build)
      expect { job.perform(bill.id) }.not_to raise_error

      expect(SwayLogging).to have_received(:warn)
        .with("generate_bill_summary.provisioning_vanished", any_args)
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One lock shared by the job and the persist guard]]
    it "does not clobber a row completed concurrently since the job loaded it (locked re-check)" do
      job = described_class.new(bill.id)
      job.enqueued_at = (described_class::STALE_AFTER + 1.hour).ago

      # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#Why the reclaim judgement lives on the row]]
      allow(SwayLogging).to receive(:warn) do
        BillLlmProvisioning.where(id: provisioning.id).update_all(generation_status: "completed")
      end

      job.perform(bill.id)

      expect(provisioning.reload.generation_status).to eq("completed")
    end

    it "runs normally when enqueued_at is within STALE_AFTER" do
      stub_app_config(:llm, llm_provider: "claude")
      adapter = instance_double(Llm::ClaudeAdapter, provider_label: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(adapter)
      expect(adapter).to receive(:generate_bill_summary).once.and_return(valid_payload)

      job = described_class.new(bill.id)
      job.enqueued_at = 1.minute.ago
      job.perform(bill.id)
    end
  end

  describe "#perform — provider routing (R1) and runtime isolation (iter-2 Q5)" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }
    let(:llamacpp_adapter) { instance_double(Llm::LlamacppAdapter, provider_label: "llamacpp") }

    it "routes to ClaudeAdapter when LLM_PROVIDER=claude and does NOT instantiate LlamacppAdapter" do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      expect(claude_adapter).to receive(:generate_bill_summary).once.and_return(valid_payload)
      expect(Llm::LlamacppAdapter).not_to receive(:new)

      described_class.perform_now(bill.id)
    end

    it "routes to LlamacppAdapter when LLM_PROVIDER=llamacpp and does NOT instantiate ClaudeAdapter" do
      stub_app_config(:llm, llm_provider: "llamacpp", llamacpp_model: "local")
      allow(Llm::Client).to receive(:build).with(provider: "llamacpp").and_return(llamacpp_adapter)
      expect(llamacpp_adapter).to receive(:generate_bill_summary).once.and_return(valid_payload)
      expect(Llm::ClaudeAdapter).not_to receive(:new)

      described_class.perform_now(bill.id)
    end

    it "defaults to llamacpp when the setting is unset" do
      stub_app_config(:llm, llm_provider: nil, llamacpp_model: "local")
      allow(Llm::Client).to receive(:build).with(provider: "llamacpp").and_return(llamacpp_adapter)
      expect(llamacpp_adapter).to receive(:generate_bill_summary).once.and_return(valid_payload)
      expect(Llm::ClaudeAdapter).not_to receive(:new)

      described_class.perform_now(bill.id)
    end
  end

  # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Failure logging preserves the committed outcome]]
  describe "#perform — a failed model call reaches the Activity Log" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
    end

    it "records a provider error when the call cannot be made" do
      allow(claude_adapter).to receive(:generate_bill_summary)
        .and_raise(Llm::TransportError, "connection reset by peer")

      expect { described_class.new.perform(bill.id) }
        .to raise_error(described_class::TransientBillSummaryError)

      entry = PipelineActivityLogEntry.where(event_type: "llm_provider_error").last
      expect(entry).not_to be_nil
      expect(entry&.severity).to eq("error")
      expect(entry&.message).to include("connection reset by peer")
    end

    it "records a parse failure, with the excerpt, when the answer does not fit the contract" do
      allow(claude_adapter).to receive(:generate_bill_summary)
        .and_raise(Llm::SchemaError, "summary_markdown is missing")

      expect { described_class.new.perform(bill.id) }
        .to raise_error(described_class::DeterministicBillSummaryError)

      entry = PipelineActivityLogEntry.where(event_type: "llm_json_parse_failure").last
      expect(entry).not_to be_nil
      expect(entry&.severity).to eq("error")
      # raw_excerpt is the field the flash path shortens, and until now nothing
      # in production ever produced one — so the shortening guarded a payload
      # that could not occur.
      expect(entry&.payload&.deep_stringify_keys&.fetch("raw_excerpt")).to include("summary_markdown is missing")
    end

    # The log entry is worth having and never worth losing the failure over: the
    # caller is about to re-raise the error that decides whether the job
    # retries, and a write to the same busy database must not replace it.
    it "still raises the original failure when the log write itself fails" do
      allow(claude_adapter).to receive(:generate_bill_summary)
        .and_raise(Llm::TransportError, "connection reset by peer")
      allow(SwayLogging).to receive(:warn)
      allow(PipelineActivityLogger).to receive(:log_llm_provider_error!)
        .and_raise(ActiveRecord::LockWaitTimeout, "database is locked")

      expect { described_class.new.perform(bill.id) }
        .to raise_error(described_class::TransientBillSummaryError, /connection reset by peer/)

      expect(SwayLogging).to have_received(:warn)
        .with("generate_bill_summary.activity_log_write_failed", any_args)
    end
  end

  describe "#perform — model read at call time (R7)" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
    end

    it "passes AdminSetting.singleton.summarization_model to the adapter on each perform" do
      AdminSetting.singleton.update!(summarization_model: "claude-haiku-5-5")
      received_models = [] #: Array[String]
      allow(claude_adapter).to receive(:generate_bill_summary) do |model:, **|
        received_models << model
        valid_payload
      end

      described_class.perform_now(bill.id)
      AdminSetting.singleton.update!(summarization_model: "claude-sonnet-5-5")
      described_class.perform_now(bill.id)

      expect(received_models).to eq(["claude-haiku-5-5", "claude-sonnet-5-5"])
    end

    # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    it "prefers the model the operator picked for this run over the AdminSetting default" do
      AdminSetting.singleton.update!(summarization_model: "claude-haiku-5-5")
      received = nil #: String?
      allow(claude_adapter).to receive(:generate_bill_summary) do |model:, **|
        received = model
        valid_payload
      end

      described_class.perform_now(bill.id, summarization_model: "claude-opus-5-5")

      expect(received).to eq("claude-opus-5-5")
      expect(AdminSetting.singleton.reload.summarization_model).to eq("claude-haiku-5-5")
    end

    # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    it "does not leak a per-run model override to another bill executed without one" do
      other_bill = create(
        :bill,
        sway_locale: bill.sway_locale,
        legislator: bill.legislator,
        scheduled_release_date_utc: 2.days.ago,
        extracted_text: "Section 2."
      )
      create(:bill_llm_provisioning, bill: other_bill)
      AdminSetting.singleton.update!(summarization_model: "claude-haiku-5-5")

      received_models = [] #: Array[String]
      allow(claude_adapter).to receive(:generate_bill_summary) do |model:, **|
        received_models << model
        valid_payload
      end

      described_class.perform_now(bill.id, summarization_model: "claude-opus-5-5")
      described_class.perform_now(other_bill.id)

      expect(received_models).to eq(["claude-opus-5-5", "claude-haiku-5-5"])
      expect(AdminSetting.singleton.reload.summarization_model).to eq("claude-haiku-5-5")
    end

    # The job is the last gate: a queue entry written before the model list
    # changed must not reach the adapter with an id Sway no longer offers.
    it "falls back to the AdminSetting default when the picked model is not supported" do
      AdminSetting.singleton.update!(summarization_model: "claude-sonnet-5-5")
      received = nil #: String?
      allow(claude_adapter).to receive(:generate_bill_summary) do |model:, **|
        received = model
        valid_payload
      end

      described_class.perform_now(bill.id, summarization_model: "gpt-9")

      expect(received).to eq("claude-sonnet-5-5")
    end
  end

  describe "#perform — provenance (R10)" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }
    let(:llamacpp_adapter) { instance_double(Llm::LlamacppAdapter, provider_label: "llamacpp") }

    it "records llm_provider='claude' and llm_model=AdminSetting on the Claude path" do
      stub_app_config(:llm, llm_provider: "claude")
      AdminSetting.singleton.update!(summarization_model: "claude-haiku-5-5")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)

      described_class.perform_now(bill.id)
      provisioning.reload
      expect(provisioning.llm_provider).to eq("claude")
      expect(provisioning.llm_model).to eq("claude-haiku-5-5")
    end

    it "records llm_provider='llamacpp' and llm_model from ENV on the llama.cpp path" do
      stub_app_config(:llm, llm_provider: "llamacpp", llamacpp_model: "test-model")
      allow(Llm::Client).to receive(:build).with(provider: "llamacpp").and_return(llamacpp_adapter)
      allow(llamacpp_adapter).to receive(:generate_bill_summary).and_return(valid_payload)

      described_class.perform_now(bill.id)
      provisioning.reload
      expect(provisioning.llm_provider).to eq("llamacpp")
      expect(provisioning.llm_model).to eq("test-model")
    end

    it "defaults llm_model to 'local' when the setting is unset on the llama.cpp path" do
      stub_app_config(:llm, llm_provider: nil, llamacpp_model: nil)
      allow(Llm::Client).to receive(:build).with(provider: "llamacpp").and_return(llamacpp_adapter)
      allow(llamacpp_adapter).to receive(:generate_bill_summary).and_return(valid_payload)

      described_class.perform_now(bill.id)
      provisioning.reload
      expect(provisioning.llm_model).to eq("local")
    end

    it "writes a completed-state provisioning row on success" do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)

      described_class.perform_now(bill.id)
      expect(provisioning.reload.generation_status).to eq("completed")
    end
  end

  describe "OpenRouter routing from its selected model" do
    let(:openrouter_adapter) { instance_double(Llm::OpenRouterAdapter, provider_label: "openrouter") }

    before do
      stub_const(
        "AdminSetting::SUPPORTED_MODELS",
        (AdminSetting::SUPPORTED_MODELS + Llm::ModelCatalog::OPENROUTER_ROUTES.values.map(&:label)).uniq
      )
      allow(Llm::Client).to receive(:build).and_call_original
      allow(Llm::Client).to receive(:build).with(provider: "openrouter").and_return(openrouter_adapter)
      allow(openrouter_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      allow(openrouter_adapter).to receive(:generate_bill_positions).and_return("draft_org_positions" => [])
    end

    [
      ["Deepseek Pro Latest", "~deepseek/deepseek-pro-latest"],
      ["Deepseek Flash Latest", "~deepseek/deepseek-flash-latest"],
      ["OpenRouter Auto", "openrouter/auto"]
    ].each do |display_name, api_model|
      it "routes #{display_name} to OpenRouter adapter with api_model #{api_model} when environment is claude" do
        stub_app_config(:llm, llm_provider: "claude")
        AdminSetting.singleton.update_columns(summarization_model: display_name)

        expect(openrouter_adapter).to receive(:generate_bill_summary).with(
          prompt: anything,
          model: api_model,
          schema: anything
        ).and_return(valid_payload)

        described_class.perform_now(bill.id)

        provisioning.reload
        expect(provisioning.llm_provider).to eq("openrouter")
        expect(provisioning.llm_model).to eq(api_model)
        expect(provisioning.generation_status).to eq("completed")
      end

      it "routes #{display_name} via per-run override when environment is llamacpp" do
        stub_app_config(:llm, llm_provider: "llamacpp")
        AdminSetting.singleton.update_columns(summarization_model: "claude-haiku-5-5")

        expect(openrouter_adapter).to receive(:generate_bill_summary).with(
          prompt: anything,
          model: api_model,
          schema: anything
        ).and_return(valid_payload)

        described_class.perform_now(bill.id, summarization_model: display_name)

        provisioning.reload
        expect(provisioning.llm_provider).to eq("openrouter")
        expect(provisioning.llm_model).to eq(api_model)
      end
    end

    it "proceeds with OpenRouter summarization even if local llama.cpp server is down" do
      stub_app_config(:llm, llm_provider: "llamacpp")
      allow(Rails.env).to receive(:development?).and_return(true)
      allow(described_class).to receive(:probe_llm_endpoint).and_return(false)

      AdminSetting.singleton.update_columns(summarization_model: "Deepseek Pro Latest")

      expect(openrouter_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      result = described_class.perform_now(bill.id)

      expect(result).not_to eq(:not_run)
      expect(provisioning.reload.generation_status).to eq("completed")
    end

    it "does not mutate standing AdminSetting when per-run OpenRouter override is used" do
      AdminSetting.singleton.update_columns(summarization_model: "claude-haiku-5-5")

      described_class.perform_now(bill.id, summarization_model: "Deepseek Pro Latest")

      expect(AdminSetting.singleton.reload.summarization_model).to eq("claude-haiku-5-5")
    end

    it "does not leak per-run OpenRouter override to sibling bill run" do
      stub_app_config(:llm, llm_provider: "claude")
      other_bill = create(
        :bill,
        sway_locale: bill.sway_locale,
        legislator: bill.legislator,
        scheduled_release_date_utc: 2.days.ago,
        extracted_text: "Section 2."
      )
      create(:bill_llm_provisioning, bill: other_bill)
      AdminSetting.singleton.update_columns(summarization_model: "claude-haiku-5-5")

      claude_adapter = instance_double(Llm::ClaudeAdapter, provider_label: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      allow(claude_adapter).to receive(:generate_bill_positions).and_return("draft_org_positions" => [])

      expect(openrouter_adapter).to receive(:generate_bill_summary).with(
        prompt: anything,
        model: "~deepseek/deepseek-pro-latest",
        schema: anything
      ).and_return(valid_payload)

      expect(claude_adapter).to receive(:generate_bill_summary).with(
        prompt: anything,
        model: "claude-haiku-5-5",
        schema: anything
      ).and_return(valid_payload)

      described_class.perform_now(bill.id, summarization_model: "Deepseek Pro Latest")
      described_class.perform_now(other_bill.id)
    end

    it "forwards reasoning_effort to openrouter adapter when model supports reasoning" do
      stub_app_config(:llm, llm_provider: "claude")

      expect(openrouter_adapter).to receive(:generate_bill_summary).with(
        prompt: anything,
        model: "~deepseek/deepseek-flash-latest",
        schema: anything,
        reasoning_effort: "high"
      ).and_return(valid_payload)

      described_class.perform_now(
        bill.id,
        summarization_model: "Deepseek Flash Latest",
        reasoning_effort: "high"
      )
    end

    it "forwards resolved route, adapter, and model to NewsClaimGroundingService when cited news articles are present" do
      stub_app_config(:llm, llm_provider: "claude")

      bill.update_columns(link: "https://legistar.baltimorecity.gov/bill/123")
      news_article = create(
        :news_article,
        canonical_url: "https://baltimoresun.com/news/council-bill-density",
        outlet_name: "The Baltimore Sun"
      )
      text_version = create(
        :news_article_text_version,
        :extracted,
        news_article: news_article,
        text: "The Baltimore City Council voted unanimously 14-0 on Monday night to approve the zoning density bill."
      )
      bna = create(
        :bill_news_article,
        :approved,
        bill: bill,
        news_article: news_article,
        current_text_version: text_version,
        match_kind: "direct"
      )

      cited_payload = {
        "summary_markdown" => "Council approved the bill [The Baltimore Sun](#{news_article.canonical_url}). Official details at [Legistar](#{bill.link}).",
        "full_breakdown_markdown" => "## Section 1\nDetails.",
        "categories" => ["Health", "Taxes"],
        "draft_org_positions" => [
          {"org_name" => "ACLU", "stance" => "support", "summary" => "Improves transparency."}
        ],
        "news_usage" => "cited",
        "cited_news_urls" => [news_article.canonical_url],
        "source_uses" => [
          {
            "bill_news_article_id" => bna.id,
            "text_version_id" => text_version.id,
            "claim_text" => "Council approved the bill",
            "evidence_excerpt" => "voted unanimously 14-0 on Monday night to approve the zoning density bill",
            "citation_url" => news_article.canonical_url
          }
        ]
      }

      allow(openrouter_adapter).to receive(:generate_bill_summary).with(
        prompt: anything,
        model: "~deepseek/deepseek-flash-latest",
        schema: anything,
        reasoning_effort: "high"
      ).and_return(cited_payload)

      expect(NewsClaimGroundingService).to receive(:call).with(
        hash_including(
          bill: bill,
          news_usage: "cited",
          persist: true,
          route: have_attributes(
            provider: :openrouter,
            api_model: "~deepseek/deepseek-flash-latest",
            reasoning_effort: "high"
          ),
          adapter: openrouter_adapter,
          model: "~deepseek/deepseek-flash-latest"
        )
      ).and_call_original

      allow(openrouter_adapter).to receive(:generate_news_claim_grounding).with(
        prompt: anything,
        model: "~deepseek/deepseek-flash-latest",
        schema: NEWS_CLAIM_GROUNDING_SCHEMA_HASH,
        reasoning_effort: "high"
      ).and_return({
        "verdict" => "supported",
        "reason" => "Council approved the bill is directly supported."
      })

      described_class.perform_now(
        bill.id,
        summarization_model: "Deepseek Flash Latest",
        reasoning_effort: "high"
      )
    end
  end

  describe "#perform — per-run summary instructions" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      allow(SwayLogging).to receive(:warn)
    end

    it "captures prompt payload: property-tax instruction is present in user_message and absent from system_prompt" do
      captured_payload = nil #: Llm::PromptPayload?
      allow(claude_adapter).to receive(:generate_bill_summary) do |prompt:, **|
        captured_payload = prompt
        valid_payload
      end

      described_class.perform_now(bill.id, summary_instructions: "Please include the property tax rate of 2.24%.")

      expect(captured_payload).not_to be_nil
      if captured_payload
        expect(captured_payload.user_message).to include("## Operator guidance")
        expect(captured_payload.user_message).to include("Please include the property tax rate of 2.24%.")
        expect(captured_payload.system_prompt).not_to include("## Operator guidance")
        expect(captured_payload.system_prompt).not_to include("property tax rate")
      end
    end

    it "does not pass operator guidance to the positions prompt" do
      provisioning.update!(extracted_testimony: "Support testimony from the Maryland Tenants Union.")
      captured_positions_payload = nil #: Llm::PromptPayload?
      allow(claude_adapter).to receive(:generate_bill_positions) do |prompt:, **|
        captured_positions_payload = prompt
        {"draft_org_positions" => []}
      end

      described_class.perform_now(bill.id, summary_instructions: "Please include the property tax rate of 2.24%.")

      expect(claude_adapter).to have_received(:generate_bill_positions)
      expect(captured_positions_payload).not_to be_nil
      if captured_positions_payload
        expect(captured_positions_payload.user_message).not_to include("## Operator guidance")
        expect(captured_positions_payload.user_message).not_to include("property tax rate")
        expect(captured_positions_payload.system_prompt).not_to include("## Operator guidance")
      else
        flunk "captured_positions_payload was nil"
      end
    end

    it "preserves non-ASCII whitespace such as U+00A0 in the prompt payload" do
      captured_payload = nil #: Llm::PromptPayload?
      allow(claude_adapter).to receive(:generate_bill_summary) do |prompt:, **|
        captured_payload = prompt
        valid_payload
      end

      described_class.perform_now(bill.id, summary_instructions: "\u00A0")

      expect(captured_payload).not_to be_nil
      if captured_payload
        expect(captured_payload.user_message).to include("## Operator guidance")
        expect(captured_payload.user_message).to include("\u00A0")
        expect(captured_payload.system_prompt).not_to include("## Operator guidance")
      else
        flunk "captured_payload was nil"
      end
    end

    it "does not leak instructions across runs on the same reused job instance" do
      job = described_class.new
      captured_payloads = []
      allow(claude_adapter).to receive(:generate_bill_summary) do |prompt:, **|
        captured_payloads << prompt
        valid_payload
      end

      job.perform(bill.id, summary_instructions: "Run 1 instructions")

      other_bill = create(:bill, extracted_text: "Section 2. Another bill.")
      create(:bill_llm_provisioning, :pending, :with_diff_content, bill: other_bill)
      job.job_id = SecureRandom.uuid
      job.perform(other_bill.id)

      expect(captured_payloads[0].user_message).to include("Run 1 instructions")
      expect(captured_payloads[1].user_message).not_to include("Run 1 instructions")
      expect(captured_payloads[1].user_message).not_to include("## Operator guidance")
    end

    it "retains summary_instructions across ActiveJob retries and serialization" do
      attempts = 0
      captured_payload = nil #: Llm::PromptPayload?
      allow(claude_adapter).to receive(:generate_bill_summary) do |prompt:, **|
        attempts += 1
        if attempts == 1
          raise Llm::TransportError.new("claude transport: 503 service unavailable")
        else
          captured_payload = prompt
          valid_payload
        end
      end

      job = described_class.new(bill.id, summary_instructions: "Retry instructions")
      job.perform_now

      expect(attempts).to eq(1)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).not_to be_empty
      retried_job_data = ActiveJob::Base.queue_adapter.enqueued_jobs.last
      expect(retried_job_data[:job]).to eq(described_class)
      expect(retried_job_data[:args]).to include(hash_including("summary_instructions" => "Retry instructions"))

      described_class.execute(retried_job_data)

      expect(attempts).to eq(2)
      expect(captured_payload).not_to be_nil
      if captured_payload
        expect(captured_payload.user_message).to include("## Operator guidance")
        expect(captured_payload.user_message).to include("Retry instructions")
        expect(captured_payload.system_prompt).not_to include("## Operator guidance")
        expect(captured_payload.system_prompt).not_to include("Retry instructions")
      else
        flunk "captured_payload was nil"
      end
    end
  end

  # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One armer for both the synchronous run and the batch]]
  describe "#perform — a row another execution already owns" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      allow(SwayLogging).to receive(:warn)
    end

    context "when the other execution commits between this job's load and its arm" do
      before do
        # A separate UPDATE, so this job's in-memory copy still says `pending` —
        # the other execution finishing while we sat in the queue. One-shot, so
        # a later read cannot put the row back and hide what the job did to it.
        other_writer_ran = false
        allow(SummaryRunMarker).to receive(:operator_paste?).and_wrap_original do |original, value|
          unless other_writer_ran
            other_writer_ran = true
            BillLlmProvisioning.where(id: provisioning.id).update_all(
              generation_status: "completed",
              summary_run_id: "the-other-executions-job-id",
              llm_summary: "Summary the other execution already paid for",
              llm_generated_at: Time.current
            )
          end
          original.call(value)
        end
      end

      it "makes no paid call" do
        described_class.new.perform(bill.id)

        expect(claude_adapter).not_to have_received(:generate_bill_summary)
      end

      it "leaves the settled row exactly as the other execution committed it" do
        described_class.new.perform(bill.id)

        provisioning.reload
        expect(provisioning.generation_status).to eq("completed")
        expect(provisioning.summary_run_id).to eq("the-other-executions-job-id")
        expect(provisioning.llm_summary).to eq("Summary the other execution already paid for")
      end

      it "says so in the log, so the stand-down is not silent" do
        described_class.new.perform(bill.id)

        expect(SwayLogging).to have_received(:warn)
          .with("generate_bill_summary.row_owned_by_another_run", hash_including(bill_id: bill.id))
      end
    end

    # The discriminator is STALENESS, not what `completed` means. A row that was
    # already settled when this job loaded it has no gap for another writer to
    # have used, so it is an ordinary regenerate and must still pay — which is
    # what the operator asked for.
    context "when the row was already settled at load, with an older run's marker on it" do
      before do
        BillLlmProvisioning.where(id: provisioning.id).update_all(
          generation_status: "completed",
          summary_run_id: "an-older-runs-job-id",
          llm_summary: "An older run's summary"
        )
      end

      it "arms and buys, because nothing moved while this job waited" do
        described_class.new.perform(bill.id)

        expect(claude_adapter).to have_received(:generate_bill_summary)
        expect(provisioning.reload.llm_summary).to eq(valid_payload["summary_markdown"])
      end

      # The counter-example to the NOT_RUN cases, so the outcome cannot be
      # over-corrected into "the pipeline never records summarize as done".
      it "tells its caller it settled the row" do
        expect(described_class.new.perform(bill.id)).to eq(described_class::SETTLED)
      end
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One armer for both the synchronous run and the batch]]
    context "when another execution is already inside its paid region" do
      before do
        BillLlmProvisioning.where(id: provisioning.id).update_all(
          generation_status: "generating",
          summary_run_id: SummaryRunMarker.run_claim("the-other-executions-job-id")
        )
      end

      it "makes no paid call" do
        described_class.new.perform(bill.id)

        expect(claude_adapter).not_to have_received(:generate_bill_summary)
      end

      # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
      it "tells its caller it did not run, so the stage is not recorded as done" do
        expect(described_class.new.perform(bill.id)).to eq(described_class::NOT_RUN)
      end

      it "leaves the other execution's claim on the row" do
        described_class.new.perform(bill.id)

        expect(provisioning.reload.summary_run_id)
          .to eq(SummaryRunMarker.run_claim("the-other-executions-job-id"))
      end

      it "says so in the log, so the stand-down is not silent" do
        described_class.new.perform(bill.id)

        expect(SwayLogging).to have_received(:warn)
          .with("generate_bill_summary.row_owned_by_another_run", hash_including(bill_id: bill.id))
      end
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One armer for both the synchronous run and the batch]]
    context "when the row is generating with no claim on it at all" do
      before do
        BillLlmProvisioning.where(id: provisioning.id).update_all(
          generation_status: "generating", summary_run_id: nil
        )
      end

      it "makes no paid call" do
        described_class.new.perform(bill.id)

        expect(claude_adapter).not_to have_received(:generate_bill_summary)
      end
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#Why the reclaim judgement lives on the row]]
    context "when a generating row was abandoned by a worker that never came back" do
      before do
        BillLlmProvisioning.where(id: provisioning.id).update_all(
          generation_status: "generating",
          summary_run_id: SummaryRunMarker.run_claim("a-job-id-no-execution-carries-any-more"),
          updated_at: (GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER + 1.minute).ago
        )
      end

      it "takes the row over and generates, rather than leaving the bill without a summary forever" do
        described_class.new.perform(bill.id)

        expect(claude_adapter).to have_received(:generate_bill_summary)
        expect(provisioning.reload.generation_status).to eq("completed")
      end

      it "says so in the log, because an abandoned run means a worker died" do
        described_class.new.perform(bill.id)

        expect(SwayLogging).to have_received(:warn)
          .with("generate_bill_summary.reclaimed_abandoned_run", hash_including(bill_id: bill.id))
      end

      # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One armer for both the synchronous run and the batch]]
      it "restarts the abandonment clock as it takes the row over, so a second arrival cannot take it too" do
        seen_at_call_time = nil #: ActiveSupport::TimeWithZone?
        allow(claude_adapter).to receive(:generate_bill_summary) do
          seen_at_call_time = BillLlmProvisioning.find(provisioning.id).updated_at
          valid_payload
        end

        described_class.new.perform(bill.id)

        expect(seen_at_call_time).to be > GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER.ago
      end
    end

    # The counter-example, so the reclaim cannot be over-corrected into "any
    # foreign claim may be taken". Alone, either example passes on a guard that
    # was simply deleted; together they pin the window.
    context "when another execution's claim is younger than the reclaim window" do
      before do
        BillLlmProvisioning.where(id: provisioning.id).update_all(
          generation_status: "generating",
          summary_run_id: SummaryRunMarker.run_claim("an-execution-that-is-still-alive"),
          updated_at: 1.minute.ago
        )
      end

      it "still declines, and leaves the live run's claim alone" do
        described_class.new.perform(bill.id)

        expect(claude_adapter).not_to have_received(:generate_bill_summary)
        expect(provisioning.reload.summary_run_id)
          .to eq(SummaryRunMarker.run_claim("an-execution-that-is-still-alive"))
      end
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One armer for both the synchronous run and the batch]]
    context "when an operator's paste lands between this run's load and its arm" do
      let(:pasted_body) { "A summary an operator wrote by hand while the run was in flight." }
      let(:job) { described_class.new(bill.id) }

      before do
        BillLlmProvisioning.where(id: provisioning.id).update_all(
          generation_status: "generating",
          summary_run_id: SummaryRunMarker.run_claim(job.job_id)
        )

        paste_landed = false
        allow(SummaryRunMarker).to receive(:operator_paste?).and_wrap_original do |original, value|
          unless paste_landed
            paste_landed = true
            BillLlmProvisioning.where(id: provisioning.id).update_all(
              summary_run_id: SummaryRunMarker.operator_paste,
              llm_summary: pasted_body,
              llm_generated_at: Time.current
            )
          end
          original.call(value)
        end
      end

      it "completes the hand-off the paste deferred, and buys nothing" do
        job.perform(bill.id)

        expect(claude_adapter).not_to have_received(:generate_bill_summary)
        expect(provisioning.reload.generation_status).to eq("completed")
        expect(provisioning.llm_summary).to eq(pasted_body)
      end

      # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One armer for both the synchronous run and the batch]]
      it "enqueues no score recompute for a stand-down that bought nothing" do
        allow(RecomputeBillInterestingScoreJob).to receive(:perform_later)

        job.perform(bill.id)

        expect(RecomputeBillInterestingScoreJob).not_to have_received(:perform_later)
      end

      it "returns STOOD_DOWN rather than SETTLED, since neither paid call was made" do
        expect(job.perform(bill.id)).to eq(described_class::STOOD_DOWN)
      end
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One armer for both the synchronous run and the batch]]
    context "when an operator's paste settles the row itself before this run's arm" do
      let(:pasted_body) { "A summary an operator wrote by hand onto a finished row." }
      let(:job) { described_class.new(bill.id) }

      before do
        BillLlmProvisioning.where(id: provisioning.id).update_all(
          generation_status: "completed",
          summary_run_id: "an-older-runs-job-id",
          llm_summary: "An older run's summary"
        )

        # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One armer for both the synchronous run and the batch]]
        paste_landed = false
        allow(SummaryRunMarker).to receive(:operator_paste?).and_wrap_original do |original, value|
          unless paste_landed
            paste_landed = true
            BillLlmProvisioning.where(id: provisioning.id).update_all(
              summary_run_id: SummaryRunMarker.operator_paste,
              llm_summary: pasted_body,
              llm_generated_at: Time.current
            )
          end
          original.call(value)
        end
      end

      it "never commits the row into a run, so there is no window to be caught in" do
        committed_status_after_the_arm = nil #: String?
        allow(job).to receive(:clear_stale_run_state_unless_superseded!).and_wrap_original do |original, target_bill, target_provisioning|
          committed_status_after_the_arm = BillLlmProvisioning.find(provisioning.id).generation_status
          original.call(target_bill, target_provisioning)
        end

        job.perform(bill.id)

        expect(committed_status_after_the_arm).to be_nil,
          "the arm proceeded over a settled paste and committed the row as " \
          "#{committed_status_after_the_arm.inspect} under an operator-paste marker"
      end

      it "leaves the hand-written body and its marker exactly as the paste left them" do
        job.perform(bill.id)

        expect(claude_adapter).not_to have_received(:generate_bill_summary)
        expect(provisioning.reload.generation_status).to eq("completed")
        expect(provisioning.llm_summary).to eq(pasted_body)
        expect(SummaryRunMarker.operator_paste?(provisioning.summary_run_id)).to be(true)
      end

      it "says which row of the table sent it home, in words that fit what happened" do
        allow(SwayLogging).to receive(:warn).and_call_original

        job.perform(bill.id)

        expect(SwayLogging).to have_received(:warn).with(
          "generate_bill_summary.row_owned_by_another_run",
          hash_including(decision: :paste_already_settled)
        )
      end

      it "writes an activity log entry naming Regenerate, not the upstream stages" do
        job.perform(bill.id)

        entry = PipelineActivityLogEntry.find_by(event_type: "summary_stood_down_for_paste", subject: bill) #: PipelineActivityLogEntry
        expect(entry).not_to be_nil
        expect(entry.severity).to eq("info")
        expect(entry.message).to include(bill.external_id)
        expect(entry.message).to include("Regenerate")
        expect(entry.message).not_to include("extract-text")
      end
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
    context "when an operator's paste lands after the run's last stand-down" do
      let(:pasted_body) { "A summary an operator wrote by hand while the call was in flight." }
      let(:job) { described_class.new(bill.id) }

      def land_the_paste!
        BillLlmProvisioning.where(id: provisioning.id).update_all(
          summary_run_id: SummaryRunMarker.operator_paste,
          llm_summary: pasted_body,
          llm_provider: "operator_paste",
          llm_generated_at: Time.current
        )
      end

      # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
      it "finishes the hand-off rather than failing the row an operator now owns" do
        allow(claude_adapter).to receive(:generate_bill_summary) do
          land_the_paste!
          raise Llm::TransportError, "the model timed out"
        end

        expect { job.perform(bill.id) }.to raise_error(described_class::TransientBillSummaryError)

        provisioning.reload
        expect(provisioning.generation_status).to eq("completed")
        expect(provisioning.llm_summary).to eq(pasted_body)
        expect(provisioning.generation_error).to be_nil
      end

      # #settle_nothing_to_generate. A bill with neither input makes no paid
      # call at all, so the whole run is a window: the paste lands and the
      # settle writes "nothing to summarize" onto a row that now holds a summary
      # somebody typed.
      it "finishes the hand-off rather than settling a row that now holds a summary" do
        bill.update!(extracted_text: nil)
        allow(SwayLogging).to receive(:warn) do |key, *|
          land_the_paste! if key == "generate_bill_summary.nothing_to_generate"
        end

        job.perform(bill.id)

        provisioning.reload
        expect(provisioning.generation_status).to eq("completed")
        expect(provisioning.llm_summary).to eq(pasted_body)
        expect(provisioning.generation_error).to be_nil
      end

      it "writes an activity log entry naming Regenerate, not a nothing-to-generate skip" do
        bill.update!(extracted_text: nil)
        allow(SwayLogging).to receive(:warn) do |key, *|
          land_the_paste! if key == "generate_bill_summary.nothing_to_generate"
        end

        job.perform(bill.id)

        entry = PipelineActivityLogEntry.find_by(event_type: "summary_stood_down_for_paste", subject: bill) #: PipelineActivityLogEntry
        expect(entry).not_to be_nil
        expect(entry.severity).to eq("info")
        expect(entry.message).to include(bill.external_id)
        expect(entry.message).to include("Regenerate")
        expect(PipelineActivityLogEntry.exists?(event_type: "summary_skipped_no_source_text", subject: bill))
          .to be(false)
      end
    end

    # The other direction, so the guard cannot be over-corrected into locking a
    # worker out of its own enqueue. A worker killed mid-run (a deploy, the Pi
    # running out of memory) leaves the row `generating` under ITS claim, and
    # the re-execution carries the same job_id.
    context "when the generating row carries this execution's own marker" do
      it "carries on under its own claim, because the run is its own" do
        job = described_class.new(bill.id)
        BillLlmProvisioning.where(id: provisioning.id).update_all(
          generation_status: "generating",
          summary_run_id: SummaryRunMarker.run_claim(job.job_id)
        )

        job.perform(bill.id)

        expect(claude_adapter).to have_received(:generate_bill_summary)
      end

      it "carries on under its own purchase receipt, and settles rather than re-buying" do
        job = described_class.new(bill.id)
        BillLlmProvisioning.where(id: provisioning.id).update_all(
          generation_status: "generating",
          summary_run_id: job.job_id,
          llm_summary: "A summary this enqueue already paid for"
        )

        job.perform(bill.id)

        expect(claude_adapter).not_to have_received(:generate_bill_summary)
        expect(provisioning.reload.generation_status).to eq("completed")
      end
    end

    # The mechanism the three contexts above rest on. The claim has to be
    # standing for the WHOLE paid region, or a job arriving mid-call finds a row
    # that is generating for nobody and reads that as free.
    it "claims the row before it spends anything" do
      job = described_class.new(bill.id)
      claim_at_call_time = nil #: String?
      allow(claude_adapter).to receive(:generate_bill_summary) do
        claim_at_call_time = BillLlmProvisioning.find(provisioning.id).summary_run_id
        valid_payload
      end

      job.perform(bill.id)

      expect(claim_at_call_time).to eq(SummaryRunMarker.run_claim(job.job_id))
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One armer for both the synchronous run and the batch]]
    context "when this execution resumes on its own purchase receipt" do
      let(:job) { described_class.new(bill.id) }
      let(:positions_payload) do
        {
          "draft_org_positions" => [
            {"org_name" => "ACLU", "stance" => "support", "summary" => "Testified in support."}
          ]
        }
      end

      before do
        allow(claude_adapter).to receive(:generate_bill_positions).and_return(positions_payload)
        BillLlmProvisioning.where(id: provisioning.id).update_all(
          generation_status: "generating",
          summary_run_id: job.job_id,
          llm_summary: "A summary this enqueue already paid for",
          extracted_testimony: "Testimony submitted at the hearing on this bill.",
          draft_org_positions: nil,
          updated_at: (GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER + 1.minute).ago
        )
      end

      it "restarts the abandonment clock, so nothing can reclaim it mid-call" do
        seen_at_call_time = nil #: ActiveSupport::TimeWithZone?
        allow(claude_adapter).to receive(:generate_bill_positions) do
          seen_at_call_time = BillLlmProvisioning.find(provisioning.id).updated_at
          positions_payload
        end

        job.perform(bill.id)

        expect(seen_at_call_time).to be > GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER.ago
      end

      # The other half, so the clock fix cannot be made by stamping a claim
      # over the receipt: the re-entry gate reads the receipt, and replacing it
      # would tell the next execution nothing had been bought.
      it "keeps the purchase receipt while it does so" do
        receipt_at_call_time = nil #: String?
        allow(claude_adapter).to receive(:generate_bill_positions) do
          receipt_at_call_time = BillLlmProvisioning.find(provisioning.id).summary_run_id
          positions_payload
        end

        job.perform(bill.id)

        expect(receipt_at_call_time).to eq(job.job_id)
        expect(claude_adapter).not_to have_received(:generate_bill_summary)
      end
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One armer for both the synchronous run and the batch]]
    context "when the row is both paste-marked and older than the reclaim window" do
      let(:job) { described_class.new(bill.id) }

      before do
        BillLlmProvisioning.where(id: provisioning.id).update_all(
          generation_status: "generating",
          summary_run_id: SummaryRunMarker.run_claim(job.job_id),
          updated_at: (GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER + 1.minute).ago
        )

        # Drive the paste in through the window the arm actually sees: the
        # supersede gate reads the loaded copy, so a marker seeded up front
        # never reaches the arm at all.
        paste_landed = false
        allow(SummaryRunMarker).to receive(:operator_paste?).and_wrap_original do |original, value|
          unless paste_landed
            paste_landed = true
            BillLlmProvisioning.where(id: provisioning.id).update_all(
              summary_run_id: SummaryRunMarker.operator_paste,
              llm_summary: "A summary an operator wrote by hand.",
              llm_generated_at: Time.current
            )
          end
          original.call(value)
        end
      end

      it "does not log a reclaim for a row it is about to stand down on" do
        job.perform(bill.id)

        expect(SwayLogging).not_to have_received(:warn)
          .with("generate_bill_summary.reclaimed_abandoned_run", anything)
      end

      it "still completes the paste hand-off" do
        job.perform(bill.id)

        expect(claude_adapter).not_to have_received(:generate_bill_summary)
        expect(provisioning.reload.generation_status).to eq("completed")
      end
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#One settle shared by the job and the ingest]]
  describe "#perform — the settle its locked re-check declined" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }
    let(:positions_payload) do
      {
        "draft_org_positions" => [
          {"org_name" => "Maryland Tenants Union", "stance" => "support", "summary" => "Testified in support."}
        ]
      }
    end

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      allow(SwayLogging).to receive(:info)
      allow(SwayLogging).to receive(:warn)
      allow(RecomputeBillInterestingScoreJob).to receive(:perform_later)
      provisioning.update!(extracted_testimony: "Testimony from the hearing record.")
      # Another writer settles the row while the positions call is in flight —
      # a separate UPDATE, so this job's copy still says `generating`.
      allow(claude_adapter).to receive(:generate_bill_positions) do
        BillLlmProvisioning.where(id: provisioning.id).update_all(generation_status: "failed")
        positions_payload
      end
    end

    it "does not log success for a settle it did not make" do
      described_class.perform_now(bill.id)

      expect(SwayLogging).not_to have_received(:info).with("generate_bill_summary.success", anything)
    end

    it "schedules no score recompute for a settle it did not make" do
      described_class.perform_now(bill.id)

      expect(RecomputeBillInterestingScoreJob).not_to have_received(:perform_later)
    end

    # @lat: [[explanation/llm-summaries#Batch summarisation#One settle shared by the job and the ingest]]
    context "when the positions call raised and the summary was not bought" do
      let(:bill) { create(:bill) }
      let!(:provisioning) do
        create(:bill_llm_provisioning, :pending, bill: bill,
          extracted_testimony: "Testimony from the hearing record.",
          llm_summary: "A summary an earlier run already bought")
      end

      it "enqueues no score recompute, because nothing the score reads moved" do
        allow(claude_adapter).to receive(:generate_bill_positions)
          .and_raise(Llm::TransportError, "claude transport: 429 rate limit")

        described_class.perform_now(bill.id)

        expect(provisioning.reload.generation_status).to eq("completed")
        expect(RecomputeBillInterestingScoreJob).not_to have_received(:perform_later)
      end
    end

    # The other side of the wire: an ordinary run that really does settle must
    # still say so and still schedule the recompute, so the examples above
    # cannot pass on a method that has gone silent.
    it "still says so when the settle happens" do
      allow(claude_adapter).to receive(:generate_bill_positions).and_return(positions_payload)

      described_class.perform_now(bill.id)

      expect(provisioning.reload.generation_status).to eq("completed")
      expect(SwayLogging).to have_received(:info).with(
        "generate_bill_summary.success", hash_including(bill_id: bill.id)
      )
      expect(RecomputeBillInterestingScoreJob).to have_received(:perform_later).with(bill.id)
    end
  end

  # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One armer for both the synchronous run and the batch]]
  describe "#perform — the row is destroyed before any paid call" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      allow(claude_adapter).to receive(:generate_bill_positions).and_return({"draft_org_positions" => []})
      allow(SwayLogging).to receive(:warn)
      # The operator destroys the bill after clicking Generate. Deleted through
      # the relation rather than the loaded object, so the job's copy is
      # unaware — the shape the "tolerates the row being deleted mid-flight"
      # example already uses.
      allow_any_instance_of(BillLlmProvisioning).to receive(:can_start_generating?).and_wrap_original do |original|
        BillLlmProvisioning.where(id: provisioning.id).delete_all
        original.call
      end
    end

    it "buys nothing" do
      expect(claude_adapter).not_to receive(:generate_bill_summary)
      expect(claude_adapter).not_to receive(:generate_bill_positions)

      described_class.perform_now(bill.id)
    end

    it "says why it stopped" do
      described_class.perform_now(bill.id)

      expect(SwayLogging).to have_received(:warn).with(
        "generate_bill_summary.row_gone_before_paid_calls",
        hash_including(bill_id: bill.id)
      )
    end

    # The row-gone pair matters most of the four unpinned paths: it is the one
    # case where no other writer will settle the row, so the bill genuinely
    # needs the pipeline to come back for it. This is the arm's half — the row
    # went while the arm held it, so #arm_row_unless_owned! answers nil. (B24-10)
    it "tells its caller it did not run, so the stage is not recorded as done" do
      expect(described_class.new.perform(bill.id)).to eq(described_class::NOT_RUN)
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#What settles a bill once its items are accounted for]]
  describe "#perform — the row is destroyed between the arm and the clear" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      allow(claude_adapter).to receive(:generate_bill_positions).and_return({"draft_org_positions" => []})
      allow(SwayLogging).to receive(:warn)
    end

    it "tells its caller it did not run, and buys nothing" do
      job = described_class.new
      allow(job).to receive(:arm_row_unless_owned!).and_wrap_original do |original, target_bill, target_provisioning|
        armed = original.call(target_bill, target_provisioning)
        BillLlmProvisioning.where(id: provisioning.id).delete_all
        armed
      end

      expect(job.perform(bill.id)).to eq(described_class::NOT_RUN)
      expect(claude_adapter).not_to have_received(:generate_bill_summary)
    end
  end

  # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
  describe "#perform — the row is destroyed while the bought summary is being persisted" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary) do
        BillLlmProvisioning.where(id: provisioning.id).delete_all
        valid_payload
      end
      allow(claude_adapter).to receive(:generate_bill_positions).and_return({"draft_org_positions" => []})
      allow(SwayLogging).to receive(:warn)
    end

    it "tells its caller it did not run, rather than claiming the summary was saved" do
      expect(described_class.new.perform(bill.id)).to eq(described_class::NOT_RUN)
    end

    it "says the paid answer had nowhere to land" do
      described_class.new.perform(bill.id)

      expect(SwayLogging).to have_received(:warn).with(
        "generate_bill_summary.row_gone_after_paid_call",
        hash_including(bill_id: bill.id)
      )
    end

    it "buys no positions, since the summary half already found no row" do
      described_class.new.perform(bill.id)

      expect(claude_adapter).not_to have_received(:generate_bill_positions)
    end
  end

  # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
  describe "#perform — the row is destroyed while the bought positions are being persisted" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }
    let!(:provisioning) do
      create(:bill_llm_provisioning, :pending, :with_diff_content, :with_testimony, bill: bill)
    end

    before do
      bill.update!(summary: Bill::SUMMARY_PLACEHOLDER)
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      allow(claude_adapter).to receive(:generate_bill_positions) do
        BillLlmProvisioning.where(id: provisioning.id).delete_all
        {"draft_org_positions" => []}
      end
      allow(SwayLogging).to receive(:warn)
    end

    it "tells its caller it did not run, even though the summary already landed" do
      expect(described_class.new.perform(bill.id)).to eq(described_class::NOT_RUN)
    end

    it "says the paid answer had nowhere to land" do
      described_class.new.perform(bill.id)

      expect(SwayLogging).to have_received(:warn).with(
        "generate_bill_summary.row_gone_after_paid_call",
        hash_including(bill_id: bill.id)
      )
    end

    it "leaves the summary it already bought published on the bill" do
      described_class.new.perform(bill.id)

      expect(bill.reload.summary).to eq(valid_payload["summary_markdown"])
    end
  end

  describe "#perform — transient error → TransientBillSummaryError (retry_on)" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary)
        .and_raise(Llm::TransportError.new("claude transport: 429 rate_limit"))
    end

    it "wraps Llm::TransportError as TransientBillSummaryError preserving the prefix" do
      expect {
        # perform_now skips retry_on; this checks the wrapping, not the retry policy
        described_class.new.perform(bill.id)
      }.to raise_error(described_class::TransientBillSummaryError, /^claude transport: 429 rate_limit/)
    end

    it "calls record_failure: provisioning is marked failed with the prefix in generation_error" do
      expect {
        described_class.new.perform(bill.id)
      }.to raise_error(described_class::TransientBillSummaryError)
      provisioning.reload
      expect(provisioning.generation_status).to eq("failed")
      expect(provisioning.generation_error.to_s).to match(/^claude transport:/)
    end

    # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Failure logging preserves the committed outcome]]
    it "does not relabel a row another writer settled while the adapter call was in flight" do
      allow(claude_adapter).to receive(:generate_bill_summary) do
        # A separate UPDATE, so the job's in-memory copy still says
        # "generating" — exactly the stale read described above.
        BillLlmProvisioning.where(id: provisioning.id).update_all(
          generation_status: "completed",
          llm_summary: "Summary the other writer already paid for and committed"
        )
        raise Llm::TransportError, "claude transport: 429 rate_limit"
      end

      expect {
        described_class.new.perform(bill.id)
      }.to raise_error(described_class::TransientBillSummaryError)

      provisioning.reload
      expect(provisioning.generation_status).to eq("completed")
      expect(provisioning.generation_error).to be_nil
      expect(provisioning.llm_summary).to eq("Summary the other writer already paid for and committed")
    end

    # The row can also be deleted while the call is in flight, if an operator
    # destroys the bill. record_failure must not turn that into a second,
    # unrelated exception that replaces the wrapped transport error the caller is
    # about to raise.
    it "tolerates the row being deleted mid-flight" do
      allow(claude_adapter).to receive(:generate_bill_summary) do
        BillLlmProvisioning.where(id: provisioning.id).delete_all
        raise Llm::TransportError, "claude transport: 429 rate_limit"
      end

      expect {
        described_class.new.perform(bill.id)
      }.to raise_error(described_class::TransientBillSummaryError, /^claude transport:/)
    end
  end

  describe "#perform — an error before the run started" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary)
        .and_raise(Llm::TransportError.new("claude transport: connection reset"))
    end

    it "settles a row whose start was skipped, instead of stranding it pending" do
      allow_any_instance_of(BillLlmProvisioning).to receive(:can_start_generating?).and_return(false)

      expect {
        described_class.new.perform(bill.id)
      }.to raise_error(described_class::TransientBillSummaryError)

      provisioning.reload
      expect(provisioning.generation_status).to eq("failed")
      expect(provisioning.generation_error.to_s).to match(/^claude transport:/)
      expect(provisioning.can_enqueue?).to be(true)
    end

    it "settles a row another writer put back to pending while the call was in flight" do
      allow(claude_adapter).to receive(:generate_bill_summary) do
        BillLlmProvisioning.where(id: provisioning.id).update_all(generation_status: "pending")
        raise Llm::TransportError, "claude transport: connection reset"
      end

      expect {
        described_class.new.perform(bill.id)
      }.to raise_error(described_class::TransientBillSummaryError)

      expect(provisioning.reload.generation_status).to eq("failed")
    end
  end

  describe ".llm_endpoint_down?" do
    it "answers false outside development, so the suite never probes" do
      stub_app_config(:llm, llm_provider: "llamacpp")

      expect(described_class).not_to receive(:probe_llm_endpoint)
      expect(described_class.llm_endpoint_down?).to be(false)
    end

    it "answers false in development when the provider is not the local server" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      stub_app_config(:llm, llm_provider: "claude")

      expect(described_class.llm_endpoint_down?).to be(false)
    end

    it "answers true in development when the local server refuses the connection" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      allow(Faraday).to receive(:new).and_raise(Faraday::ConnectionFailed.new("refused"))
      stub_app_config(:llm, llm_provider: "llamacpp")

      expect(described_class.llm_endpoint_down?).to be(true)
    end
  end

  describe "#perform — the local model server is not answering" do
    before do
      described_class.instance_variable_set(:@llm_endpoint_warned_at, nil)
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      stub_app_config(:llm, llm_provider: "llamacpp")
      allow(described_class).to receive(:probe_llm_endpoint).and_return(false)
      allow(Llm::Client).to receive(:build)
      allow(SwayLogging).to receive(:warn)
    end

    after { described_class.instance_variable_set(:@llm_endpoint_warned_at, nil) }

    it "declines every bill in the fan-out, buys nothing, and says so once" do
      expect(described_class.new.perform(bill.id)).to eq(described_class::NOT_RUN)
      expect(described_class.new.perform(bill.id)).to eq(described_class::NOT_RUN)

      expect(Llm::Client).not_to have_received(:build)
      expect(SwayLogging).to have_received(:warn)
        .with("generate_bill_summary.llm_endpoint_down", any_args).once
      expect(provisioning.reload.generation_status).to eq("pending")
    end
  end

  describe "#perform — deterministic error → DeterministicBillSummaryError (discard_on)" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary)
        .and_raise(Llm::SchemaError.new("Schema validation failed: required key 'summary_markdown' missing"))
    end

    it "wraps Llm::SchemaError as DeterministicBillSummaryError preserving the prefix" do
      expect {
        described_class.new.perform(bill.id)
      }.to raise_error(described_class::DeterministicBillSummaryError, /^Schema validation failed/)
    end

    it "calls record_failure: provisioning is marked failed with the prefix in generation_error" do
      expect {
        described_class.new.perform(bill.id)
      }.to raise_error(described_class::DeterministicBillSummaryError)
      provisioning.reload
      expect(provisioning.generation_status).to eq("failed")
      expect(provisioning.generation_error.to_s).to match(/Schema validation failed|Malformed JSON/)
    end
  end

  # An unexpected adapter error — one that is not an Llm::* error — must still
  # mark the row failed, rather than leave it stuck at `generating` because
  # mark_failed! was never called.
  describe "#perform — unexpected adapter error → TransientBillSummaryError" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary)
        .and_raise(NoMethodError.new("undefined method 'text' for tool_use block"))
    end

    it "wraps unexpected StandardError as TransientBillSummaryError with class+message context" do
      expect {
        described_class.new.perform(bill.id)
      }.to raise_error(
        described_class::TransientBillSummaryError,
        /unexpected adapter error: NoMethodError: undefined method 'text'/
      )
    end

    it "calls record_failure so provisioning is NOT stuck in `generating`" do
      expect {
        described_class.new.perform(bill.id)
      }.to raise_error(described_class::TransientBillSummaryError)
      provisioning.reload
      expect(provisioning.generation_status).to eq("failed")
      expect(provisioning.generation_error.to_s).to match(/unexpected adapter error/)
    end
  end

  # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
  describe "#perform — an operator paste supersedes a queued run" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      allow(claude_adapter).to receive(:generate_bill_positions)
        .and_return({"draft_org_positions" => []})
      allow(SwayLogging).to receive(:warn)
    end

    # The case that had to be caught, end to end through the real paste service:
    # the row is `pending` with a job queued against it, the operator pastes, and
    # then the job drains.
    it "does not overwrite a summary pasted onto the row it was queued against" do
      PasteSummaryService.new(
        bill: bill,
        actor: create(:user),
        summary_json: {summary_markdown: "## Hand-written by the operator"}.to_json
      ).call

      described_class.perform_now(bill.id)

      expect(provisioning.reload.llm_summary).to eq("## Hand-written by the operator")
    end

    it "buys nothing — neither paid call is made" do
      PasteSummaryService.new(
        bill: bill,
        actor: create(:user),
        summary_json: {summary_markdown: "## Hand-written by the operator"}.to_json
      ).call

      described_class.perform_now(bill.id)

      expect(claude_adapter).not_to have_received(:generate_bill_summary)
      expect(claude_adapter).not_to have_received(:generate_bill_positions)
    end

    it "returns STOOD_DOWN rather than SETTLED, since neither paid call was made" do
      PasteSummaryService.new(
        bill: bill,
        actor: create(:user),
        summary_json: {summary_markdown: "## Hand-written by the operator"}.to_json
      ).call

      expect(described_class.perform_now(bill.id)).to eq(described_class::STOOD_DOWN)
    end

    # The paste deliberately leaves the row unsettled; the job is what settles
    # it. Without this the row sits at `pending` forever, showing an in-flight
    # spinner over a summary that is already finished.
    it "settles the deferred row to completed instead of stranding it in flight" do
      PasteSummaryService.new(
        bill: bill,
        actor: create(:user),
        summary_json: {summary_markdown: "## Hand-written by the operator"}.to_json
      ).call
      expect(provisioning.reload.generation_status).to eq("pending")

      described_class.perform_now(bill.id)

      expect(provisioning.reload.generation_status).to eq("completed")
    end

    # @lat: [[explanation/llm-summaries#Batch summarisation#One settle shared by the job and the ingest]]
    it "leaves llm_generated_at at the paste's timestamp, because it generated nothing" do
      PasteSummaryService.new(
        bill: bill,
        actor: create(:user),
        summary_json: {summary_markdown: "## Hand-written by the operator"}.to_json
      ).call
      pasted_at = provisioning.reload.llm_generated_at

      described_class.perform_now(bill.id)

      expect(provisioning.reload.llm_generated_at).to eq(pasted_at)
    end

    it "reports the pasted row as stale once the pipeline data moves past it" do
      PasteSummaryService.new(
        bill: bill,
        actor: create(:user),
        summary_json: {summary_markdown: "## Hand-written by the operator"}.to_json
      ).call
      provisioning.reload.update!(diff_generated_at: provisioning.llm_generated_at + 1.hour)

      described_class.perform_now(bill.id)

      provisioning.reload
      expect(provisioning.stale?).to be(true)
      # And the provenance the client needs in order to explain it survives the
      # stand-down: the stale header's button asks for confirmation, and the
      # completed view renders an "Operator-pasted" chip from exactly this value.
      expect(provisioning.llm_provider).to eq("operator_paste")
    end

    it "records the stand-down rather than skipping silently" do
      PasteSummaryService.new(
        bill: bill,
        actor: create(:user),
        summary_json: {summary_markdown: "## Hand-written by the operator"}.to_json
      ).call

      described_class.perform_now(bill.id)

      expect(SwayLogging).to have_received(:warn).with(
        "generate_bill_summary.superseded_by_operator_paste",
        hash_including(bill_id: bill.id)
      )
    end

    it "writes an activity log entry naming Regenerate, not the upstream stages" do
      PasteSummaryService.new(
        bill: bill,
        actor: create(:user),
        summary_json: {summary_markdown: "## Hand-written by the operator"}.to_json
      ).call

      described_class.perform_now(bill.id)

      entry = PipelineActivityLogEntry.find_by(event_type: "summary_stood_down_for_paste", subject: bill) #: PipelineActivityLogEntry
      expect(entry).not_to be_nil
      expect(entry.severity).to eq("info")
      expect(entry.message).to include(bill.external_id)
      expect(entry.message).to include("Regenerate")
      expect(entry.message).not_to include("extract-text")
    end

    # The case the earlier guard cannot reach at all: the paste landed on a row
    # already in a final state, so settle_pasted_row! walked it to `completed` —
    # and the queued job's retry still drains afterwards and re-arms from
    # completed.
    it "does not overwrite a paste made onto a row a failed attempt left terminal" do
      provisioning.update!(generation_status: "failed", generation_error: "claude transport: 429")
      PasteSummaryService.new(
        bill: bill,
        actor: create(:user),
        summary_json: {summary_markdown: "## Pasted after the failure"}.to_json
      ).call

      described_class.perform_now(bill.id)

      expect(provisioning.reload.llm_summary).to eq("## Pasted after the failure")
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable]]
    it "still buys when the operator regenerates after pasting" do
      PasteSummaryService.new(
        bill: bill,
        actor: create(:user),
        summary_json: {summary_markdown: "## Hand-written by the operator"}.to_json
      ).call
      described_class.perform_now(bill.id)

      GenerateBillSummaryService.new(bill: bill, actor: create(:user), regenerate: true).call
      described_class.perform_now(bill.id)

      expect(claude_adapter).to have_received(:generate_bill_summary).once
      expect(provisioning.reload.llm_summary).to eq(valid_payload["summary_markdown"])
    end

    # That supersede is not silent either: it destroys hand-written work, so it
    # goes into the permanent record even though the operator asked for it.
    it "records that a deliberate regenerate is superseding a paste" do
      PasteSummaryService.new(
        bill: bill,
        actor: create(:user),
        summary_json: {summary_markdown: "## Hand-written by the operator"}.to_json
      ).call
      described_class.perform_now(bill.id)

      GenerateBillSummaryService.new(bill: bill, actor: create(:user), regenerate: true).call

      expect(SwayLogging).to have_received(:warn).with(
        "generate_bill_summary_service.superseding_operator_paste",
        hash_including(bill_id: bill.id)
      )
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
    describe "a superseded row is not re-armed first (D-IN-01)" do
      it "leaves a settled row's status alone instead of walking it through generating" do
        # A paste onto a row that is NOT in flight settles the row itself — that
        # is PasteSummaryService's ordinary branch. The failed state matters here
        # because `failed` is usually why an operator pastes in the first place.
        provisioning.update!(generation_status: "failed", generation_error: "claude transport: 429")
        PasteSummaryService.new(
          bill: bill, actor: create(:user),
          summary_json: {summary_markdown: "## Hand-written by the operator"}.to_json
        ).call
        expect(provisioning.reload.generation_status).to eq("completed")

        # Record the transitions the row is actually put through, on the instance
        # the job loads, instead of guessing from the end state — the end state
        # is `completed` either way, which is exactly why the churn went
        # unnoticed.
        seen = [] #: Array[String]
        allow_any_instance_of(BillLlmProvisioning).to receive(:enqueue!).and_wrap_original do |original|
          seen << "enqueue!"
          original.call
        end
        allow_any_instance_of(BillLlmProvisioning).to receive(:start_generating!).and_wrap_original do |original|
          seen << "start_generating!"
          original.call
        end

        described_class.perform_now(bill.id)

        expect(seen).to be_empty
        expect(provisioning.reload.generation_status).to eq("completed")
      end

      # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
      it "enqueues no score recompute for a row the paste already settled" do
        provisioning.update!(generation_status: "failed", generation_error: "claude transport: 429")
        PasteSummaryService.new(
          bill: bill, actor: create(:user),
          summary_json: {summary_markdown: "## Hand-written by the operator"}.to_json
        ).call
        allow(RecomputeBillInterestingScoreJob).to receive(:perform_later)

        described_class.perform_now(bill.id)

        expect(RecomputeBillInterestingScoreJob).not_to have_received(:perform_later)
      end

      # The other case, and the reason the check cannot simply return: a paste
      # onto a row that WAS in flight is deliberately left unsettled by
      # PasteSummaryService, which hands the status over to this job. That
      # hand-off still has to happen.
      it "still completes the hand-off for a row the paste deliberately left in flight" do
        PasteSummaryService.new(
          bill: bill, actor: create(:user),
          summary_json: {summary_markdown: "## Hand-written by the operator"}.to_json
        ).call
        expect(provisioning.reload.generation_status).to eq("pending")

        described_class.perform_now(bill.id)

        expect(provisioning.reload.generation_status).to eq("completed")
        expect(provisioning.llm_summary).to eq("## Hand-written by the operator")
      end

      # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
      it "enqueues no score recompute when it completes that hand-off" do
        PasteSummaryService.new(
          bill: bill, actor: create(:user),
          summary_json: {summary_markdown: "## Hand-written by the operator"}.to_json
        ).call
        expect(provisioning.reload.generation_status).to eq("pending")
        allow(RecomputeBillInterestingScoreJob).to receive(:perform_later)

        described_class.perform_now(bill.id)

        expect(provisioning.reload.generation_status).to eq("completed")
        expect(RecomputeBillInterestingScoreJob).not_to have_received(:perform_later)
      end

      # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
      it "leaves the row where the paste left it when the hand-off cannot finish" do
        PasteSummaryService.new(
          bill: bill, actor: create(:user),
          summary_json: {summary_markdown: "## Hand-written by the operator"}.to_json
        ).call
        expect(provisioning.reload.generation_status).to eq("pending")
        allow_any_instance_of(BillLlmProvisioning).to receive(:mark_completed!)
          .and_raise(ActiveRecord::StatementInvalid, "SQLite3::BusyException: database is locked")

        # .new.perform rather than .perform_now, the convention this file
        # already uses where the raise itself is the subject: retry_on catches
        # it at the ActiveJob layer and re-enqueues instead of raising.
        expect { described_class.new.perform(bill.id) }
          .to raise_error(described_class::TransientBillSummaryError)

        provisioning.reload
        expect(provisioning.generation_status).to eq("pending")
        expect(provisioning.generation_error).to be_nil
        expect(provisioning.llm_summary).to eq("## Hand-written by the operator")
        expect(SummaryRunMarker.operator_paste?(provisioning.summary_run_id)).to be(true)
      end

      # The other half: a row left exactly as the paste left it is one the
      # retry can finish. A row the failed attempt moved is not — the gate
      # re-runs, but from a state the paste never produced.
      it "lets the retry complete the hand-off it could not finish" do
        PasteSummaryService.new(
          bill: bill, actor: create(:user),
          summary_json: {summary_markdown: "## Hand-written by the operator"}.to_json
        ).call
        raising = true
        allow_any_instance_of(BillLlmProvisioning).to receive(:mark_completed!).and_wrap_original do |original|
          raise ActiveRecord::StatementInvalid, "SQLite3::BusyException: database is locked" if raising

          original.call
        end

        expect { described_class.new.perform(bill.id) }
          .to raise_error(described_class::TransientBillSummaryError)
        raising = false
        described_class.perform_now(bill.id)

        provisioning.reload
        expect(provisioning.generation_status).to eq("completed")
        expect(provisioning.llm_summary).to eq("## Hand-written by the operator")
      end
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
    describe "a paste that lands while the adapter call is in flight (D-WR-02)" do
      it "does not overwrite the pasted body with the summary it had already bought" do
        allow(claude_adapter).to receive(:generate_bill_summary) do
          PasteSummaryService.new(
            bill: Bill.find(bill.id), actor: create(:user),
            summary_json: {summary_markdown: "## Pasted while the call was in flight"}.to_json
          ).call
          valid_payload
        end

        described_class.perform_now(bill.id)

        expect(provisioning.reload.llm_summary).to eq("## Pasted while the call was in flight")
      end

      # Without this the body would survive one drain and be destroyed by the
      # next: summary_run_id is what makes the job stand down, and overwriting it
      # with job_id disarms the protection on the very row it was protecting.
      it "leaves the operator-paste marker on the row rather than stamping job_id over it" do
        allow(claude_adapter).to receive(:generate_bill_summary) do
          PasteSummaryService.new(
            bill: Bill.find(bill.id), actor: create(:user),
            summary_json: {summary_markdown: "## Pasted while the call was in flight"}.to_json
          ).call
          valid_payload
        end

        described_class.perform_now(bill.id)

        expect(SummaryRunMarker.operator_paste?(provisioning.reload.summary_run_id)).to be(true)
      end

      # The row must still leave `generating`, or the operator is left staring at
      # a spinner over their own text while both buttons answer
      # :already_in_progress for an hour.
      it "settles the row onto the pasted body instead of stranding it in flight" do
        allow(claude_adapter).to receive(:generate_bill_summary) do
          PasteSummaryService.new(
            bill: Bill.find(bill.id), actor: create(:user),
            summary_json: {summary_markdown: "## Pasted while the call was in flight"}.to_json
          ).call
          valid_payload
        end

        described_class.perform_now(bill.id)

        expect(provisioning.reload.generation_status).to eq("completed")
      end

      it "records the mid-run stand-down rather than discarding the purchase silently" do
        allow(claude_adapter).to receive(:generate_bill_summary) do
          PasteSummaryService.new(
            bill: Bill.find(bill.id), actor: create(:user),
            summary_json: {summary_markdown: "## Pasted while the call was in flight"}.to_json
          ).call
          valid_payload
        end

        described_class.perform_now(bill.id)

        expect(SwayLogging).to have_received(:warn).with(
          "generate_bill_summary.superseded_mid_run",
          hash_including(bill_id: bill.id)
        )
      end

      it "writes an activity log entry naming Regenerate, not the upstream stages" do
        allow(claude_adapter).to receive(:generate_bill_summary) do
          PasteSummaryService.new(
            bill: Bill.find(bill.id), actor: create(:user),
            summary_json: {summary_markdown: "## Pasted while the call was in flight"}.to_json
          ).call
          valid_payload
        end

        described_class.perform_now(bill.id)

        entry = PipelineActivityLogEntry.find_by(event_type: "summary_stood_down_for_paste", subject: bill) #: PipelineActivityLogEntry
        expect(entry).not_to be_nil
        expect(entry.severity).to eq("info")
        expect(entry.message).to include(bill.external_id)
        expect(entry.message).to include("Regenerate")
        expect(entry.message).not_to include("extract-text")
      end

      # The other place results get saved. On a testimony-only bill the positions
      # call is the only paid call of the run, so the summary is never saved, and
      # guarding that one alone would leave this path writing drafts — and,
      # worse, stamping job_id over the marker — onto a row a human now owns.
      it "does not write positions or disarm the marker when the paste lands during the positions call" do
        bill.update!(extracted_text: nil)
        provisioning.update!(diff_content: nil, extracted_testimony: "Testimony submitted at the hearing.")
        allow(claude_adapter).to receive(:generate_bill_positions) do
          PasteSummaryService.new(
            bill: Bill.find(bill.id), actor: create(:user),
            summary_json: {summary_markdown: "## Pasted during the positions call"}.to_json
          ).call
          {"draft_org_positions" => [{"org_name" => "ACLU", "stance" => "support", "summary" => "x"}]}
        end

        described_class.perform_now(bill.id)

        provisioning.reload
        expect(provisioning.draft_org_positions).to be_blank
        expect(SummaryRunMarker.operator_paste?(provisioning.summary_run_id)).to be(true)
        expect(provisioning.llm_summary).to eq("## Pasted during the positions call")
      end
    end
  end

  # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One lock shared by the job and the persist guard]]
  describe "#perform — re-entry after a post-persist failure does not re-buy (B4-CR-03)" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }
    let(:positions_payload) do
      {
        "draft_org_positions" => [
          {"org_name" => "Maryland Tenants Union", "stance" => "support", "summary" => "Testified in support."}
        ]
      }
    end

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      allow(claude_adapter).to receive(:generate_bill_positions).and_return(positions_payload)
      provisioning.update!(extracted_testimony: "Testimony of the Maryland Tenants Union in support.")
      allow(SwayLogging).to receive(:warn)
    end

    # A faithful copy of the retry the first attempt's failure triggers: a fresh
    # instance carrying the first attempt's job_id.
    def retry_of(job)
      retried = described_class.new(bill.id)
      retried.job_id = job.job_id
      retried
    end

    it "issues the summary call once across the failure and its retry" do
      allow(RecomputeBillInterestingScoreJob).to receive(:perform_later)
        .and_raise(ActiveRecord::StatementInvalid.new("SQLite3::BusyException: database is locked"))

      job = described_class.new(bill.id)
      expect { job.perform(bill.id) }.to raise_error(described_class::TransientBillSummaryError)

      allow(RecomputeBillInterestingScoreJob).to receive(:perform_later).and_return(nil)
      retry_of(job).perform(bill.id)

      expect(claude_adapter).to have_received(:generate_bill_summary).once
    end

    it "issues the positions call once across the failure and its retry" do
      allow(RecomputeBillInterestingScoreJob).to receive(:perform_later)
        .and_raise(ActiveRecord::StatementInvalid.new("SQLite3::BusyException: database is locked"))

      job = described_class.new(bill.id)
      expect { job.perform(bill.id) }.to raise_error(described_class::TransientBillSummaryError)

      allow(RecomputeBillInterestingScoreJob).to receive(:perform_later).and_return(nil)
      retry_of(job).perform(bill.id)

      expect(claude_adapter).to have_received(:generate_bill_positions).once
    end

    it "settles the row completed on the retry rather than leaving it failed" do
      allow(RecomputeBillInterestingScoreJob).to receive(:perform_later)
        .and_raise(ActiveRecord::StatementInvalid.new("SQLite3::BusyException: database is locked"))

      job = described_class.new(bill.id)
      expect { job.perform(bill.id) }.to raise_error(described_class::TransientBillSummaryError)

      allow(RecomputeBillInterestingScoreJob).to receive(:perform_later).and_return(nil)
      retry_of(job).perform(bill.id)

      expect(provisioning.reload.generation_status).to eq("completed")
    end

    it "leaves no stale failure message on the completed row" do
      allow(RecomputeBillInterestingScoreJob).to receive(:perform_later)
        .and_raise(ActiveRecord::StatementInvalid.new("SQLite3::BusyException: database is locked"))

      job = described_class.new(bill.id)
      expect { job.perform(bill.id) }.to raise_error(described_class::TransientBillSummaryError)

      allow(RecomputeBillInterestingScoreJob).to receive(:perform_later).and_return(nil)
      retry_of(job).perform(bill.id)

      # The rule LlmSummaryPositionsErrorNotice depends on: on a completed row,
      # generation_error can only have come from the positions rescue.
      expect(provisioning.reload.generation_error).to be_nil
    end

    it "keeps the summary the first attempt paid for" do
      allow(RecomputeBillInterestingScoreJob).to receive(:perform_later)
        .and_raise(ActiveRecord::StatementInvalid.new("SQLite3::BusyException: database is locked"))

      job = described_class.new(bill.id)
      expect { job.perform(bill.id) }.to raise_error(described_class::TransientBillSummaryError)

      allow(RecomputeBillInterestingScoreJob).to receive(:perform_later).and_return(nil)
      retry_of(job).perform(bill.id)

      expect(provisioning.reload.llm_summary).to include("§1 amended")
    end

    it "logs the skipped repurchase so a resumed run is not indistinguishable from a fresh one" do
      allow(RecomputeBillInterestingScoreJob).to receive(:perform_later)
        .and_raise(ActiveRecord::StatementInvalid.new("SQLite3::BusyException: database is locked"))

      job = described_class.new(bill.id)
      expect { job.perform(bill.id) }.to raise_error(described_class::TransientBillSummaryError)

      allow(RecomputeBillInterestingScoreJob).to receive(:perform_later).and_return(nil)
      retry_of(job).perform(bill.id)

      expect(SwayLogging).to have_received(:warn).with(
        "generate_bill_summary.resumed_without_repurchase", hash_including(bill_id: bill.id)
      )
    end

    # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Preserving the summary when positions fail]]
    describe "a failure between the summary persist and the positions persist" do
      before do
        allow(claude_adapter).to receive(:generate_bill_positions)
          .and_raise(StandardError, "positions transport died")
        # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One lock shared by the job and the persist guard]]
        allow(Sway::Utf8).to receive(:scrub).and_call_original
        allow(Sway::Utf8).to receive(:scrub).with("positions transport died")
          .and_raise(ActiveRecord::StatementInvalid.new("SQLite3::BusyException: database is locked"))
      end

      it "buys the positions half on the retry" do
        job = described_class.new(bill.id)
        expect { job.perform(bill.id) }.to raise_error(described_class::TransientBillSummaryError)
        # The state the marker could not describe: paid for, half persisted.
        expect(provisioning.reload.summary_run_id).to eq(job.job_id)
        expect(provisioning.draft_org_positions).to be_nil

        allow(claude_adapter).to receive(:generate_bill_positions).and_return(positions_payload)
        retry_of(job).perform(bill.id)

        expect(provisioning.reload.draft_org_positions.first["org_name"])
          .to eq("Maryland Tenants Union")
      end

      it "does not buy the summary a second time" do
        job = described_class.new(bill.id)
        expect { job.perform(bill.id) }.to raise_error(described_class::TransientBillSummaryError)

        allow(claude_adapter).to receive(:generate_bill_positions).and_return(positions_payload)
        retry_of(job).perform(bill.id)

        expect(claude_adapter).to have_received(:generate_bill_summary).once
      end

      it "settles the row completed once the debt is paid" do
        job = described_class.new(bill.id)
        expect { job.perform(bill.id) }.to raise_error(described_class::TransientBillSummaryError)

        allow(claude_adapter).to receive(:generate_bill_positions).and_return(positions_payload)
        retry_of(job).perform(bill.id)

        expect(provisioning.reload.generation_status).to eq("completed")
      end

      # @lat: [[explanation/llm-summaries#Batch summarisation#One settle shared by the job and the ingest]]
      it "leaves no stale failure message on the row it just completed" do
        job = described_class.new(bill.id)
        expect { job.perform(bill.id) }.to raise_error(described_class::TransientBillSummaryError)
        expect(provisioning.reload.generation_error).to be_present

        allow(claude_adapter).to receive(:generate_bill_positions).and_return(positions_payload)
        retry_of(job).perform(bill.id)

        expect(provisioning.reload.generation_error).to be_nil
      end

      # @lat: [[explanation/llm-summaries#Batch summarisation#One settle shared by the job and the ingest]]
      def withdraw_testimony_when_the_adapter_is_built
        allow(Llm::Client).to receive(:build).with(provider: "claude") do
          BillLlmProvisioning.where(id: provisioning.id).update_all(
            extracted_testimony: nil, supplemental_testimony: nil
          )
          claude_adapter
        end
      end

      it "leaves no stale failure message on a resume that buys nothing" do
        job = described_class.new(bill.id)
        expect { job.perform(bill.id) }.to raise_error(described_class::TransientBillSummaryError)
        expect(provisioning.reload.generation_error).to be_present

        withdraw_testimony_when_the_adapter_is_built
        retry_of(job).perform(bill.id)

        provisioning.reload
        expect(provisioning.generation_status).to eq("completed")
        expect(provisioning.generation_error).to be_nil
      end

      # The other half of the same resume: it must still buy nothing. Without
      # this, a clear that ran because the run DID make a call would look
      # identical to the one above.
      it "makes no positions call on that resume" do
        job = described_class.new(bill.id)
        expect { job.perform(bill.id) }.to raise_error(described_class::TransientBillSummaryError)

        withdraw_testimony_when_the_adapter_is_built
        retry_of(job).perform(bill.id)

        expect(claude_adapter).to have_received(:generate_bill_positions).once
        expect(claude_adapter).to have_received(:generate_bill_summary).once
      end

      # A row with drafts already on it owes nothing, so the retry must still
      # take the cheap exit rather than buying positions twice.
      it "does not re-buy positions that ARE already on the row" do
        job = described_class.new(bill.id)
        expect { job.perform(bill.id) }.to raise_error(described_class::TransientBillSummaryError)

        provisioning.reload.update_columns(draft_org_positions: [].to_json)
        allow(claude_adapter).to receive(:generate_bill_positions).and_return(positions_payload)
        retry_of(job).perform(bill.id)

        expect(claude_adapter).to have_received(:generate_bill_positions).once
      end
    end

    # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Independent inputs for summaries and positions]]
    describe "and the retry finds no summary and no testimony left" do
      before do
        bill.update!(extracted_text: nil)
        provisioning.update!(
          diff_content: nil,
          llm_summary: nil,
          extracted_testimony: nil,
          supplemental_testimony: nil,
          draft_org_positions: [{"org_name" => "Maryland Tenants Union", "stance" => "support",
                                 "summary" => "Testified in support."}]
        )
      end

      def resumed_job
        job = described_class.new(bill.id)
        provisioning.update!(summary_run_id: job.job_id)
        job
      end

      it "settles failed with the nothing-to-generate reason" do
        resumed_job.perform(bill.id)

        provisioning.reload
        expect(provisioning.generation_status).to eq("failed")
        expect(provisioning.generation_error).to eq(described_class::NOTHING_TO_GENERATE_ERROR)
      end

      it "buys nothing" do
        resumed_job.perform(bill.id)

        expect(claude_adapter).not_to have_received(:generate_bill_summary)
        expect(claude_adapter).not_to have_received(:generate_bill_positions)
      end

      it "leaves the drafts this enqueue already paid for on the row" do
        resumed_job.perform(bill.id)

        expect(provisioning.reload.draft_org_positions.first["org_name"])
          .to eq("Maryland Tenants Union")
      end
    end

    # The check must key on THIS enqueue, not on "a summary exists". A
    # regenerate carries a different job_id and must buy again — that is what
    # the operator asked for.
    it "does re-buy for a DIFFERENT enqueue (regenerate must not be short-circuited)" do
      described_class.new(bill.id).perform(bill.id)
      described_class.new(bill.id).perform(bill.id)

      expect(claude_adapter).to have_received(:generate_bill_summary).twice
    end
  end

  # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Independent inputs for summaries and positions]]
  describe "#perform — summary call gated on source presence (B4-WR-04)" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }
    let(:positions_payload) do
      {
        "draft_org_positions" => [
          {"org_name" => "Maryland Tenants Union", "stance" => "support", "summary" => "Testified in support."}
        ]
      }
    end

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      allow(claude_adapter).to receive(:generate_bill_positions).and_return(positions_payload)
      allow(SwayLogging).to receive(:warn)
      # A testimony-only bill: the hearing attachments came out cleanly, the bill
      # PDF did not. No diff markdown, no diff_content, no extracted_text.
      bill.update!(extracted_text: nil)
      provisioning.update!(
        diff_content: nil,
        extracted_testimony: "Testimony of the Maryland Tenants Union in support."
      )
    end

    it "does not buy a summary when there is no source text to summarize" do
      expect(claude_adapter).not_to receive(:generate_bill_summary)
      described_class.perform_now(bill.id)
    end

    it "returns SETTLED rather than STOOD_DOWN, since the positions call was bought" do
      expect(described_class.perform_now(bill.id)).to eq(described_class::SETTLED)
    end

    it "still buys the positions the testimony supports" do
      described_class.perform_now(bill.id)
      expect(claude_adapter).to have_received(:generate_bill_positions).once
    end

    it "persists those positions" do
      described_class.perform_now(bill.id)
      expect(provisioning.reload.draft_org_positions&.length).to eq(1)
    end

    # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Independent inputs for summaries and positions]]
    it "settles the row terminally rather than stranding it in generating" do
      described_class.perform_now(bill.id)
      expect(provisioning.reload.generation_status).to eq("failed")
    end

    it "does not claim a summary it never bought" do
      described_class.perform_now(bill.id)

      expect(provisioning.reload.llm_summary).to be_nil
      expect(provisioning.llm_generated_at).to be_nil
    end

    # The stored reason is the whole operator-visible output of this path, so
    # it says both halves: no summary, and the positions below are real.
    it "records why, and that the positions are unaffected" do
      described_class.perform_now(bill.id)

      expect(provisioning.reload.generation_error).to eq(described_class::NO_SOURCE_TEXT_ERROR)
    end

    it "logs the positions-only settle" do
      described_class.perform_now(bill.id)

      expect(SwayLogging).to have_received(:warn).with(
        "generate_bill_summary.positions_only_no_summary", hash_including(bill_id: bill.id)
      )
    end

    it "writes an activity log entry naming the upstream stages, not Regenerate" do
      described_class.perform_now(bill.id)

      entry = PipelineActivityLogEntry.find_by(event_type: "summary_skipped_no_source_text", subject: bill) #: PipelineActivityLogEntry
      expect(entry).not_to be_nil
      expect(entry.severity).to eq("info")
      expect(entry.message).to include(bill.external_id)
      expect(entry.message).to include("extract-text")
      expect(entry.message).to include("fetch-hearings")
      expect(entry.message).not_to include("Regenerate")
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
    it "finishes an operator's deferred hand-off instead of failing the row under their summary" do
      pasted_body = "A summary an operator wrote by hand while the positions call was in flight."
      allow(SwayLogging).to receive(:warn) do |key, *|
        if key == "generate_bill_summary.positions_only_no_summary"
          BillLlmProvisioning.where(id: provisioning.id).update_all(
            summary_run_id: SummaryRunMarker.operator_paste,
            llm_summary: pasted_body,
            llm_provider: "operator_paste",
            llm_generated_at: Time.current
          )
        end
      end

      described_class.perform_now(bill.id)

      provisioning.reload
      expect(provisioning.generation_status).to eq("completed")
      expect(provisioning.llm_summary).to eq(pasted_body)
      expect(provisioning.generation_error).to be_nil
    end

    # @lat: [[explanation/llm-summaries#Batch summarisation#Why the evidence digest is stamped at submit time]]
    it "records that this enqueue has spent money when the positions answer is discarded" do
      job = described_class.new(bill.id)
      allow(claude_adapter).to receive(:generate_bill_positions) do
        BillLlmProvisioning.where(id: provisioning.id).update_all(
          extracted_testimony: nil, supplemental_testimony: nil
        )
        positions_payload
      end

      job.perform(bill.id)

      expect(provisioning.reload.summary_run_id).to eq(job.job_id)
    end

    # @lat: [[explanation/llm-summaries#Batch summarisation#Why the evidence digest is stamped at submit time]]
    context "when an operator's paste lands between the persist's lock and the discard's" do
      let(:pasted_body) { "A summary an operator wrote by hand while the run was in flight." }

      before do
        allow(claude_adapter).to receive(:generate_bill_positions) do
          BillLlmProvisioning.where(id: provisioning.id).update_all(
            extracted_testimony: nil, supplemental_testimony: nil
          )
          positions_payload
        end

        allow(SwayLogging).to receive(:warn).and_wrap_original do |original, key, **rest|
          if key == "generate_bill_summary.positions_evidence_withdrawn"
            BillLlmProvisioning.where(id: provisioning.id).update_all(
              summary_run_id: SummaryRunMarker.operator_paste,
              llm_summary: pasted_body,
              llm_generated_at: Time.current
            )
          end
          original.call(key, **rest)
        end
      end

      it "writes no discard reason onto the row the paste now owns" do
        described_class.perform_now(bill.id)

        expect(provisioning.reload.generation_error).to be_nil
      end

      it "leaves the paste marker and the pasted body alone" do
        described_class.perform_now(bill.id)

        expect(provisioning.reload.llm_summary).to eq(pasted_body)
        expect(SummaryRunMarker.operator_paste?(provisioning.summary_run_id)).to be(true)
      end
    end

    # `failed -> pending` exists on the `enqueue` event, so the operator can
    # re-run once extract-text produces something. Without it the row would be
    # a dead end.
    it "leaves the row able to run again" do
      described_class.perform_now(bill.id)

      expect(provisioning.reload.can_enqueue?).to be(true)
    end

    # A REGENERATION that bought no new summary is a different case: the
    # previous summary is still on the row and is still good, just older.
    # That row is genuinely complete and must not be flipped to failed.
    context "when the row already holds a summary from an earlier run" do
      before do
        provisioning.update!(
          llm_summary: "An earlier, still-valid summary.",
          llm_generated_at: 2.days.ago
        )
      end

      it "keeps the row completed and keeps the earlier summary" do
        described_class.perform_now(bill.id)

        expect(provisioning.reload.generation_status).to eq("completed")
        expect(provisioning.llm_summary).to eq("An earlier, still-valid summary.")
      end
    end

    it "logs why the summary call was skipped" do
      described_class.perform_now(bill.id)
      expect(SwayLogging).to have_received(:warn).with(
        "generate_bill_summary.no_source_text", hash_including(bill_id: bill.id)
      )
    end

    it "does not fabricate a citation verdict for a summary it never bought" do
      described_class.perform_now(bill.id)
      expect(provisioning.reload.citations_valid).to be_nil
    end

    it "marks the enqueue as having spent money so a retry does not re-buy the positions" do
      job = described_class.new(bill.id)
      job.perform(bill.id)

      retried = described_class.new(bill.id)
      retried.job_id = job.job_id
      retried.perform(bill.id)

      expect(claude_adapter).to have_received(:generate_bill_positions).once
    end

    # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One lock shared by the job and the persist guard]]
    it "keeps the retry on the failed settle instead of flipping the row to completed" do
      job = described_class.new(bill.id)
      job.perform(bill.id)

      retried = described_class.new(bill.id)
      retried.job_id = job.job_id
      retried.perform(bill.id)

      provisioning.reload
      expect(provisioning.generation_status).to eq("failed")
      expect(provisioning.generation_error).to eq(described_class::NO_SOURCE_TEXT_ERROR)
    end

    # And a THIRD arrival of the same enqueue still buys nothing — the failed
    # settle keeps the marker, so the routing does not reopen the re-buy the
    # marker exists to prevent.
    it "still refuses to re-buy on the retry after the retry" do
      job = described_class.new(bill.id)
      job.perform(bill.id)

      2.times do
        retried = described_class.new(bill.id)
        retried.job_id = job.job_id
        retried.perform(bill.id)
      end

      expect(claude_adapter).to have_received(:generate_bill_positions).once
      expect(provisioning.reload.generation_status).to eq("failed")
    end

    # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Bounded errors preserve the operator instruction]]
    context "when the positions call fails and there is no bill text either" do
      before do
        allow(claude_adapter).to receive(:generate_bill_positions)
          .and_raise(Llm::TransportError.new("rate limited by upstream"))
      end

      it "names the real failure instead of claiming positions exist" do
        described_class.perform_now(bill.id)

        expect(provisioning.reload.generation_error).to eq(
          format(described_class::NO_SOURCE_TEXT_POSITIONS_FAILED_ERROR, reason: "rate limited by upstream")
        )
      end

      it "does not say the positions below are unaffected" do
        described_class.perform_now(bill.id)

        expect(provisioning.reload.generation_error).not_to include("are unaffected")
      end

      it "still settles the row terminally so the operator can retry" do
        described_class.perform_now(bill.id)

        provisioning.reload
        expect(provisioning.generation_status).to eq("failed")
        expect(provisioning.can_enqueue?).to be(true)
      end

      # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Bounded errors preserve the operator instruction]]
      it "keeps the retry instruction and the head of the reason for a huge adapter message" do
        allow(claude_adapter).to receive(:generate_bill_positions)
          .and_raise(Llm::TransportError.new("upstream refused: #{"y" * 5_000}"))

        described_class.perform_now(bill.id)

        stored = provisioning.reload.generation_error.to_s
        expect(stored).to include("The positions call also failed: upstream refused: yyyyy")
        expect(stored).to include("Retry to make the positions call again")
        expect(stored).to include("or until you paste a summary.")
        expect(stored.length).to be <= described_class::MAX_GENERATION_ERROR_LENGTH
      end

      # And the cut is visible, so an operator reading a reason that stops
      # abruptly knows the rest is in the log rather than that the adapter
      # sent a broken message.
      it "marks the reason it had to cut" do
        allow(claude_adapter).to receive(:generate_bill_positions)
          .and_raise(Llm::TransportError.new("upstream refused: #{"y" * 5_000}"))

        described_class.perform_now(bill.id)

        expect(provisioning.reload.generation_error.to_s)
          .to include("…. Retry to make the positions call again")
      end
    end

    # The third state of the same settle: the positions call succeeded and
    # named no organization, so there is nothing below the message either. The
    # old wording pointed the operator at positions that are not on screen.
    context "when the positions call succeeds but names no organization" do
      before do
        allow(claude_adapter).to receive(:generate_bill_positions)
          .and_return({"draft_org_positions" => []})
      end

      it "says there are no positions rather than pointing at positions below" do
        described_class.perform_now(bill.id)

        expect(provisioning.reload.generation_error)
          .to eq(described_class::NO_SOURCE_TEXT_NO_POSITIONS_ERROR)
      end
    end
  end

  # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Independent inputs for summaries and positions]]
  describe "#perform — neither paid call has its inputs (B1-WR-03)" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      allow(claude_adapter).to receive(:generate_bill_positions).and_return("draft_org_positions" => [])
      allow(SwayLogging).to receive(:warn)
      allow(RecomputeBillInterestingScoreJob).to receive(:perform_later)
      # A Legistar matter with no PDF (the documented no_pdf_uploaded skip) and
      # no hearing attachments: nothing to summarize, and nothing to draw
      # positions from.
      bill.update!(extracted_text: nil)
      provisioning.update!(extracted_testimony: nil, supplemental_testimony: nil)
    end

    shared_examples "refuses to claim a summary it never bought" do
      it "buys no summary" do
        described_class.perform_now(bill.id)
        expect(claude_adapter).not_to have_received(:generate_bill_summary)
      end

      it "buys no positions" do
        described_class.perform_now(bill.id)
        expect(claude_adapter).not_to have_received(:generate_bill_positions)
      end

      it "does not settle the row completed" do
        described_class.perform_now(bill.id)
        expect(provisioning.reload.generation_status).not_to eq("completed")
      end

      it "settles the row terminally so it is not stranded in generating" do
        described_class.perform_now(bill.id)
        expect(provisioning.reload.generation_status).to eq("failed")
      end

      it "records why, in the column the failed branch renders" do
        described_class.perform_now(bill.id)
        expect(provisioning.reload.generation_error).to match(/nothing to summarize/i)
      end

      it "leaves llm_summary nil rather than an empty claimed summary" do
        described_class.perform_now(bill.id)
        expect(provisioning.reload.llm_summary).to be_nil
      end

      it "leaves llm_generated_at nil" do
        described_class.perform_now(bill.id)
        expect(provisioning.reload.llm_generated_at).to be_nil
      end

      it "does not fabricate a citation verdict" do
        described_class.perform_now(bill.id)
        expect(provisioning.reload.citations_valid).to be_nil
      end

      it "leaves the row re-armable so the operator can retry after uploading a PDF" do
        described_class.perform_now(bill.id)
        expect(provisioning.reload.can_enqueue?).to be(true)
      end

      it "does not recompute an interesting score for a summary it never produced" do
        described_class.perform_now(bill.id)
        expect(RecomputeBillInterestingScoreJob).not_to have_received(:perform_later)
      end

      it "logs the reason" do
        described_class.perform_now(bill.id)
        expect(SwayLogging).to have_received(:warn).with(
          "generate_bill_summary.nothing_to_generate", hash_including(bill_id: bill.id)
        )
      end

      it "writes an activity log entry naming the upstream stages, not Regenerate" do
        described_class.perform_now(bill.id)

        entry = PipelineActivityLogEntry.find_by(event_type: "summary_skipped_no_source_text", subject: bill) #: PipelineActivityLogEntry
        expect(entry).not_to be_nil
        expect(entry.severity).to eq("info")
        expect(entry.message).to include(bill.external_id)
        expect(entry.message).to include("extract-text")
        expect(entry.message).to include("fetch-hearings")
        expect(entry.message).not_to include("Regenerate")
      end

      it "does not raise, so an inline pipeline perform_now keeps going" do
        expect { described_class.perform_now(bill.id) }.not_to raise_error
      end

      it "returns STOOD_DOWN rather than SETTLED, since neither paid call was made" do
        expect(described_class.perform_now(bill.id)).to eq(described_class::STOOD_DOWN)
      end
    end

    context "when the bill has no generate-diffs artifact at all" do
      before { provisioning.update!(diff_content: nil, diff_generated_at: nil) }

      include_examples "refuses to claim a summary it never bought"
    end

    # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Independent inputs for summaries and positions]]
    context "when the row already holds a summary from an earlier run" do
      before do
        provisioning.update!(
          diff_content: nil,
          diff_generated_at: nil,
          llm_summary: "An earlier, still-valid summary.",
          llm_generated_at: 2.days.ago
        )
      end

      it "keeps the row completed rather than failing over a summary that exists" do
        described_class.perform_now(bill.id)

        expect(provisioning.reload.generation_status).to eq("completed")
      end

      it "keeps the earlier summary" do
        described_class.perform_now(bill.id)

        expect(provisioning.reload.llm_summary).to eq("An earlier, still-valid summary.")
      end

      it "does not tell the operator there is nothing to summarize" do
        described_class.perform_now(bill.id)

        expect(provisioning.reload.generation_error).to be_nil
      end

      # @lat: [[explanation/llm-summaries#Batch summarisation#One settle shared by the job and the ingest]]
      it "enqueues no score recompute for a run that bought nothing" do
        described_class.perform_now(bill.id)

        expect(RecomputeBillInterestingScoreJob).not_to have_received(:perform_later)
      end
    end

    context "when the bill's only artifact is the non-amending empty sentinel" do
      before do
        provisioning.update!(
          diff_content: JSON.generate(
            "file_id" => bill.external_id,
            "title" => bill.title,
            "target" => "baltimore_city_code",
            "generated_at" => "2026-07-01T00:00:00.000000+00:00",
            "summary" => nil,
            "sections" => [],
            "stats" => {
              "sections_modified" => 0,
              "sections_referenced_only" => 0,
              "sections_not_found" => 0,
              "total_operations" => 0
            }
          )
        )
      end

      include_examples "refuses to claim a summary it never bought"
    end
  end

  # What reclassifying this error actually buys. A truncated response has to
  # reach discard_on, not retry_on — otherwise a long bill pays for the full
  # input plus 4096 output tokens three times over, for a failure whose own
  # message tells the operator how to fix it.
  describe "#perform — a max_tokens truncation is discarded, not retried (B4-WR-05)" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_raise(
        Llm::SchemaError.new("claude schema: response truncated (stop_reason=max_tokens) — extend MAX_TOKENS or trim source")
      )
    end

    it "wraps it as DeterministicBillSummaryError so discard_on applies" do
      expect {
        described_class.new.perform(bill.id)
      }.to raise_error(described_class::DeterministicBillSummaryError, /response truncated/)
    end

    it "surfaces the operator remedy in generation_error" do
      expect {
        described_class.new.perform(bill.id)
      }.to raise_error(described_class::DeterministicBillSummaryError)

      expect(provisioning.reload.generation_error.to_s).to match(/extend MAX_TOKENS or trim/)
    end
  end

  describe "auto-provisioning (preserved from pre-refactor)" do
    # extracted_text, not diff_content: this group is entirely about there being
    # no provisioning row yet, so the source has to sit on the bill — the shape a
    # non-amending resolution or appointment has.
    let(:bill_without_provisioning) do
      create(:bill, external_id: "AUTO-PROV-1", extracted_text: "Full text of a resolution with no diff.")
    end
    let(:llamacpp_adapter) { instance_double(Llm::LlamacppAdapter, provider_label: "llamacpp") }

    before do
      bill_without_provisioning.bill_llm_provisioning&.destroy
      bill_without_provisioning.reload
      stub_app_config(:llm, llm_provider: "llamacpp", llamacpp_model: "local")
      allow(Llm::Client).to receive(:build).with(provider: "llamacpp").and_return(llamacpp_adapter)
      allow(llamacpp_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
    end

    it "creates a BillLlmProvisioning row in :pending then progresses to :completed" do
      expect(bill_without_provisioning.bill_llm_provisioning).to be_nil
      described_class.perform_now(bill_without_provisioning.id)
      created = bill_without_provisioning.reload.bill_llm_provisioning
      expect(created).to be_present
      expect(created.generation_status).to eq("completed")
      expect(created.llm_summary).to include("§1 amended")
    end
  end

  # @lat: [[explanation/boot-time-backfills#Why a stamped bill costs nothing on the next boot#The category backfill buys only a missing active verdict]]
  describe "#perform — WR-03 empty active taxonomy guard" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      # Deactivate all categories so active_categories is empty inside perform.
      Category.update_all(active: false)
      allow(SwayLogging).to receive(:warn)
    end

    it "completes successfully (provisioning = completed) when no categories are active" do
      described_class.perform_now(bill.id)
      expect(provisioning.reload.generation_status).to eq("completed")
    end

    it "assigns zero categories to the bill when no categories are active" do
      described_class.perform_now(bill.id)
      expect(bill.reload.categories.count).to eq(0)
    end

    it "logs a warning with the no_active_categories key" do
      described_class.perform_now(bill.id)
      expect(SwayLogging).to have_received(:warn).with(
        "generate_bill_summary.no_active_categories", hash_including(bill_id: bill.id)
      )
    end
  end

  # Category-assignment tests. BillCategoryAssigner runs after
  # provisioning.update! and before mark_completed!, so a failure there comes
  # out as a DeterministicBillSummaryError.
  describe "#perform — category assignment (R4)" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
    end

    it "assigns 1–3 active categories to the bill on the happy path" do
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      described_class.perform_now(bill.id)
      expect(bill.reload.categories.count).to be_between(1, 3)
    end

    it "assigns only categories from the active set" do
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      described_class.perform_now(bill.id)
      expect(bill.reload.categories).to all(satisfy { |c| c.active? })
    end

    it "does NOT persist a category name outside the active set" do
      inactive_category = create(:category, name: "Deprecated", slug: "deprecated", active: false)
      payload_with_inactive = valid_payload.merge("categories" => ["Deprecated", "Health"])
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(payload_with_inactive)
      described_class.perform_now(bill.id)
      expect(bill.reload.categories).not_to include(inactive_category)
    end

    it "ends with completed status when categories resolve successfully" do
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      described_class.perform_now(bill.id)
      expect(provisioning.reload.generation_status).to eq("completed")
    end

    # @lat: [[explanation/boot-time-backfills#Why a stamped bill costs nothing on the next boot#The category backfill buys only a missing active verdict]]
    context "when parsed categories is nil (schema omitted the key) — WR-02" do
      let(:payload_no_categories) { valid_payload.except("categories") }

      before do
        allow(claude_adapter).to receive(:generate_bill_summary).and_return(payload_no_categories)
        allow(SwayLogging).to receive(:warn)
      end

      it "completes successfully (provisioning = completed) — no DeterministicBillSummaryError" do
        expect { described_class.new.perform(bill.id) }.not_to raise_error
        expect(provisioning.reload.generation_status).to eq("completed")
      end

      it "assigns zero categories to the bill (uncategorized — backfill will handle later)" do
        described_class.new.perform(bill.id)
        expect(bill.reload.categories.count).to eq(0)
      end

      it "logs a warning with the no_categories_in_response key" do
        described_class.new.perform(bill.id)
        expect(SwayLogging).to have_received(:warn).with(
          "generate_bill_summary.no_categories_in_response", hash_including(bill_id: bill.id)
        )
      end
    end

    context "when parsed categories is empty array — WR-02" do
      let(:payload_empty_categories) { valid_payload.merge("categories" => []) }

      before do
        allow(claude_adapter).to receive(:generate_bill_summary).and_return(payload_empty_categories)
        allow(SwayLogging).to receive(:warn)
      end

      it "completes successfully (provisioning = completed) — no DeterministicBillSummaryError" do
        expect { described_class.new.perform(bill.id) }.not_to raise_error
        expect(provisioning.reload.generation_status).to eq("completed")
      end

      it "assigns zero categories to the bill" do
        described_class.new.perform(bill.id)
        expect(bill.reload.categories.count).to eq(0)
      end
    end

    # @lat: [[explanation/boot-time-backfills#Why a stamped bill costs nothing on the next boot#The category backfill buys only a missing active verdict]]
    context "when parsed categories is a non-empty array with no active-set match (genuine bad data)" do
      let(:payload_unmatched) { valid_payload.merge("categories" => ["UnknownCategory"]) }

      before do
        allow(claude_adapter).to receive(:generate_bill_summary).and_return(payload_unmatched)
        allow(SwayLogging).to receive(:warn)
      end

      it "does NOT raise — the summary is already bought and persisted" do
        expect { described_class.new.perform(bill.id) }.not_to raise_error
      end

      it "completes uncategorized rather than discarding the paid-for summary" do
        described_class.new.perform(bill.id)
        expect(provisioning.reload.generation_status).to eq("completed")
      end

      it "keeps llm_summary on the row so the operator can see what they paid for" do
        described_class.new.perform(bill.id)
        expect(provisioning.reload.llm_summary).to include("§1 amended")
      end

      it "assigns zero categories (the boot backfill can categorise it later)" do
        described_class.new.perform(bill.id)
        expect(bill.reload.categories.count).to eq(0)
      end

      it "logs the mismatch so an unmatched taxonomy is not invisible" do
        described_class.new.perform(bill.id)
        expect(SwayLogging).to have_received(:warn).with(
          "generate_bill_summary.categories_not_matched", hash_including(bill_id: bill.id)
        )
      end
    end
  end

  # The positions call runs only when provisioning.testimony_present? is true —
  # the same check the Bill Creator UI's has_testimony reads — so what the UI
  # shows and what generation does can never disagree.
  describe "#perform — positions call gated on testimony_present?" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Preserving the summary when positions fail]]
    let(:curated_positions) do
      [{"org_name" => "Maryland Tenants Union", "stance" => "support", "summary" => "Operator-edited rationale."}]
    end

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
    end

    context "no testimony" do
      it "does not call generate_bill_positions" do
        expect(claude_adapter).not_to receive(:generate_bill_positions)
        described_class.perform_now(bill.id)
      end

      # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Preserving the summary when positions fail]]
      it "preserves operator-curated draft_org_positions instead of wiping them" do
        provisioning.update!(draft_org_positions: curated_positions)

        described_class.perform_now(bill.id)

        expect(provisioning.reload.draft_org_positions).to eq(curated_positions)
      end

      it "does not write the column at all when there is nothing to preserve" do
        described_class.perform_now(bill.id)

        # nil, not [] — the browser type is `IOrgPosition[] | null`, and every
        # place that reads it falls back with `|| []`, so leaving the column
        # unwritten is safe.
        expect(provisioning.reload.draft_org_positions).to be_nil
      end
    end

    context "with testimony" do
      let(:positions_payload) do
        {
          "draft_org_positions" => [
            {"org_name" => "Maryland Tenants Union", "stance" => "support", "summary" => "Closes a documented enforcement gap."}
          ]
        }
      end

      before do
        provisioning.update!(extracted_testimony: "Testimony from the hearing record.")
        allow(claude_adapter).to receive(:generate_bill_positions).and_return(positions_payload)
      end

      it "calls generate_bill_positions exactly once" do
        expect(claude_adapter).to receive(:generate_bill_positions).once.and_return(positions_payload)
        described_class.perform_now(bill.id)
      end

      it "persists the parsed positions" do
        described_class.perform_now(bill.id)
        expect(provisioning.reload.draft_org_positions).to eq(positions_payload["draft_org_positions"])
      end

      it "replaces previously curated positions when the call succeeds" do
        provisioning.update!(draft_org_positions: curated_positions)

        described_class.perform_now(bill.id)

        expect(provisioning.reload.draft_org_positions).to eq(positions_payload["draft_org_positions"])
      end

      # @lat: [[explanation/hearing-testimony-census#What a hearings fetch can conclude#Retracting evidence retires the conclusions drawn from it]]
      it "clears the evidence-retracted mark by replacing the array" do
        provisioning.update!(draft_org_positions:
          BillLlmProvisioning.drafts_with_evidence_retracted(curated_positions))

        described_class.perform_now(bill.id)

        drafts = provisioning.reload.draft_org_positions
        expect(drafts).to eq(positions_payload["draft_org_positions"])
        expect(drafts.none? { |d| BillLlmProvisioning.draft_evidence_retracted?(d) }).to be(true)
      end

      # The distinction the fix turns on. A call that succeeds and finds no
      # positions is a real answer, so it must still clear the column; only a
      # call that fails leaves the column alone.
      it "writes an empty array when the call succeeds with zero positions" do
        provisioning.update!(draft_org_positions: curated_positions)
        allow(claude_adapter).to receive(:generate_bill_positions)
          .and_return({"draft_org_positions" => []})

        described_class.perform_now(bill.id)

        expect(provisioning.reload.draft_org_positions).to eq([])
      end

      # @lat: [[explanation/llm-summaries#What a third provider reached through OpenRouter exposes#Resolving an inference route from the chosen model]]
      it "sends the positions call the same model as the summary call" do
        models = {} #: Hash[Symbol, String]
        allow(claude_adapter).to receive(:generate_bill_summary) do |**kwargs|
          models[:summary] = kwargs[:model]
          valid_payload
        end
        allow(claude_adapter).to receive(:generate_bill_positions) do |**kwargs|
          models[:positions] = kwargs[:model]
          positions_payload
        end

        described_class.perform_now(bill.id)

        expect(models[:positions]).to eq(models[:summary])
        expect(models[:positions]).to eq(AdminSetting.singleton.summarization_model)
      end

      # Kept, and renamed so it no longer stands in for the contract above. One
      # lookup is worth pinning on its own: AdminSetting.singleton reads the
      # database, and the model must not be allowed to change under a run
      # halfway through.
      it "resolves the model from AdminSetting exactly once per run" do
        expect(AdminSetting).to receive(:singleton).once.and_call_original
        described_class.perform_now(bill.id)
      end
    end

    # A transport failure on the positions call is swallowed at that call site
    # rather than re-raised. Re-raising would send the job back through retry_on,
    # which would bill the summary call up to 3 more times and strand a good
    # summary on a failed row.
    context "positions transport failure" do
      before do
        provisioning.update!(extracted_testimony: "Testimony from the hearing record.")
        allow(claude_adapter).to receive(:generate_bill_positions)
          .and_raise(Llm::TransportError.new("claude transport: 429 rate_limit"))
        allow(SwayLogging).to receive(:warn)
      end

      it "does not raise" do
        expect { described_class.new.perform(bill.id) }.not_to raise_error
      end

      it "completes the row (not failed)" do
        described_class.new.perform(bill.id)
        expect(provisioning.reload.generation_status).to eq("completed")
      end

      # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Preserving the summary when positions fail]]
      it "preserves operator-curated positions while preserving the summary text" do
        provisioning.update!(draft_org_positions: curated_positions)

        described_class.new.perform(bill.id)

        provisioning.reload
        expect(provisioning.draft_org_positions).to eq(curated_positions)
        expect(provisioning.llm_summary).to eq(valid_payload["summary_markdown"])
      end

      it "calls the summary adapter method exactly once — no re-billing (anti-recharge)" do
        expect(claude_adapter).to receive(:generate_bill_summary).once.and_return(valid_payload)
        described_class.new.perform(bill.id)
      end

      # This log key used to be positions_transport_failure. The rescue now
      # covers schema failures as well, so error_class is what tells the two
      # apart in the log.
      it "logs a structured warning naming the bill" do
        described_class.new.perform(bill.id)
        expect(SwayLogging).to have_received(:warn).with(
          "generate_bill_summary.positions_failure",
          hash_including(bill_id: bill.id, error_class: "Llm::TransportError")
        )
      end
    end

    # @lat: [[explanation/llm-summaries#Batch summarisation#Why the evidence digest is stamped at submit time]]
    context "testimony withdrawn while the run holds a stale copy" do
      let(:marked_draft) do
        {
          "org_name" => "Marked Org",
          "stance" => "support",
          "summary" => "Testified in support.",
          "evidence_retracted_at" => "2026-07-01T00:00:00Z"
        }
      end
      let(:fresh_positions) do
        {
          "draft_org_positions" => [
            {"org_name" => "Newly Drafted Org", "stance" => "support", "summary" => "Testified in support."}
          ]
        }
      end

      before do
        allow(SwayLogging).to receive(:warn)
        provisioning.update!(
          extracted_testimony: "Testimony of Marked Org in support.",
          draft_org_positions: [marked_draft]
        )
      end

      # The concurrent fetch-hearings :retract, driven as a separate UPDATE
      # while the job's copy is stale — the same technique the other race
      # examples in this file use.
      def withdraw_testimony
        BillLlmProvisioning.where(id: provisioning.id).update_all(
          extracted_testimony: nil,
          supplemental_testimony: nil
        )
      end

      context "withdrawn during the positions call" do
        before do
          allow(claude_adapter).to receive(:generate_bill_positions) do
            withdraw_testimony
            fresh_positions
          end
        end

        it "keeps the retraction mark the other run wrote" do
          described_class.perform_now(bill.id)

          drafts = provisioning.reload.draft_org_positions
          expect(drafts.length).to eq(1)
          expect(drafts.first["org_name"]).to eq("Marked Org")
          expect(BillLlmProvisioning.draft_evidence_retracted?(drafts.first)).to be(true)
        end

        it "does not save positions drawn from evidence that is gone" do
          described_class.perform_now(bill.id)

          names = provisioning.reload.draft_org_positions.pluck("org_name")
          expect(names).not_to include("Newly Drafted Org")
        end

        it "says on the row why the new positions are not there" do
          described_class.perform_now(bill.id)

          expect(provisioning.reload.generation_error.to_s).to match(/testimony/i)
        end

        it "logs the discard rather than dropping it silently" do
          described_class.perform_now(bill.id)

          expect(SwayLogging).to have_received(:warn).with(
            "generate_bill_summary.positions_evidence_withdrawn",
            hash_including(bill_id: bill.id)
          )
        end
      end

      # @lat: [[explanation/llm-summaries#Batch summarisation#Why the evidence digest is stamped at submit time]]
      context "withdrawn one attachment at a time, so the column is shorter but not blank" do
        before do
          allow(claude_adapter).to receive(:generate_bill_positions) do
            BillLlmProvisioning.where(id: provisioning.id).update_all(
              extracted_testimony: "Testimony of Other Org in support.",
              testimony_fetched_at: Time.current
            )
            fresh_positions
          end
        end

        it "keeps the retraction mark the other run wrote" do
          described_class.perform_now(bill.id)

          drafts = provisioning.reload.draft_org_positions
          expect(drafts.length).to eq(1)
          expect(drafts.first["org_name"]).to eq("Marked Org")
          expect(BillLlmProvisioning.draft_evidence_retracted?(drafts.first)).to be(true)
        end

        it "does not save positions drawn from evidence that is no longer all there" do
          described_class.perform_now(bill.id)

          names = provisioning.reload.draft_org_positions.pluck("org_name")
          expect(names).not_to include("Newly Drafted Org")
        end
      end

      # The other column the same rule has to cover. An operator clearing their
      # paste stamps every draft too (SupplementalTestimonyWrite), and it moves
      # neither extracted_testimony nor testimony_fetched_at — so a check
      # written against either of those alone would miss it.
      context "withdrawn through the operator's own paste rather than the hearing attachments" do
        before do
          provisioning.update!(supplemental_testimony: "An operator pasted this in.")
          allow(claude_adapter).to receive(:generate_bill_positions) do
            BillLlmProvisioning.where(id: provisioning.id).update_all(supplemental_testimony: nil)
            fresh_positions
          end
        end

        it "keeps the retraction mark rather than replacing the array" do
          described_class.perform_now(bill.id)

          drafts = provisioning.reload.draft_org_positions
          expect(drafts.first["org_name"]).to eq("Marked Org")
          expect(BillLlmProvisioning.draft_evidence_retracted?(drafts.first)).to be(true)
        end
      end

      # The break has to bite in the other direction too: a call whose evidence
      # did not move must still land, and must still lift the mark. Without
      # this, a persist that had simply stopped writing would pass every
      # example above.
      it "still replaces the drafts when the evidence it read is unchanged" do
        allow(claude_adapter).to receive(:generate_bill_positions).and_return(fresh_positions)

        described_class.perform_now(bill.id)

        drafts = provisioning.reload.draft_org_positions
        expect(drafts.pluck("org_name")).to eq(["Newly Drafted Org"])
        expect(BillLlmProvisioning.draft_evidence_retracted?(drafts.first)).to be(false)
      end

      # The cheaper half: the gate itself. When the withdrawal lands before the
      # positions call, the run must not buy a call whose prompt carries
      # testimony the row no longer holds.
      it "makes no positions call when the testimony went away before it" do
        allow(claude_adapter).to receive(:generate_bill_summary) do
          withdraw_testimony
          valid_payload
        end
        expect(claude_adapter).not_to receive(:generate_bill_positions)

        described_class.perform_now(bill.id)
      end
    end

    # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Preserving the summary when positions fail]]
    context "positions schema failure" do
      before do
        provisioning.update!(extracted_testimony: "Testimony from the hearing record.")
        allow(claude_adapter).to receive(:generate_bill_positions)
          .and_raise(Llm::SchemaError.new("schema validation failed from claude: unknown key 'rationale'"))
        allow(SwayLogging).to receive(:warn)
      end

      it "does not raise" do
        expect { described_class.new.perform(bill.id) }.not_to raise_error
      end

      it "completes the row so the good summary is visible to the operator" do
        described_class.new.perform(bill.id)
        provisioning.reload
        expect(provisioning.generation_status).to eq("completed")
        expect(provisioning.llm_summary).to eq(valid_payload["summary_markdown"])
        expect(provisioning.llm_full_breakdown).to eq(valid_payload["full_breakdown_markdown"])
      end

      it "calls the summary adapter method exactly once — no re-billing (anti-recharge)" do
        expect(claude_adapter).to receive(:generate_bill_summary).once.and_return(valid_payload)
        described_class.new.perform(bill.id)
      end

      it "records why positions are missing without clobbering the summary" do
        described_class.new.perform(bill.id)
        expect(provisioning.reload.generation_error).to match(/positions call failed/i)
      end

      it "preserves operator-curated positions (B-CR-01)" do
        provisioning.update!(draft_org_positions: curated_positions)

        described_class.new.perform(bill.id)

        expect(provisioning.reload.draft_org_positions).to eq(curated_positions)
      end

      it "logs a structured warning naming the bill" do
        described_class.new.perform(bill.id)
        expect(SwayLogging).to have_received(:warn).with(
          "generate_bill_summary.positions_failure", hash_including(bill_id: bill.id)
        )
      end
    end

    # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Preserving the summary when positions fail]]
    context "positions prompt construction raises a non-Llm error" do
      before do
        provisioning.update!(extracted_testimony: "Testimony from the hearing record.")
        allow(BillPositionsPromptBuilder).to receive(:new)
          .and_raise(ArgumentError.new("invalid byte sequence in UTF-8"))
        allow(SwayLogging).to receive(:warn)
      end

      it "does not raise" do
        expect { described_class.new.perform(bill.id) }.not_to raise_error
      end

      it "completes the row so the paid-for summary stays visible" do
        described_class.new.perform(bill.id)

        provisioning.reload
        expect(provisioning.generation_status).to eq("completed")
        expect(provisioning.llm_summary).to eq(valid_payload["summary_markdown"])
      end

      it "calls the summary adapter method exactly once — no re-billing" do
        expect(claude_adapter).to receive(:generate_bill_summary).once.and_return(valid_payload)

        described_class.new.perform(bill.id)
      end

      it "tells the operator why positions are absent" do
        described_class.new.perform(bill.id)

        expect(provisioning.reload.generation_error).to match(/positions call failed/i)
      end

      it "logs the failure under the positions key with its real error class" do
        described_class.new.perform(bill.id)

        expect(SwayLogging).to have_received(:warn).with(
          "generate_bill_summary.positions_failure",
          hash_including(bill_id: bill.id, error_class: "ArgumentError")
        )
      end
    end

    context "positions call raises a non-Llm error" do
      before do
        provisioning.update!(extracted_testimony: "Testimony from the hearing record.")
        allow(claude_adapter).to receive(:generate_bill_positions)
          .and_raise(ArgumentError.new("invalid byte sequence in UTF-8"))
        allow(SwayLogging).to receive(:warn)
      end

      it "completes the row without re-billing the summary" do
        expect(claude_adapter).to receive(:generate_bill_summary).once.and_return(valid_payload)

        expect { described_class.new.perform(bill.id) }.not_to raise_error

        expect(provisioning.reload.generation_status).to eq("completed")
      end

      it "preserves operator-curated positions" do
        provisioning.update!(draft_org_positions: curated_positions)

        described_class.new.perform(bill.id)

        expect(provisioning.reload.draft_org_positions).to eq(curated_positions)
      end
    end

    # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Preserving the summary when positions fail]]
    context "positions payload that cannot be serialized" do
      before do
        provisioning.update!(extracted_testimony: "Testimony from the hearing record.")
        bad_org_name = (+"ACME \xC3\x28 Coalition").force_encoding(Encoding::UTF_8)
        allow(claude_adapter).to receive(:generate_bill_positions).and_return({
          "draft_org_positions" => [
            {"org_name" => bad_org_name, "stance" => "support", "summary" => "Supports the bill."}
          ]
        })
        allow(SwayLogging).to receive(:warn)
      end

      it "completes the row rather than failing an already-paid-for summary" do
        expect { described_class.new.perform(bill.id) }.not_to raise_error

        provisioning.reload
        expect(provisioning.generation_status).to eq("completed")
        expect(provisioning.llm_summary).to eq(valid_payload["summary_markdown"])
      end

      it "leaves the previously curated positions intact and unpolluted" do
        provisioning.update!(draft_org_positions: curated_positions)

        described_class.new.perform(bill.id)

        expect(provisioning.reload.draft_org_positions).to eq(curated_positions)
      end
    end

    # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Bounded errors preserve the operator instruction]]
    context "positions failure with an oversized error message" do
      before do
        provisioning.update!(extracted_testimony: "Testimony from the hearing record.")
        allow(claude_adapter).to receive(:generate_bill_positions)
          .and_raise(Llm::TransportError.new("x" * 5_000))
        allow(SwayLogging).to receive(:warn)
      end

      it "keeps generation_error within MAX_GENERATION_ERROR_LENGTH" do
        described_class.new.perform(bill.id)

        expect(provisioning.reload.generation_error.length)
          .to be <= described_class::MAX_GENERATION_ERROR_LENGTH
      end

      it "still leads with the prefix that tells the operator the summary is fine" do
        described_class.new.perform(bill.id)

        expect(provisioning.reload.generation_error)
          .to start_with("positions call failed (the summary is valid): ")
      end
    end

    # The outer ladder has to keep treating a SUMMARY failure as deterministic —
    # widening the inner rescue must not swallow this one.
    context "summary schema failure" do
      before do
        allow(claude_adapter).to receive(:generate_bill_summary)
          .and_raise(Llm::SchemaError.new("schema validation failed from claude: missing summary_markdown"))
      end

      it "still fails the row and raises the discardable error" do
        expect { described_class.new.perform(bill.id) }
          .to raise_error(GenerateBillSummaryJob::DeterministicBillSummaryError)
        expect(provisioning.reload.generation_status).to eq("failed")
      end
    end

    # @lat: [[explanation/llm-summaries#Batch summarisation#One settle shared by the job and the ingest]]
    context "the row is settled concurrently while the positions call is in flight (B2-CR-02)" do
      before do
        provisioning.update!(extracted_testimony: "Testimony from the hearing record.")
        allow(SwayLogging).to receive(:warn)
        allow(SwayLogging).to receive(:log_exception)
        # Another inline perform_now, from the pipeline's summarize stage,
        # reaches `completed` while this job is waiting for the positions
        # response.
        allow(claude_adapter).to receive(:generate_bill_positions) do
          BillLlmProvisioning.find(provisioning.id).update_columns(generation_status: "completed")
          raise Llm::TransportError, "429 rate limited"
        end
      end

      it "does not raise past the positions rescue" do
        expect { described_class.new.perform(bill.id) }.not_to raise_error
      end

      it "does not re-issue the already-paid-for summary call" do
        expect(claude_adapter).to receive(:generate_bill_summary).once.and_return(valid_payload)

        described_class.new.perform(bill.id)
      end

      it "leaves the row completed rather than stranding it under a foreign error" do
        described_class.new.perform(bill.id)

        provisioning.reload
        expect(provisioning.generation_status).to eq("completed")
        expect(provisioning.generation_error).to start_with("positions call failed (the summary is valid): ")
        expect(provisioning.generation_error).not_to include("InvalidTransition")
      end

      # The reason the reload exists must stay handled: a positions payload that
      # cannot be saved must still not make mark_completed!'s save raise again.
      it "still drops a payload the JSON coder rejected" do
        bad_org_name = (+"ACME \xC3\x28 Coalition").force_encoding(Encoding::UTF_8)
        allow(claude_adapter).to receive(:generate_bill_positions).and_return({
          "draft_org_positions" => [
            {"org_name" => bad_org_name, "stance" => "support", "summary" => "Supports the bill."}
          ]
        })

        expect { described_class.new.perform(bill.id) }.not_to raise_error

        expect(provisioning.reload.generation_status).to eq("completed")
      end
    end

    # @lat: [[explanation/llm-summaries#Output is validated, not trusted#Failure logging preserves the committed outcome]]
    context "an exception raised after the row is already terminal (B-WR-01 hole a)" do
      before do
        allow(SwayLogging).to receive(:log_exception)
        allow(SwayLogging).to receive(:info).and_call_original
        # The success log at the very end of #perform, after mark_completed!, is
        # the easiest raise-after-the-row-is-final there is to reach.
        allow(SwayLogging).to receive(:info)
          .with("generate_bill_summary.success", anything)
          .and_raise(RuntimeError.new("log sink unavailable"))
      end

      it "does not tag the completed row with an unrelated generation_error" do
        expect { described_class.new.perform(bill.id) }
          .to raise_error(GenerateBillSummaryJob::TransientBillSummaryError)

        provisioning.reload
        expect(provisioning.generation_status).to eq("completed")
        expect(provisioning.generation_error).to be_nil
      end
    end
  end

  # Citations are checked against the bill's parsed BillSectionReference records,
  # which are the ground truth, and the verdict is saved either way. An invalid
  # citation never stops the job completing: it is flagged and shown, not
  # blocked.
  describe "#perform — citation validation persistence (Req 5, SUMM-03)" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }
    let!(:real_section) { create(:bill_section_reference, bill: bill, key: "art_1__sec_1") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(claude_adapter)
    end

    context "citation validation — fabricated key" do
      let(:payload_with_fabricated_citation) do
        valid_payload.merge("cited_section_keys" => ["art_1__sec_1", "art_99__sec_99"])
      end

      before do
        allow(claude_adapter).to receive(:generate_bill_summary).and_return(payload_with_fabricated_citation)
      end

      it "persists citations_valid: false with the fabricated key in invalid_citations" do
        described_class.perform_now(bill.id)
        provisioning.reload
        expect(provisioning.citations_valid).to be(false)
        expect(provisioning.invalid_citations).to eq(["art_99__sec_99"])
      end

      it "still completes the job — an invalid citation never blocks completion" do
        described_class.perform_now(bill.id)
        expect(provisioning.reload.generation_status).to eq("completed")
      end
    end

    context "citation validation — real-only keys" do
      let(:payload_real_only) { valid_payload.merge("cited_section_keys" => ["art_1__sec_1"]) }

      before { allow(claude_adapter).to receive(:generate_bill_summary).and_return(payload_real_only) }

      it "persists citations_valid: true and an empty invalid_citations" do
        described_class.perform_now(bill.id)
        provisioning.reload
        expect(provisioning.citations_valid).to be(true)
        expect(provisioning.invalid_citations).to eq([])
      end
    end

    # @lat: [[explanation/llm-summaries#Public summary content and source grounding]]
    context "citation validation — omitted cited_section_keys" do
      let(:payload_nil_citations) { valid_payload.except("cited_section_keys") }

      before { allow(claude_adapter).to receive(:generate_bill_summary).and_return(payload_nil_citations) }

      it "persists citations_valid: nil — not validated, not clean" do
        described_class.perform_now(bill.id)
        expect(provisioning.reload.citations_valid).to be_nil
      end

      it "persists invalid_citations: nil rather than an empty clean list" do
        described_class.perform_now(bill.id)
        expect(provisioning.reload.invalid_citations).to be_nil
      end

      it "does not leave a prior run's verdict standing" do
        provisioning.update!(citations_valid: false, invalid_citations: ["art_99__sec_1"])

        described_class.perform_now(bill.id)

        provisioning.reload
        expect(provisioning.citations_valid).to be_nil
        expect(provisioning.invalid_citations).to be_nil
      end
    end

    # An explicit empty array claims something different from a missing key: the
    # model said "I cite nothing", and nothing it cited is wrong. That stays a
    # clean verdict for both writers.
    context "citation validation — explicit empty cited_section_keys" do
      let(:payload_empty_citations) { valid_payload.merge("cited_section_keys" => []) }

      before { allow(claude_adapter).to receive(:generate_bill_summary).and_return(payload_empty_citations) }

      it "persists citations_valid: true — an explicit empty citation list is checkable and clean" do
        described_class.perform_now(bill.id)
        expect(provisioning.reload.citations_valid).to be(true)
      end
    end

    context "news URL citation validation" do
      let(:news_url) { "https://www.thebaltimorebanner.com/story-1" }

      before do
        provisioning.update!(
          news_articles: [{"url" => news_url, "title" => "Title", "cited_text" => "Snippet"}]
        )
      end

      it "persists news_urls_valid: true and empty invalid_news_urls when cited news URL is valid" do
        payload = valid_payload.merge("cited_news_urls" => [news_url])
        allow(claude_adapter).to receive(:generate_bill_summary).and_return(payload)

        described_class.perform_now(bill.id)

        provisioning.reload
        expect(provisioning.news_urls_valid).to be(true)
        expect(provisioning.invalid_news_urls).to eq([])
      end

      it "persists news_urls_valid: false and invalid_news_urls when cited news URL is unlisted, and still completes" do
        unlisted = "https://unlisted-outlet.com/article"
        payload = valid_payload.merge("cited_news_urls" => [unlisted])
        allow(claude_adapter).to receive(:generate_bill_summary).and_return(payload)

        described_class.perform_now(bill.id)

        provisioning.reload
        expect(provisioning.news_urls_valid).to be(false)
        expect(provisioning.invalid_news_urls).to eq([unlisted])
        expect(provisioning.generation_status).to eq("completed")
      end

      it "persists news_urls_valid: nil and invalid_news_urls: nil when no news claim is made" do
        allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)

        described_class.perform_now(bill.id)

        provisioning.reload
        expect(provisioning.news_urls_valid).to be_nil
        expect(provisioning.invalid_news_urls).to be_nil
      end
    end

    # The two writers must not be able to drift apart again, so they share one
    # entry point instead of each carrying its own hand-copied rule.
    it "derives the verdict through the same entry point PasteSummaryService uses" do
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      allow(SummaryCitationValidator).to receive(:verdict_attrs).and_call_original

      described_class.perform_now(bill.id)

      expect(SummaryCitationValidator).to have_received(:verdict_attrs).with(bill: bill, payload: valid_payload)
    end
  end

  # A finished generation publishes itself, and never over words a
  # person wrote.
  describe "publishing the summary to the bill page" do
    def run_publish_summary_job(payload)
      stub_app_config(:llm, llm_provider: "claude")
      adapter = instance_double(Llm::ClaudeAdapter, provider_label: "claude")
      allow(Llm::Client).to receive(:build).with(provider: "claude").and_return(adapter)
      allow(adapter).to receive(:generate_bill_summary).and_return(payload)
      described_class.new.perform(bill.id)
    end

    it "publishes over the ingestion placeholder" do
      bill.update!(summary: Bill::SUMMARY_PLACEHOLDER)

      run_publish_summary_job(valid_payload)

      expect(bill.reload.summary).to eq(valid_payload["summary_markdown"])
      expect(bill.summary_ai_unreviewed?).to be(true)
    end

    # The C21-02 rule. The published text and the draft this run replaces are
    # DIFFERENT strings here, which is the only shape that can catch a publish
    # that ignores the question.
    it "refuses to publish over a summary a person wrote" do
      bill.update!(summary: "An admin wrote this by hand.")
      provisioning.update!(llm_summary: "The last run wrote something else.")

      run_publish_summary_job(valid_payload)

      expect(bill.reload.summary).to eq("An admin wrote this by hand.")
      # And because the two now differ, the page says a person wrote it.
      expect(bill.summary_ai_unreviewed?).to be(false)
    end

    it "publishes over the draft an earlier run published" do
      bill.update!(summary: "The last run wrote this.")
      provisioning.update!(llm_summary: "The last run wrote this.")

      run_publish_summary_job(valid_payload)

      expect(bill.reload.summary).to eq(valid_payload["summary_markdown"])
      expect(bill.summary_ai_unreviewed?).to be(true)
    end

    # Generating and publishing land together, so the two columns can never
    # disagree in the window that would strip the notice off unread text.
    it "leaves the published summary equal to the draft it just wrote" do
      bill.update!(summary: Bill::SUMMARY_PLACEHOLDER)

      run_publish_summary_job(valid_payload)

      expect(bill.reload.summary).to eq(provisioning.reload.llm_summary)
    end
  end

  describe "pre-summarization news article fetching" do
    let(:sway_locale) { SwayLocale.find_by(city: "baltimore") || create(:sway_locale, :baltimore) }
    let(:bill) { create(:bill, sway_locale: sway_locale, extracted_text: "Section 1. City Council Bill.") }
    let!(:provisioning) { create(:bill_llm_provisioning, :pending, :with_diff_content, bill: bill) }
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      allow(SwayLogging).to receive(:warn)
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
    end

    # @lat: [[news-implicit#Decoupling news discovery from pipeline execution]]
    it "does not call BillNewsArticleFetchService before summarization" do
      expect(BillNewsArticleFetchService).not_to receive(:call)
      described_class.new.perform(bill.id)
      expect(provisioning.reload.generation_status).to eq("completed")
    end
  end

  describe "news reporting draft positions filtering and persistence" do
    let(:sway_locale) { SwayLocale.find_by(city: "baltimore") || create(:sway_locale, :baltimore) }
    let(:bill) { create(:bill, sway_locale: sway_locale, extracted_text: "Section 1. City Council Housing Bill.") }
    let!(:provisioning) { create(:bill_llm_provisioning, :pending, :with_diff_content, bill: bill, extracted_testimony: nil, supplemental_testimony: nil) }
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    let(:article_text) do
      "The Baltimore Tenants Union strongly backed the bill. Jane Doe, executive director of the Baltimore Tenants Union, said: \"We need this protection now.\""
    end
    let!(:bill_news_article) do
      reporting_article = create(:news_article, outlet_name: "The Baltimore Banner", title: "Housing Debate", canonical_url: "https://example.com/housing")
      version = create(:news_article_text_version, :extracted, news_article: reporting_article, text: article_text)
      create(:bill_news_article, :approved, bill: bill, news_article: reporting_article, current_text_version: version)
    end
    let(:reporting_article) { bill_news_article.news_article }
    let(:text_version) { bill_news_article.current_text_version }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      allow(SwayLogging).to receive(:info)
      allow(SwayLogging).to receive(:warn)
    end

    it "filters raw model positions through NewsOrgPositionGroundingService and persists grounded news drafts without hearing testimony" do
      grounded_payload = {
        "draft_org_positions" => [
          {
            "org_name" => "Baltimore Tenants Union",
            "stance" => "support",
            "summary" => "Initial summary",
            "bill_news_article_id" => bill_news_article.id,
            "text_version_id" => text_version.id,
            "evidence_excerpt" => "said: \"We need this protection now.\"",
            "speaker_name" => "Jane Doe",
            "speaker_role" => "executive director"
          }
        ]
      }
      allow(claude_adapter).to receive(:generate_bill_positions).and_return(grounded_payload)

      initial_org_count = Organization.count
      initial_pos_count = OrganizationBillPosition.count

      described_class.new.perform(bill.id)

      expect(Organization.count).to eq(initial_org_count)
      expect(OrganizationBillPosition.count).to eq(initial_pos_count)

      drafts = provisioning.reload.draft_org_positions
      expect(drafts).to be_present
      expect(drafts.length).to eq(1)
      first_draft = drafts.first
      expect(first_draft["org_name"]).to eq("Baltimore Tenants Union")
      expect(first_draft["bill_news_article_id"]).to eq(bill_news_article.id)
      expect(first_draft["text_version_id"]).to eq(text_version.id)
      expect(first_draft["source_url"]).to eq("https://example.com/housing")
      expect(first_draft["summary"]).to include("\"We need this protection now.\"")
    end

    it "drops ungrounded news positions and maintains zero created Organization or OrganizationBillPosition rows" do
      ungrounded_payload = {
        "draft_org_positions" => [
          {
            "org_name" => "Hallucinated Group",
            "stance" => "oppose",
            "summary" => "Opposed",
            "bill_news_article_id" => bill_news_article.id,
            "text_version_id" => text_version.id,
            "evidence_excerpt" => "nonexistent text quote",
            "speaker_name" => "Nobody",
            "speaker_role" => "executive director"
          }
        ]
      }
      allow(claude_adapter).to receive(:generate_bill_positions).and_return(ungrounded_payload)

      initial_org_count = Organization.count
      initial_pos_count = OrganizationBillPosition.count

      described_class.new.perform(bill.id)

      expect(Organization.count).to eq(initial_org_count)
      expect(OrganizationBillPosition.count).to eq(initial_pos_count)

      expect(provisioning.reload.draft_org_positions).to eq([])
    end

    it "resumes the positions half after purchase on a bill with approved news reporting and no hearing testimony" do
      job = described_class.new(bill.id)
      run_id = job.job_id
      provisioning.update_columns(
        summary_run_id: run_id,
        llm_summary: "A summary purchased in an earlier execution.",
        draft_org_positions: nil
      )
      grounded_payload = {
        "draft_org_positions" => [
          {
            "org_name" => "Baltimore Tenants Union",
            "stance" => "support",
            "summary" => "Initial summary",
            "bill_news_article_id" => bill_news_article.id,
            "text_version_id" => text_version.id,
            "evidence_excerpt" => "said: \"We need this protection now.\"",
            "speaker_name" => "Jane Doe",
            "speaker_role" => "executive director"
          }
        ]
      }
      allow(claude_adapter).to receive(:generate_bill_positions).and_return(grounded_payload)

      expect(claude_adapter).not_to receive(:generate_bill_summary)
      job.perform(bill.id)

      expect(provisioning.reload.draft_org_positions).to be_present
      expect(provisioning.draft_org_positions.first["org_name"]).to eq("Baltimore Tenants Union")
    end

    it "preserves hearing positions and news positions when hearing testimony is present" do
      provisioning.update!(extracted_testimony: "Official hearing testimony from Maryland League.")
      combined_payload = {
        "draft_org_positions" => [
          {
            "org_name" => "Maryland League",
            "stance" => "support",
            "summary" => "Spoke in favor at the hearing."
          },
          {
            "org_name" => "Baltimore Tenants Union",
            "stance" => "support",
            "summary" => "Initial summary",
            "bill_news_article_id" => bill_news_article.id,
            "text_version_id" => text_version.id,
            "evidence_excerpt" => "said: \"We need this protection now.\"",
            "speaker_name" => "Jane Doe",
            "speaker_role" => "executive director"
          }
        ]
      }
      allow(claude_adapter).to receive(:generate_bill_positions).and_return(combined_payload)

      described_class.new.perform(bill.id)

      drafts = provisioning.reload.draft_org_positions
      expect(drafts.length).to eq(2)
      expect(drafts.pluck("org_name")).to contain_exactly("Maryland League", "Baltimore Tenants Union")
    end
  end

  # @lat: [[llm-summaries#Output is validated, not trusted#Multi-chunk positions generation and deduplication]]
  describe "chunked bill positions merging and deduplication" do
    let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

    before do
      stub_app_config(:llm, llm_provider: "claude")
      allow(Llm::Client).to receive(:build).and_return(claude_adapter)
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)
      allow(SwayLogging).to receive(:info)
      allow(SwayLogging).to receive(:warn)
      provisioning.update!(extracted_testimony: "Hearing testimony submitted by organizations.")
    end

    context "when prompt_payloads returns a single chunk" do
      it "calls adapter.generate_bill_positions once and preserves existing behavior" do
        single_payload = Llm::PromptPayload.new(system_prompt: "sys", user_message: "user single")
        positions_response = {
          "draft_org_positions" => [
            {"org_name" => "Maryland Tenants Union", "stance" => "support", "summary" => "MTU single chunk testimony"}
          ]
        }
        allow_any_instance_of(BillPositionsPromptBuilder).to receive(:prompt_payloads).and_return([single_payload])

        expect(claude_adapter).to receive(:generate_bill_positions).once.with(
          hash_including(prompt: single_payload)
        ).and_return(positions_response)

        described_class.new.perform(bill.id)

        expect(provisioning.reload.draft_org_positions.length).to eq(1)
        expect(provisioning.draft_org_positions.first["org_name"]).to eq("Maryland Tenants Union")
      end
    end

    context "when prompt_payloads returns multiple chunks" do
      it "invokes adapter.generate_bill_positions once per chunk payload in sequential order" do
        payload_0 = Llm::PromptPayload.new(system_prompt: "sys", user_message: "chunk 0 message")
        payload_1 = Llm::PromptPayload.new(system_prompt: "sys", user_message: "chunk 1 message")
        chunk_0_response = {
          "draft_org_positions" => [
            {"org_name" => "Maryland Tenants Union", "stance" => "support", "summary" => "Chunk 0 MTU position"}
          ]
        }
        chunk_1_response = {
          "draft_org_positions" => [
            {"org_name" => "Baltimore Teachers Union", "stance" => "support", "summary" => "Chunk 1 BTU position"}
          ]
        }
        allow_any_instance_of(BillPositionsPromptBuilder).to receive(:prompt_payloads).and_return([payload_0, payload_1])

        expect(claude_adapter).to receive(:generate_bill_positions).with(
          hash_including(prompt: payload_0)
        ).ordered.and_return(chunk_0_response)

        expect(claude_adapter).to receive(:generate_bill_positions).with(
          hash_including(prompt: payload_1)
        ).ordered.and_return(chunk_1_response)

        described_class.new.perform(bill.id)
      end

      it "concatenates positions, deduplicates by canonical org name keeping chunk 0 on collision, and caps at MAX_DRAFT_POSITIONS" do
        payload_0 = Llm::PromptPayload.new(system_prompt: "sys", user_message: "chunk 0 message")
        payload_1 = Llm::PromptPayload.new(system_prompt: "sys", user_message: "chunk 1 message")
        allow_any_instance_of(BillPositionsPromptBuilder).to receive(:prompt_payloads).and_return([payload_0, payload_1])

        chunk_0_positions = [
          {"org_name" => "Maryland Tenants Union", "stance" => "support", "summary" => "First seen MTU summary"}
        ] + 30.times.map do |i|
          {"org_name" => "Early Org #{i}", "stance" => "support", "summary" => "Summary #{i}"}
        end

        chunk_1_positions = [
          {"org_name" => "The Maryland Tenants Union, Inc.", "stance" => "oppose", "summary" => "Duplicate MTU summary from chunk 1"}
        ] + 30.times.map do |i|
          {"org_name" => "Later Org #{i}", "stance" => "oppose", "summary" => "Later summary #{i}"}
        end

        allow(claude_adapter).to receive(:generate_bill_positions).with(
          hash_including(prompt: payload_0)
        ).and_return({"draft_org_positions" => chunk_0_positions})

        allow(claude_adapter).to receive(:generate_bill_positions).with(
          hash_including(prompt: payload_1)
        ).and_return({"draft_org_positions" => chunk_1_positions})

        described_class.new.perform(bill.id)

        drafts = provisioning.reload.draft_org_positions
        expect(drafts.length).to eq(BillPositionsPromptBuilder::MAX_DRAFT_POSITIONS)
        mtu = drafts.find { |p| NewsOrgPositionGroundingService.normalize_organization_name(p["org_name"]) == "maryland tenants union" }
        expect(mtu["summary"]).to eq("First seen MTU summary")
        expect(mtu["stance"]).to eq("support")
      end

      it "deduplicates draft_news_testimonies by [bill_news_article_id, text_version_id] supporting string and symbol keys" do
        payload_0 = Llm::PromptPayload.new(system_prompt: "sys", user_message: "chunk 0 message")
        payload_1 = Llm::PromptPayload.new(system_prompt: "sys", user_message: "chunk 1 message")
        allow_any_instance_of(BillPositionsPromptBuilder).to receive(:prompt_payloads).and_return([payload_0, payload_1])

        article_1 = create(:news_article, :op_ed, outlet_name: "The Sun", title: "OpEd 1")
        version_1 = create(:news_article_text_version, :extracted, news_article: article_1, text: "OpEd 1 text.")
        op_ed = create(:bill_news_article, :approved, :support, bill: bill, news_article: article_1, current_text_version: version_1)

        article_2 = create(:news_article, :op_ed, outlet_name: "The Banner", title: "OpEd 2")
        version_2 = create(:news_article_text_version, :extracted, news_article: article_2, text: "OpEd 2 text.")
        op_ed_2 = create(:bill_news_article, :approved, :oppose, bill: bill, news_article: article_2, current_text_version: version_2)

        chunk_0_news = [
          {
            "bill_news_article_id" => op_ed.id,
            "text_version_id" => op_ed.current_text_version_id,
            "stance" => "support",
            "argument" => "First seen argument from chunk 0"
          }
        ]
        chunk_1_news = [
          {
            bill_news_article_id: op_ed.id,
            text_version_id: op_ed.current_text_version_id,
            stance: "support",
            argument: "Duplicate echoed argument from chunk 1 with symbol keys"
          },
          {
            "bill_news_article_id" => op_ed_2.id,
            "text_version_id" => op_ed_2.current_text_version_id,
            "stance" => "oppose",
            "argument" => "Unique argument from chunk 1"
          }
        ]

        allow(claude_adapter).to receive(:generate_bill_positions).with(
          hash_including(prompt: payload_0)
        ).and_return({"draft_org_positions" => [], "draft_news_testimonies" => chunk_0_news})

        allow(claude_adapter).to receive(:generate_bill_positions).with(
          hash_including(prompt: payload_1)
        ).and_return({"draft_org_positions" => [], "draft_news_testimonies" => chunk_1_news})

        captured_payload = {}
        allow(NewsArticleTestimonyService).to receive(:persist_drafts!) do |kwargs|
          captured_payload = kwargs[:payload] || {}
        end
        allow(NewsArticleTestimonyService).to receive(:publish_commentary!)

        described_class.new.perform(bill.id)

        expect(captured_payload).not_to be_empty
        testimonies = captured_payload["draft_news_testimonies"]
        expect(testimonies.length).to eq(2)
        first_testimony = testimonies.find do |t|
          (t["bill_news_article_id"] || t[:bill_news_article_id]) == op_ed.id
        end
        expect(first_testimony["argument"] || first_testimony[:argument]).to eq("First seen argument from chunk 0")
      end

      it "absorbs failures on later chunks without persisting partial drafts" do
        payload_0 = Llm::PromptPayload.new(system_prompt: "sys", user_message: "chunk 0 message")
        payload_1 = Llm::PromptPayload.new(system_prompt: "sys", user_message: "chunk 1 message")
        allow_any_instance_of(BillPositionsPromptBuilder).to receive(:prompt_payloads).and_return([payload_0, payload_1])

        allow(claude_adapter).to receive(:generate_bill_positions).with(
          hash_including(prompt: payload_0)
        ).and_return({"draft_org_positions" => [{"org_name" => "Org A", "stance" => "support", "summary" => "Sum A"}]})

        allow(claude_adapter).to receive(:generate_bill_positions).with(
          hash_including(prompt: payload_1)
        ).and_raise(Llm::TransportError.new("chunk 1 transport failed"))

        allow(SwayLogging).to receive(:warn)

        expect { described_class.new.perform(bill.id) }.not_to raise_error
        expect(provisioning.reload.draft_org_positions).to be_nil
        expect(provisioning.generation_status).to eq("completed")
        expect(provisioning.generation_error).to include("chunk 1 transport failed")
      end
    end
  end
end
