# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::ModelCatalog do
  # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes]]
  describe ".lookup" do
    context "with OpenRouter model choices" do
      it "maps Deepseek Pro Latest to its OpenRouter route" do
        route = described_class.lookup("Deepseek Pro Latest")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:openrouter)
        expect(route.api_model).to eq("~deepseek/deepseek-pro-latest")
        expect(route.label).to eq("Deepseek Pro Latest")
        expect(route.openrouter?).to be(true)
        expect(route.claude?).to be(false)
        expect(route.llamacpp?).to be(false)
      end

      it "maps Deepseek Flash Latest to its OpenRouter route" do
        route = described_class.lookup("Deepseek Flash Latest")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:openrouter)
        expect(route.api_model).to eq("~deepseek/deepseek-flash-latest")
        expect(route.label).to eq("Deepseek Flash Latest")
        expect(route.openrouter?).to be(true)
      end

      it "maps OpenRouter Auto to its OpenRouter route" do
        route = described_class.lookup("OpenRouter Auto")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:openrouter)
        expect(route.api_model).to eq("openrouter/auto")
        expect(route.label).to eq("OpenRouter Auto")
        expect(route.openrouter?).to be(true)
      end

      it "maps Opus Latest to its OpenRouter route" do
        route = described_class.lookup("Opus Latest")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:openrouter)
        expect(route.api_model).to eq("~anthropic/claude-opus-latest")
        expect(route.label).to eq("Opus Latest")
        expect(route.openrouter?).to be(true)
        expect(route.claude?).to be(false)
        expect(route.llamacpp?).to be(false)
        expect(route.supports_reasoning?).to be(true)
      end

      it "maps Sonnet Latest to its OpenRouter route" do
        route = described_class.lookup("Sonnet Latest")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:openrouter)
        expect(route.api_model).to eq("~anthropic/claude-sonnet-latest")
        expect(route.label).to eq("Sonnet Latest")
        expect(route.openrouter?).to be(true)
        expect(route.supports_reasoning?).to be(true)
      end

      it "maps Haiku Latest to its OpenRouter route" do
        route = described_class.lookup("Haiku Latest")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:openrouter)
        expect(route.api_model).to eq("~anthropic/claude-haiku-latest")
        expect(route.label).to eq("Haiku Latest")
        expect(route.openrouter?).to be(true)
        expect(route.supports_reasoning?).to be(true)
      end

      it "maps Gemini Argon Latest to its OpenRouter route" do
        route = described_class.lookup("Gemini Argon Latest")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:openrouter)
        expect(route.api_model).to eq("google/gemini-4-argon")
        expect(route.label).to eq("Gemini Argon Latest")
        expect(route.openrouter?).to be(true)
        expect(route.supports_reasoning?).to be(true)
      end

      it "maps Gemini Flash Latest to its OpenRouter route" do
        route = described_class.lookup("Gemini Flash Latest")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:openrouter)
        expect(route.api_model).to eq("~google/gemini-flash-latest")
        expect(route.label).to eq("Gemini Flash Latest")
        expect(route.openrouter?).to be(true)
        expect(route.supports_reasoning?).to be(true)
      end

      it "maps GLM Latest to its OpenRouter route" do
        route = described_class.lookup("GLM Latest")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:openrouter)
        expect(route.api_model).to eq("~z-ai/glm-latest")
        expect(route.label).to eq("GLM Latest")
        expect(route.openrouter?).to be(true)
        expect(route.supports_reasoning?).to be(true)
      end

      it "maps canonical OpenRouter alias identifiers" do
        expect(described_class.lookup("~anthropic/claude-opus-latest")).to eq(described_class.lookup("Opus Latest"))
        expect(described_class.lookup("~anthropic/claude-sonnet-latest")).to eq(described_class.lookup("Sonnet Latest"))
        expect(described_class.lookup("~anthropic/claude-haiku-latest")).to eq(described_class.lookup("Haiku Latest"))
        expect(described_class.lookup("google/gemini-4-argon")).to eq(described_class.lookup("Gemini Argon Latest"))
        expect(described_class.lookup("~google/gemini-flash-latest")).to eq(described_class.lookup("Gemini Flash Latest"))
        expect(described_class.lookup("~z-ai/glm-latest")).to eq(described_class.lookup("GLM Latest"))
        expect(described_class.lookup("~deepseek/deepseek-pro-latest")).to eq(described_class.lookup("Deepseek Pro Latest"))
        expect(described_class.lookup("~deepseek/deepseek-flash-latest")).to eq(described_class.lookup("Deepseek Flash Latest"))
        expect(described_class.lookup("openrouter/auto")).to eq(described_class.lookup("OpenRouter Auto"))
      end

      it "normalizes legacy unprefixed latest identifiers to canonical aliases" do
        expect(described_class.lookup("deepseek/deepseek-pro-latest").api_model).to eq("~deepseek/deepseek-pro-latest")
        expect(described_class.lookup("deepseek/deepseek-flash-latest").api_model).to eq("~deepseek/deepseek-flash-latest")
      end

      it "maps hyphenated choice slugs" do
        expect(described_class.lookup("deepseek-pro-latest")).to eq(described_class.lookup("Deepseek Pro Latest"))
        expect(described_class.lookup("deepseek-flash-latest")).to eq(described_class.lookup("Deepseek Flash Latest"))
        expect(described_class.lookup("openrouter-auto")).to eq(described_class.lookup("OpenRouter Auto"))
      end
    end

    context "with OpenRouter decision model choices" do
      it "maps ScaleDown Classify Latest to its OpenRouter decision route" do
        route = described_class.lookup("ScaleDown Classify Latest")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:openrouter)
        expect(route.api_model).to eq("scaledown/classify-1")
        expect(route.label).to eq("ScaleDown Classify Latest")
        expect(route.mode).to eq(:decision)
        expect(route.decision_model?).to be(true)
        expect(route.extraction_model?).to be(false)
        expect(route.supports_reasoning?).to be(false)
        expect(route.deconstruct_keys([:provider, :mode])).to eq(provider: :openrouter, mode: :decision)
      end

      it "maps scaledown/classify-1 compatibility key" do
        expect(described_class.lookup("scaledown/classify-1")).to eq(described_class.lookup("ScaleDown Classify Latest"))
      end

      it "maps Jev Latest and its compatibility keys" do
        route = described_class.lookup("Jev Latest")
        expect(route).not_to be_nil
        expect(route.api_model).to eq("~typesafe/jev-latest")
        expect(route.mode).to eq(:decision)
        expect(route.decision_model?).to be(true)
        expect(route.supports_reasoning?).to be(false)

        expect(described_class.lookup("~typesafe/jev-latest")).to eq(route)
        expect(described_class.lookup("typesafe/jev-1.14")).to eq(route)
        expect(described_class.lookup("typesafe/jev-latest")).to eq(route)
      end

      it "maps Perplexity Decider Latest and its compatibility key" do
        route = described_class.lookup("Perplexity Decider Latest")
        expect(route).not_to be_nil
        expect(route.api_model).to eq("~perplexity/pplx-decider-latest")
        expect(route.mode).to eq(:decision)
        expect(route.decision_model?).to be(true)
        expect(route.supports_reasoning?).to be(false)

        expect(described_class.lookup("~perplexity/pplx-decider-latest")).to eq(route)
      end

      it "maps Perplexity Decider Flash Latest and its compatibility key" do
        route = described_class.lookup("Perplexity Decider Flash Latest")
        expect(route).not_to be_nil
        expect(route.api_model).to eq("~perplexity/pplx-decider-flash-latest")
        expect(route.mode).to eq(:decision)
        expect(route.decision_model?).to be(true)
        expect(route.supports_reasoning?).to be(false)

        expect(described_class.lookup("~perplexity/pplx-decider-flash-latest")).to eq(route)
      end
    end

    context "with OpenRouter extraction model choices" do
      it "maps ScaleDown Extract Latest to its OpenRouter extraction route" do
        route = described_class.lookup("ScaleDown Extract Latest")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:openrouter)
        expect(route.api_model).to eq("scaledown/extract")
        expect(route.label).to eq("ScaleDown Extract Latest")
        expect(route.mode).to eq(:extraction)
        expect(route.extraction_model?).to be(true)
        expect(route.decision_model?).to be(false)
        expect(route.supports_reasoning?).to be(false)
        expect(route.deconstruct_keys([:mode])).to eq(mode: :extraction)
      end

      it "maps scaledown/extract compatibility key" do
        expect(described_class.lookup("scaledown/extract")).to eq(described_class.lookup("ScaleDown Extract Latest"))
      end
    end

    context "with active Claude models" do
      it "maps claude-haiku-5-5 to Claude provider" do
        route = described_class.lookup("claude-haiku-5-5")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:claude)
        expect(route.api_model).to eq("claude-haiku-5-5")
        expect(route.label).to eq("Haiku 5.5")
        expect(route.claude?).to be(true)
        expect(route.openrouter?).to be(false)
      end

      it "maps claude-sonnet-5 to Claude provider" do
        route = described_class.lookup("claude-sonnet-5-5")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:claude)
        expect(route.api_model).to eq("claude-sonnet-5-5")
        expect(route.label).to eq("Sonnet 5.5")
        expect(route.claude?).to be(true)
      end

      it "maps claude-opus-5-5 to Claude provider" do
        route = described_class.lookup("claude-opus-5-5")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:claude)
        expect(route.api_model).to eq("claude-opus-5-5")
        expect(route.label).to eq("Opus 5.5")
        expect(route.claude?).to be(true)
      end
    end

    context "with retired Claude models" do
      it "preserves claude-sonnet-4-6 for historical database rows" do
        route = described_class.lookup("claude-sonnet-4-6")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:claude)
        expect(route.api_model).to eq("claude-sonnet-4-6")
        expect(route.claude?).to be(true)
      end

      it "preserves claude-sonnet-4-5 for historical database rows" do
        route = described_class.lookup("claude-sonnet-4-5")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:claude)
        expect(route.api_model).to eq("claude-sonnet-4-5")
        expect(route.claude?).to be(true)
      end

      it "preserves claude-opus-4-8 for historical database rows" do
        route = described_class.lookup("claude-opus-4-8")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:claude)
        expect(route.api_model).to eq("claude-opus-4-8")
        expect(route.claude?).to be(true)
      end
    end

    context "with dynamic OpenRouter models" do
      it "resolves dynamic OpenRouter models returned by Llm::OpenRouterModelsService" do
        allow(Llm::OpenRouterModelsService).to receive(:lookup).with("openai/gpt-4o").and_return({
          id: "openai/gpt-4o",
          label: "OpenAI: GPT-4o",
          supports_reasoning: true
        })

        route = described_class.lookup("openai/gpt-4o")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:openrouter)
        expect(route.api_model).to eq("openai/gpt-4o")
        expect(route.label).to eq("OpenAI: GPT-4o")
        expect(route.openrouter?).to be(true)
        expect(route.supports_reasoning?).to be(true)
      end

      it "respects supports_reasoning: false from dynamic model lookup" do
        allow(Llm::OpenRouterModelsService).to receive(:lookup).with("meta-llama/llama-3-8b").and_return({
          id: "meta-llama/llama-3-8b",
          label: "Meta: Llama 3 8B",
          supports_reasoning: false
        })

        route = described_class.lookup("meta-llama/llama-3-8b")
        expect(route).not_to be_nil
        expect(route.supports_reasoning?).to be(false)
      end

      it "falls back to stored model route on cold cache when slug is valid and persisted on AdminSetting" do
        allow(Llm::OpenRouterModelsService).to receive(:lookup).with("mistralai/mistral-large").and_return(nil)
        allow(Llm::OpenRouterModelsService).to receive(:valid_slug?).with("mistralai/mistral-large").and_return(true)
        allow(AdminSetting).to receive(:stored_model?).with("mistralai/mistral-large").and_return(true)

        route = described_class.lookup("mistralai/mistral-large")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:openrouter)
        expect(route.api_model).to eq("mistralai/mistral-large")
        expect(route.label).to eq("mistralai/mistral-large")
        expect(route.supports_reasoning?).to be(true)
      end

      it "does not fall back to cold cache route if slug syntax is invalid" do
        allow(Llm::OpenRouterModelsService).to receive(:lookup).with("invalid slug").and_return(nil)
        allow(Llm::OpenRouterModelsService).to receive(:valid_slug?).with("invalid slug").and_return(false)
        allow(AdminSetting).to receive(:stored_model?).with("invalid slug").and_return(true)

        expect(described_class.lookup("invalid slug")).to be_nil
      end

      it "returns nil if model is neither cached nor stored on AdminSetting" do
        allow(Llm::OpenRouterModelsService).to receive(:lookup).with("cohere/command-r").and_return(nil)
        allow(Llm::OpenRouterModelsService).to receive(:valid_slug?).with("cohere/command-r").and_return(true)
        allow(AdminSetting).to receive(:stored_model?).with("cohere/command-r").and_return(false)

        expect(described_class.lookup("cohere/command-r")).to be_nil
      end

      it "resolves dynamic decision model when catalog_models is nil" do
        allow(Llm::OpenRouterModelsService).to receive(:lookup).with("custom/decision-slug").and_return(nil)
        allow(Llm::OpenRouterModelsService).to receive(:lookup_decision_model).with("custom/decision-slug").and_return({
          id: "custom/decision-slug",
          label: "Custom Decision Slug",
          supports_reasoning: false,
          mode: :decision
        })

        route = described_class.lookup("custom/decision-slug")
        expect(route).not_to be_nil
        expect(route.provider).to eq(:openrouter)
        expect(route.api_model).to eq("custom/decision-slug")
        expect(route.mode).to eq(:decision)
        expect(route.decision_model?).to be(true)
        expect(route.supports_reasoning?).to be(false)
      end

      it "does not query lookup_decision_model when catalog_models is provided" do
        allow(Llm::OpenRouterModelsService).to receive(:lookup).with("custom/decision-slug", models: []).and_return(nil)
        expect(Llm::OpenRouterModelsService).not_to receive(:lookup_decision_model)

        expect(described_class.lookup("custom/decision-slug", catalog_models: [])).to be_nil
      end

      it "resolves cold-cache fallback with :decision mode when stored on AdminSetting decision_model" do
        allow(Llm::OpenRouterModelsService).to receive(:lookup).with("custom/stored-decision").and_return(nil)
        allow(Llm::OpenRouterModelsService).to receive(:lookup_decision_model).with("custom/stored-decision").and_return(nil)
        allow(Llm::OpenRouterModelsService).to receive(:valid_slug?).with("custom/stored-decision").and_return(true)
        allow(AdminSetting).to receive(:stored_model?).with("custom/stored-decision").and_return(true)
        allow(AdminSetting).to receive(:column_names).and_return(%w[id summarization_model decision_model extraction_model])
        allow(AdminSetting).to receive(:exists?).with(decision_model: "custom/stored-decision").and_return(true)

        route = described_class.lookup("custom/stored-decision")
        expect(route).not_to be_nil
        expect(route.mode).to eq(:decision)
        expect(route.decision_model?).to be(true)
        expect(route.supports_reasoning?).to be(false)
      end

      it "resolves cold-cache fallback with :extraction mode when stored on AdminSetting extraction_model" do
        allow(Llm::OpenRouterModelsService).to receive(:lookup).with("custom/stored-extract").and_return(nil)
        allow(Llm::OpenRouterModelsService).to receive(:lookup_decision_model).with("custom/stored-extract").and_return(nil)
        allow(Llm::OpenRouterModelsService).to receive(:valid_slug?).with("custom/stored-extract").and_return(true)
        allow(AdminSetting).to receive(:stored_model?).with("custom/stored-extract").and_return(true)
        allow(AdminSetting).to receive(:column_names).and_return(%w[id summarization_model decision_model extraction_model])
        allow(AdminSetting).to receive(:exists?).with(decision_model: "custom/stored-extract").and_return(false)
        allow(AdminSetting).to receive(:exists?).with(summarization_model: "custom/stored-extract").and_return(false)
        allow(AdminSetting).to receive(:exists?).with(extraction_model: "custom/stored-extract").and_return(true)

        route = described_class.lookup("custom/stored-extract")
        expect(route).not_to be_nil
        expect(route.mode).to eq(:extraction)
        expect(route.extraction_model?).to be(true)
        expect(route.supports_reasoning?).to be(false)
      end

      it "resolves cold-cache fallback with :chat mode and supports_reasoning: true when stored in both summarization_model and extraction_model" do
        allow(Llm::OpenRouterModelsService).to receive(:lookup).with("openai/o3-mini").and_return(nil)
        allow(Llm::OpenRouterModelsService).to receive(:lookup_decision_model).with("openai/o3-mini").and_return(nil)
        allow(Llm::OpenRouterModelsService).to receive(:valid_slug?).with("openai/o3-mini").and_return(true)
        allow(AdminSetting).to receive(:stored_model?).with("openai/o3-mini").and_return(true)
        allow(AdminSetting).to receive(:column_names).and_return(%w[id summarization_model decision_model extraction_model])
        allow(AdminSetting).to receive(:exists?).with(decision_model: "openai/o3-mini").and_return(false)
        allow(AdminSetting).to receive(:exists?).with(summarization_model: "openai/o3-mini").and_return(true)
        allow(AdminSetting).to receive(:exists?).with(extraction_model: "openai/o3-mini").and_return(true)

        route = described_class.lookup("openai/o3-mini")
        expect(route).not_to be_nil
        expect(route.mode).to eq(:chat)
        expect(route.decision_model?).to be(false)
        expect(route.extraction_model?).to be(false)
        expect(route.supports_reasoning?).to be(true)
      end
    end

    context "with strict matching guarantees" do
      it "returns nil for unknown model choices" do
        expect(described_class.lookup("gpt-4")).to be_nil
        expect(described_class.lookup("llama-3")).to be_nil
        expect(described_class.lookup("unknown-org/unknown-model")).to be_nil
      end

      it "does not use prefix-based or wildcard matching for Claude" do
        expect(described_class.lookup("claude-")).to be_nil
        expect(described_class.lookup("claude-future-model")).to be_nil
        expect(described_class.lookup("claude-*")).to be_nil
      end

      it "does not use prefix-based or wildcard matching for OpenRouter" do
        expect(described_class.lookup("deepseek/*")).to be_nil
        expect(described_class.lookup("openrouter/*")).to be_nil
        expect(described_class.lookup("deepseek-pro")).to be_nil
      end

      it "returns nil for blank and nil choices" do
        expect(described_class.lookup(nil)).to be_nil
        expect(described_class.lookup("")).to be_nil
        expect(described_class.lookup("   ")).to be_nil
      end
    end
  end

  describe ".fetch" do
    it "returns the route when found" do
      route = described_class.fetch("Deepseek Pro Latest")
      expect(route.provider).to eq(:openrouter)
    end

    it "raises Llm::UnknownRouteError when unmapped or wildcard" do
      expect {
        described_class.fetch("unknown-model-id")
      }.to raise_error(Llm::UnknownRouteError, /unsupported or unknown model choice/i)

      expect {
        described_class.fetch("deepseek/*")
      }.to raise_error(Llm::UnknownRouteError, /unsupported or unknown model choice/i)

      expect {
        described_class.fetch("openrouter/*")
      }.to raise_error(Llm::UnknownRouteError, /unsupported or unknown model choice/i)
    end
  end

  describe ".supports_reasoning?" do
    it "returns true for baseline OpenRouter models" do
      expect(described_class.supports_reasoning?("Opus Latest")).to be(true)
      expect(described_class.supports_reasoning?("Deepseek Pro Latest")).to be(true)
      expect(described_class.supports_reasoning?("OpenRouter Auto")).to be(true)
    end

    it "returns false for Claude models" do
      expect(described_class.supports_reasoning?("claude-haiku-5-5")).to be(false)
      expect(described_class.supports_reasoning?("claude-sonnet-5-5")).to be(false)
      expect(described_class.supports_reasoning?("claude-opus-5-5")).to be(false)
    end

    it "queries reasoning support on dynamic OpenRouter models" do
      allow(Llm::OpenRouterModelsService).to receive(:lookup).with("openai/o3-mini").and_return({
        id: "openai/o3-mini",
        label: "OpenAI: o3-mini",
        supports_reasoning: true
      })
      allow(Llm::OpenRouterModelsService).to receive(:lookup).with("meta-llama/llama-3-8b").and_return({
        id: "meta-llama/llama-3-8b",
        label: "Meta: Llama 3 8B",
        supports_reasoning: false
      })

      expect(described_class.supports_reasoning?("openai/o3-mini")).to be(true)
      expect(described_class.supports_reasoning?("meta-llama/llama-3-8b")).to be(false)
    end

    it "returns false for nil or unknown choices" do
      expect(described_class.supports_reasoning?(nil)).to be(false)
      expect(described_class.supports_reasoning?("")).to be(false)
      expect(described_class.supports_reasoning?("unknown-model")).to be(false)
    end
  end

  describe "ModelRoute destructuring and methods" do
    it "supports array destructuring via to_ary" do
      provider, model = described_class.lookup("OpenRouter Auto")
      expect(provider).to eq(:openrouter)
      expect(model).to eq("openrouter/auto")
    end

    it "supports pattern matching deconstruction" do
      route = described_class.lookup("claude-haiku-5-5")
      case route
      in [provider, api_model]
        expect(provider).to eq(:claude)
        expect(api_model).to eq("claude-haiku-5-5")
      end
    end

    it "defaults supports_reasoning? to false for non-openrouter routes when unspecified" do
      custom_route = described_class::ModelRoute.new(provider: :llamacpp, api_model: "default", label: "Local")
      expect(custom_route.supports_reasoning?).to be(false)
    end

    it "defaults mode to :chat and includes mode in deconstruct_keys" do
      route = described_class::ModelRoute.new(provider: :openrouter, api_model: "test/model", label: "Test")
      expect(route.mode).to eq(:chat)
      expect(route.decision_model?).to be(false)
      expect(route.extraction_model?).to be(false)
      expect(route.deconstruct_keys([:mode, :provider])).to eq(mode: :chat, provider: :openrouter)
    end

    it "returns all keys when deconstruct_keys is called with nil for Ruby pattern matching with rest" do
      route = described_class::ModelRoute.new(
        provider: :openrouter,
        api_model: "scaledown/classify-1",
        label: "ScaleDown Classify Latest",
        mode: :decision
      )

      expect(route.deconstruct_keys(nil)).to eq(
        provider: :openrouter,
        api_model: "scaledown/classify-1",
        label: "ScaleDown Classify Latest",
        supports_reasoning: false,
        mode: :decision
      )

      matched = case route
      in {provider: p, mode: m, **rest}
        [p, m, rest[:api_model]]
      else
        nil
      end

      expect(matched).to eq([:openrouter, :decision, "scaledown/classify-1"])
    end

    it "supports pattern matching with specific keys" do
      route = described_class.lookup("ScaleDown Extract Latest")
      matched = case route
      in {provider: p, mode: m}
        [p, m]
      else
        nil
      end

      expect(matched).to eq([:openrouter, :extraction])
    end

    it "returns an empty hash from deconstruct_keys when keys is an empty array" do
      route = described_class.lookup("ScaleDown Classify Latest")
      expect(route.deconstruct_keys([])).to eq({})
    end

    it "forces supports_reasoning? to false for decision and extraction routes unless explicitly true" do
      decision_route = described_class::ModelRoute.new(provider: :openrouter, api_model: "decider", label: "Decider", mode: :decision)
      expect(decision_route.decision_model?).to be(true)
      expect(decision_route.supports_reasoning?).to be(false)

      extraction_route = described_class::ModelRoute.new(provider: :openrouter, api_model: "extract", label: "Extract", mode: :extraction)
      expect(extraction_route.extraction_model?).to be(true)
      expect(extraction_route.supports_reasoning?).to be(false)

      reasoning_decision_route = described_class::ModelRoute.new(provider: :openrouter, api_model: "decider", label: "Decider", supports_reasoning: true, mode: :decision)
      expect(reasoning_decision_route.supports_reasoning?).to be(true)
    end
  end

  describe ".decision_model?" do
    it "returns true for built-in decision models" do
      expect(described_class.decision_model?("ScaleDown Classify Latest")).to be(true)
      expect(described_class.decision_model?("scaledown/classify-1")).to be(true)
      expect(described_class.decision_model?("Jev Latest")).to be(true)
      expect(described_class.decision_model?("~perplexity/pplx-decider-latest")).to be(true)
    end

    it "returns false for chat models and extraction models" do
      expect(described_class.decision_model?("Opus Latest")).to be(false)
      expect(described_class.decision_model?("claude-haiku-5-5")).to be(false)
      expect(described_class.decision_model?("ScaleDown Extract Latest")).to be(false)
      expect(described_class.decision_model?(nil)).to be(false)
      expect(described_class.decision_model?("unknown")).to be(false)
    end
  end

  describe ".extraction_model?" do
    it "returns true for built-in extraction models" do
      expect(described_class.extraction_model?("ScaleDown Extract Latest")).to be(true)
      expect(described_class.extraction_model?("scaledown/extract")).to be(true)
    end

    it "returns false for decision models and chat models" do
      expect(described_class.extraction_model?("ScaleDown Classify Latest")).to be(false)
      expect(described_class.extraction_model?("Opus Latest")).to be(false)
      expect(described_class.extraction_model?("claude-sonnet-5-5")).to be(false)
      expect(described_class.extraction_model?(nil)).to be(false)
      expect(described_class.extraction_model?("unknown")).to be(false)
    end
  end

  describe "active UI allowlist" do
    it "includes all catalog choices in AdminSetting::SUPPORTED_MODELS" do
      expect(AdminSetting::SUPPORTED_MODELS).to eq([
        "claude-haiku-5-5",
        "claude-sonnet-5-5",
        "claude-opus-5-5",
        "Opus Latest",
        "Sonnet Latest",
        "Haiku Latest",
        "Gemini Argon Latest",
        "Gemini Flash Latest",
        "GLM Latest",
        "Deepseek Pro Latest",
        "Deepseek Flash Latest",
        "OpenRouter Auto"
      ])
    end

    it "does not alter AdminSetting singleton behavior" do
      setting = AdminSetting.singleton
      expect(setting).to be_persisted
      expect(AdminSetting::SUPPORTED_MODELS).to include(setting.summarization_model)
    end
  end
end
