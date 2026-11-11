# frozen_string_literal: true

# @lat: [[llm-adapter-error-classification#Helper API the host spec supplies]]
RSpec.shared_examples "an Llm structured-output adapter" do
  it "classifies a truncated response as a discardable Llm::SchemaError" do
    stub_adapter_truncated

    expect { run_structured_call }.to raise_error(Llm::SchemaError, /truncated/)
  end

  # "" is the case both sides always had. The three whitespace bodies are the
  # ones that told the two adapters apart.
  ["", "\n", "   ", "\n\n  \t"].each do |blank|
    it "classifies a #{blank.inspect} body as a retryable Llm::TransportError" do
      stub_adapter_body(blank)

      expect { run_structured_call }.to raise_error(Llm::TransportError, /empty response/)
    end
  end

  it "classifies a transport failure as a retryable Llm::TransportError" do
    stub_adapter_transport

    expect { run_structured_call }.to raise_error(Llm::TransportError)
  end
end
