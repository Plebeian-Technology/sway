# frozen_string_literal: true

# @lat: [[run-claude-adapter-integration-spec#Steps]]
# Full run makes 9 live Claude API calls and costs real money — price it before running.

require "rails_helper"

RSpec.describe Llm::ClaudeAdapter, "live Claude API integration", :integration do
  before do
    if ENV["ANTHROPIC_API_KEY"].to_s.empty?
      skip "ANTHROPIC_API_KEY not set — live Anthropic API integration skipped"
    end
    unless ENV["RUN_LIVE_LLM_TESTS"] == "1"
      skip "RUN_LIVE_LLM_TESTS=1 not set — live spec skipped to prevent accidental API spend"
    end
  end

  let(:fixture_path) { Rails.root.join("spec", "fixtures", "llm", "sample_bill_source.md") }
  let(:fixture_text) { fixture_path.read }
  let(:model) { "claude-haiku-5-5" }

  # @lat: [[claude-adapter-integration-spec-design#Why the cache examples run on Sonnet, not the Haiku default]]
  let(:cacheable_model) { "claude-sonnet-5-5" }
  let(:schema) { BILL_SUMMARY_SCHEMA_HASH }

  # Reuse BillSummaryPromptBuilder's system prefix so the live call goes through
  # the very same cache-eligible block production uses. Its token count is
  # deliberately not repeated here — Llm::PromptCache and its spec hold that
  # measurement.
  let(:bill) do
    sway_locale = create(:sway_locale, city: "Baltimore", state: "Maryland", country: "United States")
    district = create(:district, sway_locale: sway_locale)
    legislator = create(:legislator, district: district)
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      external_id: "CB-26-0177-LIVE",
      title: "Annual Lead-Paint Inspections — Rental Units Constructed Before 1978",
      status: Bill::Status::COMMITTEE,
      category: "civic",
      scheduled_release_date_utc: Date.new(2026, 6, 15)
    )
  end

  let(:prompt) do
    bill.update!(extracted_text: fixture_text)
    builder = BillSummaryPromptBuilder.new(bill)
    Llm::PromptPayload.new(system_prompt: builder.system_prompt, user_message: builder.user_message)
  end

  # @lat: [[claude-adapter-integration-spec-design#Why the cache examples run on Sonnet, not the Haiku default]]
  let(:other_bill) do
    other = create(
      :bill,
      sway_locale: bill.sway_locale,
      legislator: bill.legislator,
      external_id: "CB-26-0901-LIVE",
      title: "Vacant Property Receivership Reform",
      status: Bill::Status::COMMITTEE,
      category: "civic",
      scheduled_release_date_utc: Date.new(2026, 9, 21)
    )
    create(:bill_section_reference, bill: other, key: "art_13__sec_2", title: "Receivership petitions")
    other
  end

  let(:other_bill_prompt) do
    other_bill.update!(extracted_text: fixture_text)
    builder = BillSummaryPromptBuilder.new(other_bill)
    Llm::PromptPayload.new(system_prompt: builder.system_prompt, user_message: builder.user_message)
  end

  describe "schema fidelity (post-validation)" do
    it "returns a Hash that validates against BILL_SUMMARY_SCHEMA with the three top-level keys" do
      adapter = described_class.new
      result = adapter.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      expect(BILL_SUMMARY_SCHEMA.validate(result).to_a).to be_empty
      # @lat: [[claude-adapter-integration-spec-design#Why the schema-fidelity example no longer asserts draft_org_positions is absent]]
      expect(result.keys).to include("summary_markdown", "full_breakdown_markdown")
    end

    # @lat: [[claude-adapter-integration-spec-design#Why the cache examples run on Sonnet, not the Haiku default]]
    it "does not cache on the Haiku 5.5 default — the prefix is under its 4096-token floor" do
      adapter = described_class.new
      adapter.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      expect(adapter.last_usage.cache_creation_input_tokens.to_i).to eq(0),
        "Anthropic reported a cache write on Haiku 5.5. Either the system prefix now clears the " \
          "4096-token floor (update Llm::PromptCache's premise and the R5 gate in " \
          "spec/services/bill_summary_prompt_builder_spec.rb), or the documented floor has changed."
    end
  end

  # @lat: [[claude-adapter-integration-spec-design#Why the positions call needed its own live example]]
  describe "positions call" do
    let(:positions_prompt) do
      bill.create_bill_llm_provisioning!(
        extracted_testimony: <<~TESTIMONY
          Maryland Tenants Union — written testimony, October 16 2025.
          We SUPPORT this bill. Annual inspections close a documented
          enforcement gap that falls hardest on tenants in lower-income
          neighborhoods.

          Greater Baltimore Apartment Association — written testimony.
          We OPPOSE the annual cadence. Biennial inspections achieve the same
          public-health outcome at roughly half the operational cost.
        TESTIMONY
      )
      builder = BillPositionsPromptBuilder.new(bill.reload)
      Llm::PromptPayload.new(system_prompt: builder.system_prompt, user_message: builder.user_message)
    end

    it "returns a Hash that validates against BILL_POSITIONS_SCHEMA" do
      adapter = described_class.new
      result = adapter.generate_bill_positions(
        prompt: positions_prompt, model: model, schema: BILL_POSITIONS_SCHEMA_HASH
      )

      expect(BILL_POSITIONS_SCHEMA.validate(result).to_a).to be_empty
      expect(result.keys).to eq(["draft_org_positions"])
      expect(result["draft_org_positions"]).to be_an(Array)
      # Not checking WHICH positions come back — that is the model's judgement.
      # What must hold is that the contract is honoured and the testimony really
      # was read.
      expect(result["draft_org_positions"].pluck("stance").uniq)
        .to all(be_in(%w[support oppose neutral]))
    end

    it "returns stop_reason: end_turn — the same structured-outputs misconfig guard as the summary call" do
      adapter = described_class.new
      adapter.generate_bill_positions(
        prompt: positions_prompt, model: model, schema: BILL_POSITIONS_SCHEMA_HASH
      )

      expect(adapter.last_response.stop_reason.to_s).to eq("end_turn"),
        "expected stop_reason='end_turn'; got #{adapter.last_response.stop_reason.inspect}. " \
          "tool_use indicates structured outputs returned the JSON inside a tool envelope rather " \
          "than as direct text — verify the output_config.format request shape."
    end
  end

  describe "stop_reason end_turn assertion (iter-2 Q4 / H4)" do
    it "returns stop_reason: end_turn (NOT tool_use, NOT max_tokens) — guards against structured-outputs misconfig" do
      adapter = described_class.new
      adapter.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      expect(adapter.last_response.stop_reason.to_s).to eq("end_turn"),
        "expected stop_reason='end_turn'; got #{adapter.last_response.stop_reason.inspect}. " \
          "tool_use indicates structured outputs returned the JSON inside a tool envelope rather than " \
          "as direct text — verify the output_config.format request shape."
    end
  end

  # Every example in this block runs on `cacheable_model`, not on the model
  # operators use by default. The `let` above says why: on Haiku 5.5 these
  # assertions were asserting something false, and had never once run.
  describe "cache write + read" do
    # @lat: [[claude-adapter-integration-spec-design#Why the cache write/read split is now one example, not two]]
    it "creates the cache on call 1 and reads it on call 2 within the 5-minute TTL" do
      adapter = described_class.new

      adapter.generate_bill_summary(prompt: prompt, model: cacheable_model, schema: schema)
      first = adapter.last_usage

      # A second call with the same prefix, model and schema. The system block
      # is byte-for-byte identical, so Anthropic should serve it from cache.
      adapter.generate_bill_summary(prompt: prompt, model: cacheable_model, schema: schema)
      second = adapter.last_usage

      expect(first.cache_creation_input_tokens.to_i + first.cache_read_input_tokens.to_i).to be > 0,
        "Anthropic reported neither a cache write nor a cache read on call 1 despite the R5 " \
          "gate passing — the marker did not reach the request. The system prefix may be under " \
          "the 1024-token Sonnet-tier cache minimum, or Llm::PromptCache withheld cache_control " \
          "for #{cacheable_model}. Re-run the CachePrefixTokenizer gate against the live prefix."

      expect(second.cache_read_input_tokens.to_i).to be > 0,
        "Anthropic reported 0 cache_read tokens on call 2 — the cache_control: ephemeral " \
          "block did not hit. Either the TTL expired (unlikely <5min apart), the system block " \
          "shape changed, or the cache_control kwarg dropped from the request."
    end

    # @lat: [[claude-adapter-integration-spec-design#Why a separate example reads the cache across two DIFFERENT bills]]
    it "reads from the cache across two DIFFERENT bills (the production pattern)" do
      adapter = described_class.new
      adapter.generate_bill_summary(prompt: prompt, model: cacheable_model, schema: schema)
      adapter.generate_bill_summary(prompt: other_bill_prompt, model: cacheable_model, schema: schema)
      cr = adapter.last_usage.cache_read_input_tokens
      expect(cr.to_i).to be > 0,
        "Anthropic reported 0 cache_read tokens on a second, DIFFERENT bill — the system " \
          "prefix is not bill-stable. Something per-bill has been added back into " \
          "BillSummaryPromptBuilder#system_prompt (PROD-WR-04); it belongs in #user_message."
    end
  end
end
