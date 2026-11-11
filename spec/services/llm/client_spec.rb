# frozen_string_literal: true

require "rails_helper"

# Llm::Client.build(provider:) is the one place GenerateBillSummaryJob picks
# an adapter, read from Sway::Settings.llm.llm_provider; unrecognized values
# raise right away rather than guessing.
RSpec.describe Llm::Client do
  describe ".build" do
    it "returns a Llm::ClaudeAdapter when provider is 'claude'" do
      adapter = described_class.build(provider: "claude")
      expect(adapter).to be_a(Llm::ClaudeAdapter)
    end

    it "returns a Llm::LlamacppAdapter when provider is 'llamacpp'" do
      adapter = described_class.build(provider: "llamacpp")
      expect(adapter).to be_a(Llm::LlamacppAdapter)
    end

    it "returns a Llm::OpenRouterAdapter when provider is 'openrouter'" do
      adapter = described_class.build(provider: "openrouter")
      expect(adapter).to be_a(Llm::OpenRouterAdapter)
    end

    it "raises ArgumentError for unknown providers (fail-fast) naming all three allowed providers" do
      expect {
        described_class.build(provider: "openai")
      }.to raise_error(ArgumentError, 'unknown provider: "openai" (allowed: claude, llamacpp, openrouter)')
    end

    it "reads Sway::Settings.llm.llm_provider when no argument is supplied" do
      with_app_config(:llm, llm_provider: "claude") do
        expect(described_class.build).to be_a(Llm::ClaudeAdapter)
      end
    end

    it "returns a Llm::OpenRouterAdapter when Sway::Settings.llm.llm_provider is 'openrouter'" do
      with_app_config(:llm, llm_provider: "openrouter") do
        expect(described_class.build).to be_a(Llm::OpenRouterAdapter)
      end
    end

    it "defaults to llamacpp when the setting is unset" do
      with_app_config(:llm, llm_provider: nil) do
        expect(described_class.build).to be_a(Llm::LlamacppAdapter)
      end
    end

    # The group is memoized once per process, not re-read here on
    # every call -- but .build itself takes no snapshot of its own, so a
    # spec that swaps the setting between calls still sees the change.
    it "reads the setting fresh on every call, not cached inside .build" do
      with_app_config(:llm, llm_provider: "claude") do
        expect(described_class.build).to be_a(Llm::ClaudeAdapter)
      end

      expect(described_class.build).to be_a(Llm::LlamacppAdapter)
    end

    # @lat: [[llm-settings-group-design#Why an empty LLM_PROVIDER never reaches Llm::Client.build's unknown-provider branch]]
    it "treats LLM_PROVIDER='' (empty) as 'llamacpp'" do
      with_env("LLM_PROVIDER" => "") do
        expect(Sway::Settings::Llm.new.llm_provider).to eq("llamacpp")
      end
    end

    it "treats LLM_PROVIDER='   ' (whitespace-only) as 'llamacpp'" do
      with_env("LLM_PROVIDER" => "   ") do
        expect(Sway::Settings::Llm.new.llm_provider).to eq("llamacpp")
      end
    end

    # provider: '' is the CALLER'S argument, not the setting -- .build's own
    # strip-and-fallback (the line the settings migration left in place)
    # handles this before Sway::Settings.llm is ever consulted.
    it "treats provider: '' (empty argument) as 'llamacpp'" do
      expect(described_class.build(provider: "")).to be_a(Llm::LlamacppAdapter)
    end
  end

  describe "news search obsolescence" do
    it "does not respond to supports_news_search?" do
      expect(described_class).not_to respond_to(:supports_news_search?)
    end

    it "does not respond to news_search_supported?" do
      expect(described_class).not_to respond_to(:news_search_supported?)
    end

    it "ensures adapters do not respond to news search methods" do
      %w[claude openrouter llamacpp].each do |provider|
        adapter = described_class.build(provider: provider)
        expect(adapter).not_to respond_to(:generate_bill_news_articles)
        expect(adapter).not_to respond_to(:supports_news_search?)
        expect(adapter).not_to respond_to(:news_search_supported?)
      end
    end

    it "ensures news search param and response constants are removed" do
      expect(Llm.const_defined?(:ClaudeNewsSearchParams)).to be(false)
      expect(Llm.const_defined?(:ClaudeNewsSearchResponse)).to be(false)
    end
  end

  describe ".generate_decisions" do
    it "delegates to OpenRouterAdapter by default" do
      model = "scaledown/classify-1"
      state = {"attachment" => {"title" => "Letter"}}
      questions = {"is_testimony" => {"type" => "choice"}}
      adapter_double = instance_double(Llm::OpenRouterAdapter)

      expect(described_class).to receive(:build).with(provider: "openrouter").and_return(adapter_double)
      expect(adapter_double).to receive(:generate_decisions).with(
        model: model,
        state: state,
        questions: questions
      ).and_return({"answers" => {}})

      result = described_class.generate_decisions(model: model, state: state, questions: questions)
      expect(result).to eq({"answers" => {}})
    end

    it "passes custom provider when provided" do
      model = "scaledown/classify-1"
      state = {"attachment" => {"title" => "Letter"}}
      questions = {"is_testimony" => {"type" => "choice"}}
      adapter_double = instance_double(Llm::OpenRouterAdapter)

      expect(described_class).to receive(:build).with(provider: "openrouter").and_return(adapter_double)
      expect(adapter_double).to receive(:generate_decisions).with(
        model: model,
        state: state,
        questions: questions
      ).and_return({"answers" => {}})

      described_class.generate_decisions(
        model: model,
        state: state,
        questions: questions,
        provider: "openrouter"
      )
    end

    it "raises ArgumentError when provider does not support generate_decisions" do
      expect {
        described_class.generate_decisions(
          model: "scaledown/classify-1",
          state: {},
          questions: {"q" => {"type" => "choice"}},
          provider: "claude"
        )
      }.to raise_error(ArgumentError, 'Provider "claude" does not support generate_decisions')

      expect {
        described_class.generate_decisions(
          model: "scaledown/classify-1",
          state: {},
          questions: {"q" => {"type" => "choice"}},
          provider: "llamacpp"
        )
      }.to raise_error(ArgumentError, 'Provider "llamacpp" does not support generate_decisions')
    end

    it "raises ArgumentError when an unknown provider is specified" do
      expect {
        described_class.generate_decisions(
          model: "scaledown/classify-1",
          state: {},
          questions: {"q" => {"type" => "choice"}},
          provider: "non_existent_provider"
        )
      }.to raise_error(ArgumentError, /unknown provider: "non_existent_provider"/)
    end
  end

  describe ".generate_entity_extraction" do
    it "delegates to OpenRouterAdapter by default" do
      model = "scaledown/extract"
      content = "Sample letter text"
      entities = {org_name: "Organization name"}
      adapter_double = instance_double(Llm::OpenRouterAdapter)

      expect(described_class).to receive(:build).with(provider: "openrouter").and_return(adapter_double)
      expect(adapter_double).to receive(:generate_entity_extraction).with(
        model: model,
        content: content,
        entities: entities,
        max_tokens: nil
      ).and_return({"org_name" => "ACLU"})

      result = described_class.generate_entity_extraction(
        model: model,
        content: content,
        entities: entities
      )
      expect(result).to eq({"org_name" => "ACLU"})
    end

    it "forwards max_tokens and custom provider when provided" do
      model = "scaledown/extract"
      content = "Sample letter text"
      entities = {org_name: "Organization name"}
      adapter_double = instance_double(Llm::OpenRouterAdapter)

      expect(described_class).to receive(:build).with(provider: "openrouter").and_return(adapter_double)
      expect(adapter_double).to receive(:generate_entity_extraction).with(
        model: model,
        content: content,
        entities: entities,
        max_tokens: 512
      ).and_return({"org_name" => "ACLU"})

      described_class.generate_entity_extraction(
        model: model,
        content: content,
        entities: entities,
        max_tokens: 512,
        provider: "openrouter"
      )
    end

    it "raises ArgumentError when provider does not support generate_entity_extraction" do
      expect {
        described_class.generate_entity_extraction(
          model: "scaledown/extract",
          content: "Sample letter text",
          entities: {org_name: "Organization name"},
          provider: "claude"
        )
      }.to raise_error(ArgumentError, 'Provider "claude" does not support generate_entity_extraction')

      expect {
        described_class.generate_entity_extraction(
          model: "scaledown/extract",
          content: "Sample letter text",
          entities: {org_name: "Organization name"},
          provider: "llamacpp"
        )
      }.to raise_error(ArgumentError, 'Provider "llamacpp" does not support generate_entity_extraction')
    end

    it "raises ArgumentError when an unknown provider is specified" do
      expect {
        described_class.generate_entity_extraction(
          model: "scaledown/extract",
          content: "Sample letter text",
          entities: {org_name: "Organization name"},
          provider: "non_existent_provider"
        )
      }.to raise_error(ArgumentError, /unknown provider: "non_existent_provider"/)
    end
  end
end
