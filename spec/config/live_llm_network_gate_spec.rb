# frozen_string_literal: true

require "rails_helper"

# @lat: [[verification-gates#RSpec runtime contracts]]
RSpec.describe "live LLM network gate" do
  let(:count_tokens_url) { "https://api.anthropic.com/v1/messages/count_tokens" }

  describe CachePrefixTokenizer do
    it "issues no request to api.anthropic.com when only the API key is set" do
      stub = stub_request(:post, count_tokens_url)
        .to_return(
          status: 200,
          body: {input_tokens: 4242}.to_json,
          headers: {"Content-Type" => "application/json"}
        )

      result = with_env("ANTHROPIC_API_KEY" => "sk-ant-not-a-real-key", "RUN_LIVE_LLM_TESTS" => nil) do
        described_class.count("x" * 4000)
      end

      expect(stub).not_to have_been_requested
      expect(result).to be_nil
    end

    it "makes the count_tokens call once BOTH gates are set" do
      stub = stub_request(:post, count_tokens_url)
        .to_return(
          status: 200,
          body: {input_tokens: 4242}.to_json,
          headers: {"Content-Type" => "application/json"}
        )

      result = with_env("ANTHROPIC_API_KEY" => "sk-ant-not-a-real-key", "RUN_LIVE_LLM_TESTS" => "1") do
        described_class.count("x" * 4000)
      end

      expect(stub).to have_been_requested
      expect(result).to eq(4242)
    end

    # The Anthropic SDK waits 600 seconds by default. A helper called from an
    # ordinary spec must not be able to stall the suite for ten minutes on a
    # slow endpoint, so it sets its own, shorter limit instead of inheriting
    # that one.
    it "bounds the call with an explicit deadline rather than inheriting the SDK's 600-second default" do
      stub_request(:post, count_tokens_url)
        .to_return(
          status: 200,
          body: {input_tokens: 4242}.to_json,
          headers: {"Content-Type" => "application/json"}
        )
      captured = nil #: Hash[Symbol, untyped]?
      allow(Anthropic::Client).to receive(:new).and_wrap_original do |original, **kwargs|
        captured = kwargs
        original.call(**kwargs)
      end

      with_env("ANTHROPIC_API_KEY" => "sk-ant-not-a-real-key", "RUN_LIVE_LLM_TESTS" => "1") do
        described_class.count("x" * 4000)
      end

      expect(captured).to be_a(Hash)
      deadline = captured&.fetch(:timeout, nil)
      expect(deadline).to be_a(Numeric),
        "Anthropic::Client was constructed without a timeout: — it inherits the SDK's 600s default"
      expect(deadline).to be_positive
      expect(deadline).to be < 600
    end

    it "does not blank-guard on the un-stripped key, so a trailing newline is not mistaken for a real key" do
      stub = stub_request(:post, count_tokens_url)
        .to_return(
          status: 200,
          body: {input_tokens: 4242}.to_json,
          headers: {"Content-Type" => "application/json"}
        )

      result = with_env("ANTHROPIC_API_KEY" => " \n ", "RUN_LIVE_LLM_TESTS" => "1") do
        described_class.count("x" * 4000)
      end

      expect(stub).not_to have_been_requested
      expect(result).to be_nil
    end
  end

  # @lat: [[verification-gates#RSpec runtime contracts]]
  describe "suite HTTP policy" do
    let(:anthropic_request) { VCR::Request.new(:post, "https://#{LiveLlmGate::HOST}/v1/messages") }

    def with_live_llm_flag(value)
      with_env(LiveLlmGate::ENV_FLAG => value) do
        LiveLlmGate.apply_http_policy!
        yield
      end
    ensure
      # Rebuild the policy from the real environment, so one example cannot
      # leave the suite's HTTP policy loosened for everything that runs after it.
      LiveLlmGate.apply_http_policy!
    end

    it "blocks api.anthropic.com in an ordinary run" do
      with_live_llm_flag(nil) do
        expect(Array(WebMock::Config.instance.allow)).not_to include(LiveLlmGate::HOST)
        expect(VCR.request_ignorer.ignore?(anthropic_request)).to be(false)
      end
    end

    it "blocks openrouter.ai in an ordinary run" do
      with_live_llm_flag(nil) do
        expect(Array(WebMock::Config.instance.allow)).not_to include(LiveLlmGate::OPENROUTER_HOST)
        request = VCR::Request.new(:post, "https://#{LiveLlmGate::OPENROUTER_HOST}/api/v1/chat/completions")
        expect(VCR.request_ignorer.ignore?(request)).to be(false)
      end
    end

    it "permits api.anthropic.com once the operator has opted into live LLM billing" do
      with_live_llm_flag("1") do
        expect(Array(WebMock::Config.instance.allow)).to include(LiveLlmGate::HOST)
        expect(VCR.request_ignorer.ignore?(anthropic_request)).to be(true)
      end
    end

    it "permits openrouter.ai once the operator has opted into live LLM billing" do
      with_live_llm_flag("1") do
        expect(Array(WebMock::Config.instance.allow)).to include(LiveLlmGate::OPENROUTER_HOST)
        request = VCR::Request.new(:post, "https://#{LiveLlmGate::OPENROUTER_HOST}/api/v1/chat/completions")
        expect(VCR.request_ignorer.ignore?(request)).to be(true)
      end
    end

    # Before each system spec, Capybara starts a real Puma server and pings it
    # with a localhost "__identify__" request. Blocking localhost would fail
    # every :system example, so that allowance is not something the flag
    # switches on and off.
    it "keeps localhost reachable under either setting" do
      with_live_llm_flag("1") { expect(WebMock::Config.instance.allow_localhost).to be(true) }
      with_live_llm_flag(nil) { expect(WebMock::Config.instance.allow_localhost).to be(true) }
    end
  end
end
