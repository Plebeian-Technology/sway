# frozen_string_literal: true

# A batch of 2 tiny requests on Sonnet 5.5, batch-discounted — well under $0.01, but real spend.
require "rails_helper"

RSpec.describe Llm::ClaudeBatchService, "live Claude Batches API integration", :integration do
  before do
    if ENV["ANTHROPIC_API_KEY"].to_s.empty?
      skip "ANTHROPIC_API_KEY not set — live Anthropic API integration skipped"
    end
    unless ENV["RUN_LIVE_LLM_TESTS"] == "1"
      skip "RUN_LIVE_LLM_TESTS=1 not set — live spec skipped to prevent accidental API spend"
    end
  end

  let(:model) { "claude-sonnet-5-5" }
  let(:schema) { BILL_CATEGORIES_SCHEMA_HASH }

  def synthetic_item(custom_id, topic)
    prompt = Llm::PromptPayload.new(
      system_prompt: "You classify a one-sentence bill description into 1-3 categories. " \
        "Respond with JSON matching the given schema only.",
      user_message: "Bill description: #{topic}"
    )
    Llm::ClaudeBatchService::Item.new(
      custom_id: custom_id, prompt: prompt, model: model, schema: schema, validation_schema: BILL_CATEGORIES_SCHEMA
    )
  end

  let(:items) do
    [
      synthetic_item("synthetic-a", "A bill funding new public school libraries."),
      synthetic_item("synthetic-b", "A bill regulating stormwater runoff permits.")
    ]
  end

  it "submits, polls to completion, and resolves both results by custom_id" do
    poll_timeout_seconds = 600
    poll_interval_seconds = 10
    batch = described_class.submit(items: items)

    deadline = Time.current + poll_timeout_seconds
    status = described_class.status(batch_id: batch.id)
    while status.processing_status.to_s != "ended" && Time.current < deadline
      sleep poll_interval_seconds
      status = described_class.status(batch_id: batch.id)
    end
    expect(status.processing_status.to_s).to eq("ended"), "batch #{batch.id} did not end within #{poll_timeout_seconds}s"

    items_by_custom_id = items.index_by(&:custom_id)
    results = described_class.results(batch_id: batch.id, items_by_custom_id: items_by_custom_id)

    expect(results.keys).to contain_exactly("synthetic-a", "synthetic-b")
    results.each do |custom_id, result|
      expect(result.error).to be_nil, "#{custom_id} failed: #{result.error&.message}"
      expect(BILL_CATEGORIES_SCHEMA.validate(result.value).to_a).to be_empty
    end
  end
end
