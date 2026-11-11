# frozen_string_literal: true

require "rails_helper"
require "net/http"

# @lat: [[llamacpp-structured-output-conformance#What it pins down]]
# Last green 2026-09-05, model LiquidAI/LFM2.5-2.6B-GGUF:Q4_K_M, 2 examples 0 failures, via: dip run bundle exec rspec /app/spec/integration/llamacpp_response_format_spec.rb
RSpec.describe "llama.cpp response_format integration" do
  base_url = ENV.fetch("LLAMACPP_BASE_URL", "http://host.docker.internal:8888/v1")
  models_uri = URI.parse("#{base_url}/models") #: URI::HTTP
  models_uri_host = models_uri.host #: String

  before do
    Net::HTTP.start(models_uri_host, models_uri.port, open_timeout: 1, read_timeout: 2) do |http|
      response = http.get(models_uri.request_uri)
      unless response.code == "200"
        skip "llama.cpp returned HTTP #{response.code} at #{models_uri} — server up but not ready"
      end
    end
  rescue => e
    skip "llama.cpp not reachable at #{models_uri}: #{e.class}: #{e.message}"
  end

  let(:client) do
    OpenAI::Client.new(
      uri_base: base_url,
      access_token: "sk-no-key-required",
      # @lat: [[llm-summaries#LLM bill summaries#Two adapters, one client#What the local server is asked for, and how long it is given]]
      request_timeout: 300
    )
  end

  let(:schema_hash) do
    JSON.parse(Rails.root.join("config", "schemas", "bill_summary.json").read)
  end

  let(:prompt) do
    <<~PROMPT
      Summarize a fictional Baltimore City Council bill titled "Annual Tree
      Census Act of 2026" that would require the Department of Recreation
      and Parks to count every public tree each March and publish a
      report. Include one draft organization position from a fictional
      "Baltimore Tree Coalition" stance=support. Respond as JSON matching
      the schema you were given.
    PROMPT
  end

  it "json_object alone: model may drift (baseline — captures current bug)" do
    response = client.chat(parameters: {
      model: ENV.fetch("LLAMACPP_MODEL", "local"),
      messages: [{role: "user", content: prompt}],
      response_format: {type: "json_object"},
      temperature: 0.2,
      max_tokens: 2048
    })

    content = response.dig("choices", 0, "message", "content")
    parsed = JSON.parse(content)
    errors = BILL_SUMMARY_SCHEMA.validate(parsed).to_a

    # Loose on purpose: this example is a baseline and a worked example, not a
    # contract. It records what the model really returns when nothing
    # constrains its grammar, so when the output drifts there is something
    # concrete to work from while tuning the prompt.
    Rails.logger.info("[llamacpp-int] json_object keys=#{parsed.keys.inspect} schema_errors=#{errors.size}")
    expect(parsed).to be_a(Hash)
  end

  it "json_schema: response conforms to BILL_SUMMARY_SCHEMA" do
    response = client.chat(parameters: {
      model: ENV.fetch("LLAMACPP_MODEL", "local"),
      messages: [{role: "user", content: prompt}],
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "bill_summary",
          schema: schema_hash,
          strict: true
        }
      },
      temperature: 0.2,
      max_tokens: 2048
    })

    content = response.dig("choices", 0, "message", "content")
    expect(content).to be_present, "llama.cpp returned empty content; full response: #{response.inspect}"

    parsed = JSON.parse(content)
    errors = BILL_SUMMARY_SCHEMA.validate(parsed).to_a
    expect(errors).to(
      eq([]),
      "Schema violations: #{errors.map { |e| "#{e["data_pointer"]} (#{e["type"]})" }.join(", ")}\n" \
        "Payload keys: #{parsed.keys.inspect}\n" \
        "Full payload: #{JSON.pretty_generate(parsed)[0, 2000]}"
    )
    # summary_markdown is the schema's ONE required key, so the grammar
    # guarantees it. Nothing else here may be demanded.
    expect(parsed["summary_markdown"]).to be_a(String).and(be_present)

    # The prompt asks for a position; the schema does not require one, and this
    # 2.6B model obeys the ask most of the time. Recorded, never asserted — a
    # demand the grammar cannot enforce is a coin flip, not a gate.
    Rails.logger.info("[llamacpp-int] json_schema optional_keys=#{(parsed.keys - ["summary_markdown"]).inspect}")
  end
end
