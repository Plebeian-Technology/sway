# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::RouteResolver do
  # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes]]
  let(:setting) do
    AdminSetting.singleton.tap do |s|
      s.update!(
        summarization_model: "claude-haiku-5-5",
        classification_model: "claude-haiku-5-5"
      )
    end
  end

  before do
    setting
  end

  describe ".resolve" do
    context "with OpenRouter model choices" do
      it "resolves Deepseek Pro Latest to OpenRouter under claude environment" do
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(model_choice: "Deepseek Pro Latest")
          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("~deepseek/deepseek-pro-latest")
          expect(route.openrouter?).to be(true)
          expect(route.claude?).to be(false)
          expect(route.llamacpp?).to be(false)
        end
      end

      it "resolves Deepseek Pro Latest to OpenRouter under llamacpp environment" do
        with_app_config(:llm, llm_provider: "llamacpp", llamacpp_model: "local") do
          route = described_class.resolve(model_choice: "Deepseek Pro Latest")
          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("~deepseek/deepseek-pro-latest")
          expect(route.openrouter?).to be(true)
        end
      end

      it "resolves Deepseek Flash Latest to OpenRouter under claude environment" do
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(model_choice: "Deepseek Flash Latest")
          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("~deepseek/deepseek-flash-latest")
          expect(route.openrouter?).to be(true)
        end
      end

      it "resolves Deepseek Flash Latest to OpenRouter under llamacpp environment" do
        with_app_config(:llm, llm_provider: "llamacpp", llamacpp_model: "local") do
          route = described_class.resolve(model_choice: "Deepseek Flash Latest")
          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("~deepseek/deepseek-flash-latest")
          expect(route.openrouter?).to be(true)
        end
      end

      it "resolves OpenRouter Auto to OpenRouter under claude environment" do
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(model_choice: "OpenRouter Auto")
          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("openrouter/auto")
          expect(route.openrouter?).to be(true)
        end
      end

      it "resolves OpenRouter Auto to OpenRouter under llamacpp environment" do
        with_app_config(:llm, llm_provider: "llamacpp", llamacpp_model: "local") do
          route = described_class.resolve(model_choice: "OpenRouter Auto")
          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("openrouter/auto")
          expect(route.openrouter?).to be(true)
        end
      end
    end

    context "with existing Claude model choices" do
      it "resolves claude-haiku-5-5 to claude when llm_provider is claude" do
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(model_choice: "claude-haiku-5-5")
          expect(route.provider).to eq(:claude)
          expect(route.api_model).to eq("claude-haiku-5-5")
          expect(route.claude?).to be(true)
          expect(route.openrouter?).to be(false)
        end
      end

      it "resolves claude-haiku-5-5 to llamacpp when llm_provider is llamacpp" do
        with_app_config(:llm, llm_provider: "llamacpp", llamacpp_model: "custom-local") do
          route = described_class.resolve(model_choice: "claude-haiku-5-5")
          expect(route.provider).to eq(:llamacpp)
          expect(route.api_model).to eq("custom-local")
          expect(route.llamacpp?).to be(true)
          expect(route.claude?).to be(false)
        end
      end

      it "resolves claude-sonnet-5 to claude in production" do
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(model_choice: "claude-sonnet-5-5")
          expect(route.provider).to eq(:claude)
          expect(route.api_model).to eq("claude-sonnet-5-5")
        end
      end

      it "resolves claude-sonnet-5 to llamacpp in dev" do
        with_app_config(:llm, llm_provider: "llamacpp", llamacpp_model: "local") do
          route = described_class.resolve(model_choice: "claude-sonnet-5-5")
          expect(route.provider).to eq(:llamacpp)
          expect(route.api_model).to eq("local")
        end
      end

      it "resolves claude-opus-5-5 to claude in production" do
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(model_choice: "claude-opus-5-5")
          expect(route.provider).to eq(:claude)
          expect(route.api_model).to eq("claude-opus-5-5")
        end
      end
    end

    context "with purpose handling" do
      it "reads summarization_model for purpose: :summary" do
        setting.update!(summarization_model: "claude-sonnet-5-5")
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(purpose: :summary)
          expect(route.provider).to eq(:claude)
          expect(route.api_model).to eq("claude-sonnet-5-5")
        end
      end

      it "reads classification_model for purpose: :classification" do
        setting.update!(classification_model: "claude-opus-5-5")
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(purpose: :classification)
          expect(route.provider).to eq(:claude)
          expect(route.api_model).to eq("claude-opus-5-5")
        end
      end

      it "accepts string representation of purpose" do
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(purpose: "summary")
          expect(route.api_model).to eq(setting.summarization_model)
        end
      end

      it "raises ArgumentError for unknown purpose" do
        expect {
          described_class.resolve(purpose: :invalid_purpose)
        }.to raise_error(ArgumentError, /unknown purpose/i)
      end
    end

    context "with per-run summary overrides" do
      it "uses valid per-run override present in active_models" do
        setting.update!(summarization_model: "claude-haiku-5-5")
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            purpose: :summary,
            per_run_override: "claude-sonnet-5-5",
            active_models: ["claude-haiku-5-5", "claude-sonnet-5-5"]
          )
          expect(route.api_model).to eq("claude-sonnet-5-5")
        end
      end

      it "authorizes OpenRouter candidate override when locally provided in active_models" do
        setting.update!(summarization_model: "claude-haiku-5-5")
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            purpose: :summary,
            per_run_override: "Deepseek Pro Latest",
            active_models: ["claude-haiku-5-5", "Deepseek Pro Latest"]
          )
          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("~deepseek/deepseek-pro-latest")
        end
      end

      it "authorizes dynamic OpenRouter candidate override when present in AdminSetting.offered_models" do
        allow(Llm::OpenRouterModelsService).to receive(:lookup).with("openai/gpt-4o").and_return(
          {id: "openai/gpt-4o", label: "OpenAI: GPT-4o", supports_reasoning: false}
        )
        setting.update!(offered_models: AdminSetting::SUPPORTED_MODELS + ["openai/gpt-4o"])
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            purpose: :summary,
            per_run_override: "openai/gpt-4o"
          )
          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("openai/gpt-4o")
        end
      end

      it "resolves Gemini Argon Latest per-run override to OpenRouter route" do
        setting.update!(summarization_model: "claude-haiku-5-5")
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            purpose: :summary,
            per_run_override: "Gemini Argon Latest"
          )
          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("google/gemini-4-argon")
        end
      end

      it "resolves Opus Latest per-run override to OpenRouter route" do
        setting.update!(summarization_model: "claude-haiku-5-5")
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            purpose: :summary,
            per_run_override: "Opus Latest"
          )
          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("~anthropic/claude-opus-latest")
        end
      end

      it "rejects dynamic candidate override absent from AdminSetting.offered_models and falls back to stored default" do
        setting.update!(summarization_model: "claude-haiku-5-5")
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            purpose: :summary,
            per_run_override: "openai/gpt-4o"
          )
          expect(route.provider).to eq(:claude)
          expect(route.api_model).to eq("claude-haiku-5-5")
        end
      end

      it "rejects inactive candidate override absent from active_models and falls back to stored default" do
        setting.update!(summarization_model: "claude-haiku-5-5")
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            purpose: :summary,
            per_run_override: "unsupported-model"
          )
          expect(route.provider).to eq(:claude)
          expect(route.api_model).to eq("claude-haiku-5-5")
        end
      end

      it "falls back to stored default when queued override is unsupported or arbitrary" do
        setting.update!(summarization_model: "claude-sonnet-5-5")
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            purpose: :summary,
            per_run_override: "unsupported-model-id"
          )
          expect(route.provider).to eq(:claude)
          expect(route.api_model).to eq("claude-sonnet-5-5")
        end
      end

      it "ignores per-run override when purpose is :classification" do
        setting.update!(classification_model: "claude-haiku-5-5")
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            purpose: :classification,
            per_run_override: "Deepseek Pro Latest",
            active_models: ["claude-haiku-5-5", "Deepseek Pro Latest"]
          )
          expect(route.provider).to eq(:claude)
          expect(route.api_model).to eq("claude-haiku-5-5")
        end
      end
    end

    context "with stored retired Claude models" do
      before do
        # Bypass validation to simulate legacy stored database row
        setting.update_columns(summarization_model: "claude-sonnet-4-6")
      end

      it "resolves stored retired Claude default in production" do
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(purpose: :summary)
          expect(route.provider).to eq(:claude)
          expect(route.api_model).to eq("claude-sonnet-4-6")
        end
      end

      it "resolves stored retired Claude default in development" do
        with_app_config(:llm, llm_provider: "llamacpp", llamacpp_model: "local") do
          route = described_class.resolve(purpose: :summary)
          expect(route.provider).to eq(:llamacpp)
          expect(route.api_model).to eq("local")
        end
      end

      it "falls back to stored retired default when queued override is unoffered" do
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            purpose: :summary,
            per_run_override: "unoffered-or-retired-id"
          )
          expect(route.provider).to eq(:claude)
          expect(route.api_model).to eq("claude-sonnet-4-6")
        end
      end

      it "rejects retired model passed as per-run override when absent from active_models" do
        setting.update_columns(summarization_model: "claude-haiku-5-5")
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            purpose: :summary,
            per_run_override: "claude-sonnet-4-6"
          )
          # Falls back to stored active default
          expect(route.api_model).to eq("claude-haiku-5-5")
        end
      end
    end

    context "with blank setting fallbacks" do
      it "uses fallback_model when classification_model is blank" do
        setting.update_columns(classification_model: "")
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            purpose: :classification,
            fallback_model: "claude-haiku-5-5"
          )
          expect(route.provider).to eq(:claude)
          expect(route.api_model).to eq("claude-haiku-5-5")
        end
      end
    end

    context "with unknown route and error handling" do
      it "raises Llm::UnknownRouteError for completely unknown model choice" do
        expect {
          described_class.resolve(model_choice: "unknown-unregistered-model")
        }.to raise_error(Llm::UnknownRouteError, /unsupported or unknown model choice/i)
      end

      it "raises Llm::UnknownRouteError when stored setting is unknown" do
        setting.update_columns(summarization_model: "invalid-database-string")
        expect {
          described_class.resolve(purpose: :summary)
        }.to raise_error(Llm::UnknownRouteError, /unsupported or unknown model choice/i)
      end

      it "raises Llm::UnknownRouteError when llm_provider is unsupported for Claude model" do
        with_app_config(:llm, llm_provider: "unsupported_provider") do
          expect {
            described_class.resolve(model_choice: "claude-haiku-5-5")
          }.to raise_error(Llm::UnknownRouteError, /unsupported environment llm_provider/i)
        end
      end
    end

    context "with Route destructuring and convenience methods" do
      it "supports array destructuring via to_ary" do
        with_app_config(:llm, llm_provider: "claude") do
          provider, api_model = described_class.resolve(model_choice: "Deepseek Flash Latest")
          expect(provider).to eq(:openrouter)
          expect(api_model).to eq("~deepseek/deepseek-flash-latest")
        end
      end

      it "supports pattern matching" do
        with_app_config(:llm, llm_provider: "claude") do
          case described_class.resolve(model_choice: "OpenRouter Auto")
          in [provider, api_model]
            expect(provider).to eq(:openrouter)
            expect(api_model).to eq("openrouter/auto")
          end
        end
      end
    end

    context "with reasoning_effort resolution" do
      it "returns per-run reasoning_effort when model supports reasoning" do
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            model_choice: "Deepseek Flash Latest",
            reasoning_effort: "high"
          )
          expect(route.reasoning_effort).to eq("high")
        end
      end

      it "falls back to standing AdminSetting summarization_reasoning_effort for purpose: :summary" do
        setting.update_columns(summarization_reasoning_effort: "medium")
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            model_choice: "Deepseek Flash Latest",
            purpose: :summary
          )
          expect(route.reasoning_effort).to eq("medium")
        end
      end

      it "falls back to standing AdminSetting classification_reasoning_effort for purpose: :classification" do
        setting.update_columns(classification_reasoning_effort: "low")
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            model_choice: "Deepseek Flash Latest",
            purpose: :classification
          )
          expect(route.reasoning_effort).to eq("low")
        end
      end

      it "returns nil reasoning_effort when model does not support reasoning" do
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            model_choice: "claude-haiku-5-5",
            reasoning_effort: "high"
          )
          expect(route.reasoning_effort).to be_nil
        end
      end

      it "discards per-run reasoning_effort when per-run model override is rejected" do
        setting.update_columns(
          summarization_model: "Opus Latest",
          summarization_reasoning_effort: "low"
        )
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            purpose: :summary,
            per_run_override: "unoffered-or-retired-model",
            reasoning_effort: "high"
          )
          expect(route.api_model).to eq("~anthropic/claude-opus-latest")
          expect(route.reasoning_effort).to eq("low")
        end
      end

      it "does not leak standing summarization_reasoning_effort onto a different per-run model override when reasoning_effort is nil" do
        setting.update_columns(
          summarization_model: "Opus Latest",
          summarization_reasoning_effort: "high"
        )
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            purpose: :summary,
            per_run_override: "Gemini Argon Latest",
            reasoning_effort: nil
          )
          expect(route.api_model).to eq("google/gemini-4-argon")
          expect(route.reasoning_effort).to be_nil
        end
      end

      it "resolves reasoning_effort: 'default' to nil even when standing summarization_reasoning_effort is set" do
        setting.update_columns(
          summarization_model: "Opus Latest",
          summarization_reasoning_effort: "high"
        )
        with_app_config(:llm, llm_provider: "claude") do
          route = described_class.resolve(
            purpose: :summary,
            per_run_override: "Opus Latest",
            reasoning_effort: "default"
          )
          expect(route.api_model).to eq("~anthropic/claude-opus-latest")
          expect(route.reasoning_effort).to be_nil
        end
      end
    end

    context "with specialized model purposes" do
      describe "Route struct mode and predicates" do
        it "defaults mode to :chat when omitted or nil" do
          route = described_class::Route.new(provider: :openrouter, api_model: "openrouter/auto")
          expect(route.mode).to eq(:chat)
          expect(route.decision_model?).to be(false)
          expect(route.extraction_model?).to be(false)
        end

        it "supports decision routes with mode: :decision" do
          route = described_class::Route.new(
            provider: :openrouter,
            api_model: "scaledown/classify-1",
            mode: :decision
          )
          expect(route.mode).to eq(:decision)
          expect(route.decision_model?).to be(true)
          expect(route.extraction_model?).to be(false)
        end

        it "supports extraction routes with mode: :extraction" do
          route = described_class::Route.new(
            provider: :openrouter,
            api_model: "scaledown/extract",
            mode: :extraction
          )
          expect(route.mode).to eq(:extraction)
          expect(route.decision_model?).to be(false)
          expect(route.extraction_model?).to be(true)
        end

        it "preserves to_ary and deconstruct as two-element arrays while exposing mode in deconstruct_keys" do
          route = described_class::Route.new(
            provider: :openrouter,
            api_model: "scaledown/classify-1",
            mode: :decision
          )
          expect(route.to_ary).to eq([:openrouter, "scaledown/classify-1"])
          expect(route.deconstruct).to eq([:openrouter, "scaledown/classify-1"])
          expect(route.deconstruct_keys([:provider, :mode])).to eq({provider: :openrouter, mode: :decision})
          expect(route.deconstruct_keys(nil)).to eq({
            provider: :openrouter,
            api_model: "scaledown/classify-1",
            reasoning_effort: nil,
            mode: :decision
          })

          matched = false
          case route
          in {provider: p, mode: m, **rest}
            expect(p).to eq(:openrouter)
            expect(m).to eq(:decision)
            expect(rest[:api_model]).to eq("scaledown/classify-1")
            matched = true
          end
          expect(matched).to be(true)
        end
      end

      describe "purpose: :decision resolution" do
        it "resolves setting.decision_model to OpenRouter decision route" do
          setting.update_columns(decision_model: "ScaleDown Classify Latest")
          route = described_class.resolve(purpose: :decision)

          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("scaledown/classify-1")
          expect(route.mode).to eq(:decision)
          expect(route.decision_model?).to be(true)
          expect(route.extraction_model?).to be(false)
          expect(route.reasoning_effort).to be_nil
        end

        it "accepts string representations 'decision' and 'decisions'" do
          setting.update_columns(decision_model: "Jev Latest")

          route_singular = described_class.resolve(purpose: "decision")
          expect(route_singular.api_model).to eq("~typesafe/jev-latest")
          expect(route_singular.mode).to eq(:decision)

          route_plural = described_class.resolve(purpose: "decisions")
          expect(route_plural.api_model).to eq("~typesafe/jev-latest")
          expect(route_plural.mode).to eq(:decision)
        end

        it "falls back to blank_fallback or default decision model when stored column is blank" do
          setting.update_columns(decision_model: "")

          route_with_blank_fallback = described_class.resolve(
            purpose: :decision,
            blank_fallback: "Perplexity Decider Latest"
          )
          expect(route_with_blank_fallback.api_model).to eq("~perplexity/pplx-decider-latest")

          route_with_default = described_class.resolve(purpose: :decision)
          expect(route_with_default.api_model).to eq("scaledown/classify-1")
        end
      end

      describe "purpose: :extraction resolution" do
        it "resolves setting.extraction_model to OpenRouter extraction route" do
          setting.update_columns(extraction_model: "ScaleDown Extract Latest")
          route = described_class.resolve(purpose: :extraction)

          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("scaledown/extract")
          expect(route.mode).to eq(:extraction)
          expect(route.decision_model?).to be(false)
          expect(route.extraction_model?).to be(true)
          expect(route.reasoning_effort).to be_nil
        end

        it "accepts string representations 'extraction' and 'extract'" do
          route_full = described_class.resolve(purpose: "extraction")
          expect(route_full.api_model).to eq("scaledown/extract")
          expect(route_full.mode).to eq(:extraction)

          route_short = described_class.resolve(purpose: "extract")
          expect(route_short.api_model).to eq("scaledown/extract")
          expect(route_short.mode).to eq(:extraction)
        end

        it "falls back to blank_fallback or default extraction model when stored column is blank" do
          setting.update_columns(extraction_model: "")

          route_with_fallback = described_class.resolve(
            purpose: :extraction,
            blank_fallback: "ScaleDown Extract Latest"
          )
          expect(route_with_fallback.api_model).to eq("scaledown/extract")

          route_default = described_class.resolve(purpose: :extraction)
          expect(route_default.api_model).to eq("scaledown/extract")
        end
      end

      describe "classification routing to decision models" do
        it "resolves with mode: :decision and decision_model?: true when classification_model is a decision model" do
          setting.update_columns(classification_model: "ScaleDown Classify Latest")
          route = described_class.resolve(purpose: :classification)

          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("scaledown/classify-1")
          expect(route.mode).to eq(:decision)
          expect(route.decision_model?).to be(true)
          expect(route.extraction_model?).to be(false)
        end
      end

      describe "lazy allowlist evaluation and specialized purpose resolution" do
        it "does not call AdminSetting.offered_models or AdminSetting.singleton when resolving specialized purposes with custom setting" do
          custom_setting = instance_double(
            AdminSetting,
            decision_model: "ScaleDown Classify Latest",
            extraction_model: "ScaleDown Extract Latest"
          )
          expect(AdminSetting).not_to receive(:offered_models)
          expect(AdminSetting).not_to receive(:singleton)

          route_decision = described_class.resolve(purpose: :decision, setting: custom_setting)
          expect(route_decision.api_model).to eq("scaledown/classify-1")

          route_extraction = described_class.resolve(purpose: :extraction, setting: custom_setting)
          expect(route_extraction.api_model).to eq("scaledown/extract")
        end

        it "checks setting.offered_models_list when purpose: :summary with override and rejects decision model overrides" do
          custom_setting = instance_double(
            AdminSetting,
            summarization_model: "claude-haiku-5-5",
            offered_models_list: ["claude-haiku-5-5", "claude-sonnet-4-6"]
          )
          expect(custom_setting).to receive(:offered_models_list).and_return(["claude-haiku-5-5", "claude-sonnet-4-6"])

          with_app_config(:llm, llm_provider: "claude") do
            route = described_class.resolve(
              purpose: :summary,
              setting: custom_setting,
              per_run_override: "ScaleDown Classify Latest"
            )
            expect(route.api_model).to eq("claude-haiku-5-5")
          end
        end
      end
    end
  end

  describe "Adversarial & Empirical Challenge" do
    let(:setting) do
      AdminSetting.singleton.tap do |s|
        s.update_columns(
          summarization_model: "claude-haiku-5-5",
          classification_model: "claude-haiku-5-5",
          decision_model: "ScaleDown Classify Latest",
          extraction_model: "ScaleDown Extract Latest",
          summarization_reasoning_effort: "high",
          classification_reasoning_effort: "high"
        )
      end
    end

    before do
      setting
    end

    describe "Suite 1: Route struct integrity and Ruby 3 pattern matching" do
      it "matches array pattern deconstruction to [provider, api_model]" do
        route = Llm::RouteResolver::Route.new(
          provider: :openrouter,
          api_model: "scaledown/classify-1",
          reasoning_effort: nil,
          mode: :decision
        )

        matched = false
        case route
        in [provider, api_model]
          expect(provider).to eq(:openrouter)
          expect(api_model).to eq("scaledown/classify-1")
          matched = true
        else
          matched = false
        end
        expect(matched).to be(true)
      end

      it "matches array pattern with pin operator and rest values" do
        route = Llm::RouteResolver::Route.new(
          provider: :openrouter,
          api_model: "scaledown/extract",
          reasoning_effort: nil,
          mode: :extraction
        )

        matched = false
        case route
        in [:openrouter, api_model]
          expect(api_model).to eq("scaledown/extract")
          matched = true
        else
          matched = false
        end
        expect(matched).to be(true)
      end

      it "matches hash pattern deconstruction with specific keys including mode" do
        route = Llm::RouteResolver::Route.new(
          provider: :openrouter,
          api_model: "scaledown/classify-1",
          reasoning_effort: nil,
          mode: :decision
        )

        matched = false
        case route
        in {provider: p, api_model: m, mode: md}
          expect(p).to eq(:openrouter)
          expect(m).to eq("scaledown/classify-1")
          expect(md).to eq(:decision)
          matched = true
        else
          matched = false
        end
        expect(matched).to be(true)
      end

      it "matches subset hash patterns without requiring all keys" do
        route = Llm::RouteResolver::Route.new(
          provider: :openrouter,
          api_model: "scaledown/classify-1",
          reasoning_effort: nil,
          mode: :decision
        )

        matched_mode = false
        case route
        in {mode: md}
          expect(md).to eq(:decision)
          matched_mode = true
        end
        expect(matched_mode).to be(true)

        matched_api_model = false
        case route
        in {api_model: m}
          expect(m).to eq("scaledown/classify-1")
          matched_api_model = true
        end
        expect(matched_api_model).to be(true)
      end

      it "verifies deconstruct_keys behavior with explicit keys array" do
        route = Llm::RouteResolver::Route.new(
          provider: :openrouter,
          api_model: "scaledown/classify-1",
          reasoning_effort: nil,
          mode: :decision
        )

        expect(route.deconstruct_keys([:provider, :mode])).to eq(
          {provider: :openrouter, mode: :decision}
        )
        expect(route.deconstruct_keys([:api_model, :reasoning_effort])).to eq(
          {api_model: "scaledown/classify-1", reasoning_effort: nil}
        )
      end

      it "preserves to_ary as a 2-element array matching [provider, api_model] for multiple assignment" do
        route = Llm::RouteResolver::Route.new(
          provider: :openrouter,
          api_model: "scaledown/classify-1",
          reasoning_effort: nil,
          mode: :decision
        )

        provider, api_model = route
        expect(provider).to eq(:openrouter)
        expect(api_model).to eq("scaledown/classify-1")

        expect(route.to_ary).to eq([:openrouter, "scaledown/classify-1"])
        expect(route.to_ary.size).to eq(2)
      end

      it "defaults mode to :chat when omitted or nil and sets predicates accordingly" do
        route_omitted = Llm::RouteResolver::Route.new(
          provider: :openrouter,
          api_model: "openrouter/auto"
        )
        expect(route_omitted.mode).to eq(:chat)
        expect(route_omitted.decision_model?).to be(false)
        expect(route_omitted.extraction_model?).to be(false)

        route_nil = Llm::RouteResolver::Route.new(
          provider: :openrouter,
          api_model: "openrouter/auto",
          reasoning_effort: nil,
          mode: nil
        )
        expect(route_nil.mode).to eq(:chat)
        expect(route_nil.decision_model?).to be(false)
        expect(route_nil.extraction_model?).to be(false)
      end

      it "correctly reports predicates for decision and extraction modes" do
        decision_route = Llm::RouteResolver::Route.new(
          provider: :openrouter,
          api_model: "scaledown/classify-1",
          mode: :decision
        )
        expect(decision_route.mode).to eq(:decision)
        expect(decision_route.decision_model?).to be(true)
        expect(decision_route.extraction_model?).to be(false)
        expect(decision_route.openrouter?).to be(true)
        expect(decision_route.claude?).to be(false)
        expect(decision_route.llamacpp?).to be(false)

        extraction_route = Llm::RouteResolver::Route.new(
          provider: :openrouter,
          api_model: "scaledown/extract",
          mode: :extraction
        )
        expect(extraction_route.mode).to eq(:extraction)
        expect(extraction_route.decision_model?).to be(false)
        expect(extraction_route.extraction_model?).to be(true)
        expect(extraction_route.openrouter?).to be(true)
        expect(extraction_route.claude?).to be(false)
        expect(extraction_route.llamacpp?).to be(false)
      end
    end

    describe "Suite 2: Purpose normalization and edge case parsing" do
      it "normalizes symbol and string aliases for all four purposes" do
        purpose_expectations = {
          :summary => :summary,
          :summarization => :summary,
          "summary" => :summary,
          "summarization" => :summary,
          :classification => :classification,
          "classification" => :classification,
          :decision => :decision,
          :decisions => :decision,
          "decision" => :decision,
          "decisions" => :decision,
          :extraction => :extraction,
          :extract => :extraction,
          "extraction" => :extraction,
          "extract" => :extraction
        }

        purpose_expectations.each do |input_purpose, expected_purpose|
          route = Llm::RouteResolver.resolve(purpose: input_purpose)
          case expected_purpose
          when :decision
            expect(route.mode).to eq(:decision)
            expect(route.decision_model?).to be(true)
          when :extraction
            expect(route.mode).to eq(:extraction)
            expect(route.extraction_model?).to be(true)
          when :summary, :classification
            expect(route.mode).to eq(:chat)
            expect(route.decision_model?).to be(false)
            expect(route.extraction_model?).to be(false)
          end
        end
      end

      it "handles whitespace surrounding purpose strings" do
        whitespace_cases = [
          "  decision  ",
          "\tdecisions\n",
          " extraction ",
          "\rextract\t",
          "  summary  ",
          "   classification\n"
        ]

        whitespace_cases.each do |input_purpose|
          expect {
            Llm::RouteResolver.resolve(purpose: input_purpose)
          }.not_to raise_error
        end
      end

      it "rejects invalid, unknown, empty, or nil purposes with ArgumentError" do
        invalid_inputs = [
          :invalid,
          :extractions,
          :summaries,
          "",
          "   ",
          nil,
          123,
          true,
          [],
          {},
          "DECISION",
          "Decisions",
          "EXTRACTION",
          "Extract",
          :DECISION
        ]

        invalid_inputs.each do |invalid_purpose|
          expect {
            Llm::RouteResolver.send(:resolve, purpose: invalid_purpose)
          }.to raise_error(ArgumentError, /unknown purpose/i)
        end
      end
    end

    describe "Suite 3: Fallback resilience and degraded configuration handling" do
      context "with purpose: :decision" do
        it "falls back to default decision model when stored decision_model is nil" do
          mock_setting = instance_double(AdminSetting, decision_model: nil)
          route = Llm::RouteResolver.resolve(purpose: :decision, setting: mock_setting)

          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("scaledown/classify-1")
          expect(route.mode).to eq(:decision)
          expect(route.decision_model?).to be(true)
        end

        it "falls back to default decision model when stored decision_model is an empty string" do
          mock_setting = instance_double(AdminSetting, decision_model: "")
          route = Llm::RouteResolver.resolve(purpose: :decision, setting: mock_setting)

          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("scaledown/classify-1")
          expect(route.mode).to eq(:decision)
        end

        it "falls back to default decision model when stored decision_model is pure whitespace" do
          mock_setting = instance_double(AdminSetting, decision_model: "   \t\n  ")
          route = Llm::RouteResolver.resolve(purpose: :decision, setting: mock_setting)

          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("scaledown/classify-1")
          expect(route.mode).to eq(:decision)
        end

        it "gracefully handles setting object lacking decision_model method (duck-typing resilience)" do
          old_setting_double = Object.new
          route = Llm::RouteResolver.send(:resolve, purpose: :decision, setting: old_setting_double)

          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("scaledown/classify-1")
          expect(route.mode).to eq(:decision)
        end

        it "prefers effective_fallback over default_fallback when stored decision_model is blank" do
          mock_setting = instance_double(AdminSetting, decision_model: nil)
          route = Llm::RouteResolver.resolve(
            purpose: :decision,
            setting: mock_setting,
            fallback_model: "Perplexity Decider Latest"
          )

          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("~perplexity/pplx-decider-latest")
          expect(route.mode).to eq(:decision)
        end

        it "accepts blank_fallback or fallback arguments when stored decision_model is blank" do
          mock_setting = instance_double(AdminSetting, decision_model: "")

          route_blank = Llm::RouteResolver.resolve(
            purpose: :decision,
            setting: mock_setting,
            blank_fallback: "Jev Latest"
          )
          expect(route_blank.api_model).to eq("~typesafe/jev-latest")

          route_fallback = Llm::RouteResolver.resolve(
            purpose: :decision,
            setting: mock_setting,
            fallback: "Perplexity Decider Flash Latest"
          )
          expect(route_fallback.api_model).to eq("~perplexity/pplx-decider-flash-latest")
        end

        it "raises UnknownRouteError when stored decision_model is an unknown string and no fallback is given" do
          mock_setting = instance_double(AdminSetting, decision_model: "nonexistent-decision-model")
          expect {
            Llm::RouteResolver.resolve(purpose: :decision, setting: mock_setting)
          }.to raise_error(Llm::UnknownRouteError, /unsupported or unknown model choice/i)
        end
      end

      context "with purpose: :extraction" do
        it "falls back to default extraction model when stored extraction_model is nil" do
          mock_setting = instance_double(AdminSetting, extraction_model: nil)
          route = Llm::RouteResolver.resolve(purpose: :extraction, setting: mock_setting)

          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("scaledown/extract")
          expect(route.mode).to eq(:extraction)
          expect(route.extraction_model?).to be(true)
        end

        it "falls back to default extraction model when stored extraction_model is an empty string" do
          mock_setting = instance_double(AdminSetting, extraction_model: "")
          route = Llm::RouteResolver.resolve(purpose: :extraction, setting: mock_setting)

          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("scaledown/extract")
          expect(route.mode).to eq(:extraction)
        end

        it "falls back to default extraction model when stored extraction_model is pure whitespace" do
          mock_setting = instance_double(AdminSetting, extraction_model: "   \t\n  ")
          route = Llm::RouteResolver.resolve(purpose: :extraction, setting: mock_setting)

          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("scaledown/extract")
          expect(route.mode).to eq(:extraction)
        end

        it "gracefully handles setting object lacking extraction_model method" do
          old_setting_double = Object.new
          route = Llm::RouteResolver.send(:resolve, purpose: :extraction, setting: old_setting_double)

          expect(route.provider).to eq(:openrouter)
          expect(route.api_model).to eq("scaledown/extract")
          expect(route.mode).to eq(:extraction)
        end

        it "raises UnknownRouteError when stored extraction_model is an unknown string" do
          mock_setting = instance_double(AdminSetting, extraction_model: "nonexistent-extract-model")
          expect {
            Llm::RouteResolver.resolve(purpose: :extraction, setting: mock_setting)
          }.to raise_error(Llm::UnknownRouteError, /unsupported or unknown model choice/i)
        end
      end
    end

    describe "Suite 4: Reasoning effort invariant across decision and extraction models" do
      it "strictly produces nil reasoning_effort for built-in decision models regardless of passed reasoning_effort" do
        decision_models = [
          "ScaleDown Classify Latest",
          "Jev Latest",
          "Perplexity Decider Latest",
          "Perplexity Decider Flash Latest"
        ]

        efforts_to_test = ["high", "medium", "low", "none", "default", "", "   ", nil]

        decision_models.each do |model_name|
          setting.update_columns(decision_model: model_name)

          efforts_to_test.each do |effort|
            route = Llm::RouteResolver.resolve(
              purpose: :decision,
              reasoning_effort: effort
            )
            expect(route.reasoning_effort).to be_nil, "Expected reasoning_effort to be nil for #{model_name} with effort=#{effort.inspect}"
          end
        end
      end

      it "strictly produces nil reasoning_effort for extraction model regardless of passed reasoning_effort" do
        efforts_to_test = ["high", "medium", "low", "none", "default", "", "   ", nil]

        efforts_to_test.each do |effort|
          route = Llm::RouteResolver.resolve(
            purpose: :extraction,
            reasoning_effort: effort
          )
          expect(route.reasoning_effort).to be_nil, "Expected reasoning_effort to be nil for extraction model with effort=#{effort.inspect}"
        end
      end

      it "strictly produces nil reasoning_effort for decision routes even when AdminSetting standing reasoning effort is set" do
        setting.update_columns(
          summarization_reasoning_effort: "high",
          classification_reasoning_effort: "high"
        )

        decision_route = Llm::RouteResolver.resolve(purpose: :decision)
        expect(decision_route.reasoning_effort).to be_nil

        extraction_route = Llm::RouteResolver.resolve(purpose: :extraction)
        expect(extraction_route.reasoning_effort).to be_nil
      end

      it "strictly produces nil reasoning_effort when a decision model is chosen for classification purpose" do
        setting.update_columns(classification_model: "ScaleDown Classify Latest")

        ["high", "low", nil].each do |effort|
          route = Llm::RouteResolver.resolve(
            purpose: :classification,
            reasoning_effort: effort
          )
          expect(route.decision_model?).to be(true)
          expect(route.reasoning_effort).to be_nil
        end
      end
    end

    describe "Suite 5: Multi-threaded resolution concurrency and race-free execution" do
      it "resolves routes across 50 concurrent threads without race conditions or state corruption" do
        thread_count = 50
        iterations_per_thread = 20

        errors = []
        results = Array.new(thread_count) { [] }

        threads = Array.new(thread_count) do |thread_idx|
          Thread.new do
            iterations_per_thread.times do |iter|
              purpose = case iter % 4
              when 0 then :decision
              when 1 then :extraction
              when 2 then :summary
              else :classification
              end

              route = Llm::RouteResolver.resolve(purpose: purpose, setting: setting)

              case purpose
              when :decision
                unless route.provider == :openrouter && route.mode == :decision && route.decision_model? && route.reasoning_effort.nil?
                  errors << "Thread #{thread_idx} iter #{iter}: unexpected decision route: #{route.inspect}"
                end
              when :extraction
                unless route.provider == :openrouter && route.mode == :extraction && route.extraction_model? && route.reasoning_effort.nil?
                  errors << "Thread #{thread_idx} iter #{iter}: unexpected extraction route: #{route.inspect}"
                end
              when :summary, :classification
                unless route.mode == :chat && !route.decision_model? && !route.extraction_model?
                  errors << "Thread #{thread_idx} iter #{iter}: unexpected chat route: #{route.inspect}"
                end
              end

              results[thread_idx] << route.mode
            rescue => e
              errors << "Thread #{thread_idx} raised #{e.class}: #{e.message}"
            end
          end
        end

        threads.each(&:join)

        expect(errors).to be_empty
        expect(results.flatten.size).to eq(thread_count * iterations_per_thread)
      end

      it "resolves concurrent requests with explicit per-thread setting instances" do
        thread_count = 20
        errors = []

        threads = Array.new(thread_count) do |idx|
          Thread.new do
            thread_setting = if idx.even?
              instance_double(AdminSetting, decision_model: "Jev Latest")
            else
              instance_double(AdminSetting, decision_model: "Perplexity Decider Latest")
            end

            route = Llm::RouteResolver.resolve(purpose: :decision, setting: thread_setting)
            expected_api_model = idx.even? ? "~typesafe/jev-latest" : "~perplexity/pplx-decider-latest"

            if route.api_model != expected_api_model || route.mode != :decision
              errors << "Thread #{idx}: got #{route.api_model}, expected #{expected_api_model}"
            end
          rescue => e
            errors << "Thread #{idx} error: #{e.message}"
          end
        end

        threads.each(&:join)
        expect(errors).to be_empty
      end
    end

    describe "Suite 6: Model choice override vs purpose semantics" do
      it "allows explicit model_choice to override default purpose model" do
        route = Llm::RouteResolver.resolve(
          purpose: :decision,
          model_choice: "Perplexity Decider Flash Latest"
        )

        expect(route.provider).to eq(:openrouter)
        expect(route.api_model).to eq("~perplexity/pplx-decider-flash-latest")
        expect(route.mode).to eq(:decision)
        expect(route.decision_model?).to be(true)
      end

      it "inherits mode from catalog when explicit model_choice is passed" do
        decision_route = Llm::RouteResolver.resolve(
          model_choice: "ScaleDown Classify Latest"
        )
        expect(decision_route.mode).to eq(:decision)
        expect(decision_route.decision_model?).to be(true)

        extraction_route = Llm::RouteResolver.resolve(
          model_choice: "ScaleDown Extract Latest"
        )
        expect(extraction_route.mode).to eq(:extraction)
        expect(extraction_route.extraction_model?).to be(true)

        chat_route = Llm::RouteResolver.resolve(
          model_choice: "claude-haiku-5-5"
        )
        expect(chat_route.mode).to eq(:chat)
        expect(chat_route.decision_model?).to be(false)
        expect(chat_route.extraction_model?).to be(false)
      end
    end
  end
end
