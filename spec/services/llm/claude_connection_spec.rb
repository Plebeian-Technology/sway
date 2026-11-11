# frozen_string_literal: true

require "rails_helper"

# The one place an Anthropic::Client is constructed. Both the synchronous
# adapter and the batch service build through it, so the retry budget and the
# deadline cannot drift apart between them.
RSpec.describe Llm::ClaudeConnection do
  around do |example|
    original_key = ENV["ANTHROPIC_API_KEY"]
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test-key"
    begin
      example.run
    ensure
      ENV["ANTHROPIC_API_KEY"] = original_key
    end
  end

  describe ".build" do
    it "constructs an Anthropic::Client with the resolved key, retry budget and deadline" do
      client = instance_double(Anthropic::Client)
      expect(Anthropic::Client).to receive(:new).with(
        api_key: "sk-ant-test-key",
        max_retries: described_class::DEFAULT_MAX_RETRIES,
        timeout: described_class::DEFAULT_TIMEOUT_SECONDS
      ).and_return(client)

      expect(described_class.build).to eq(client)
    end

    it "does not memoize — each caller owns the client it builds" do
      allow(Anthropic::Client).to receive(:new).and_return(instance_double(Anthropic::Client))
      2.times { described_class.build }
      expect(Anthropic::Client).to have_received(:new).twice
    end

    it "raises Llm::TransportError, not KeyError, when the key is absent" do
      ENV["ANTHROPIC_API_KEY"] = nil
      expect { described_class.build }.to raise_error(Llm::TransportError, /ANTHROPIC_API_KEY is not set/)
    end

    it "treats a blank key as absent" do
      ENV["ANTHROPIC_API_KEY"] = "   "
      expect { described_class.build }.to raise_error(Llm::TransportError, /ANTHROPIC_API_KEY is not set/)
    end

    it "reads the key through EnvSecret rather than ENV directly" do
      allow(EnvSecret).to receive(:read).with("ANTHROPIC_API_KEY").and_return("sk-ant-from-secret")
      allow(Anthropic::Client).to receive(:new).and_return(instance_double(Anthropic::Client))
      described_class.build
      expect(Anthropic::Client).to have_received(:new).with(hash_including(api_key: "sk-ant-from-secret"))
    end
  end

  describe "the shared budgets" do
    it "keeps a two-retry budget" do
      expect(described_class::DEFAULT_MAX_RETRIES).to eq(2)
    end

    it "keeps a 120 second deadline" do
      expect(described_class::DEFAULT_TIMEOUT_SECONDS).to eq(120)
    end
  end
end
