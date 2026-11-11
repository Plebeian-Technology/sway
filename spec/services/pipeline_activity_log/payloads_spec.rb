# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PipelineActivityLog payloads" do
  # steep:ignore:start
  def round_trip(payload)
    JSON.parse(JSON.generate(payload.to_h), symbolize_names: true)
  end
  # steep:ignore:end

  describe PipelineActivityLog::StageFailurePayload do
    let(:payload) { described_class.new(stage_name: "extract-text", error_message: "timeout") }

    it "round-trips through JSON" do
      result = round_trip(payload)
      expect(result[:stage_name]).to eq("extract-text")
      expect(result[:error_message]).to eq("timeout")
    end

    it "truncates error_message to 4000 chars (LOW-5)" do
      long_msg = "x" * 5000
      p = described_class.new(stage_name: "extract-text", error_message: long_msg)
      expect(p.to_h[:error_message].length).to eq(4000)
    end
  end

  describe PipelineActivityLog::IngestionFailurePayload do
    let(:payload) { described_class.new(bill_external_id: "BAL-001", error_message: "invalid record") }

    it "round-trips through JSON" do
      result = round_trip(payload)
      expect(result[:bill_external_id]).to eq("BAL-001")
      expect(result[:error_message]).to eq("invalid record")
    end
  end

  describe PipelineActivityLog::LlmProviderErrorPayload do
    let(:payload) { described_class.new(error_message: "OpenAI 503") }

    it "round-trips through JSON" do
      result = round_trip(payload)
      expect(result[:error_message]).to eq("OpenAI 503")
    end
  end

  describe PipelineActivityLog::LlmJsonParseFailurePayload do
    let(:payload) { described_class.new(error_message: "unexpected token", raw_excerpt: '{"bad":') }

    it "round-trips through JSON" do
      result = round_trip(payload)
      expect(result[:error_message]).to eq("unexpected token")
      expect(result[:raw_excerpt]).to eq('{"bad":')
    end
  end
end
