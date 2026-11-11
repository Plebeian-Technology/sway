# frozen_string_literal: true

require "rails_helper"

# @lat: [[sway-logging-design#Why filter_parameters lists :anthropic_api_key alongside the :_key substring matcher]]
RSpec.describe "filter_parameters" do
  let(:filters) { Rails.application.config.filter_parameters }

  # @lat: [[sway-logging-design#Why the :anthropic_api_key spec checks the joined filter list, not its shape]]
  let(:matchers_joined) { filters.map(&:inspect).join(",") }

  it "includes the :anthropic_api_key matcher (documentation + defense in depth)" do
    expect(matchers_joined).to include("anthropic_api_key"),
      "expected an anthropic_api_key matcher in filter_parameters; matchers: #{filters.map(&:inspect).inspect}"
  end

  it "includes a matcher that matches the sk-ant- key prefix (value-leak defense)" do
    regexp_matchers = filters.grep(Regexp)
    expect(regexp_matchers.any? { |re| re.match?("sk-ant-abc123XYZ") }).to be(true),
      "expected a Regexp matcher for sk-ant- prefix; matchers: #{regexp_matchers.map(&:inspect)}"
  end

  it "still scrubs an :anthropic_api_key param via Rails ParameterFilter" do
    pf = ActiveSupport::ParameterFilter.new(filters)
    scrubbed = pf.filter("anthropic_api_key" => "sk-ant-secret-value")
    expect(scrubbed["anthropic_api_key"]).to eq("[FILTERED]")
  end

  it "scrubs verification codes and residential registration fields while preserving region_code" do
    pf = ActiveSupport::ParameterFilter.new(filters)
    scrubbed = pf.filter(
      "code" => "123456",
      "street" => "100 Holiday St",
      "street2" => "Suite 400",
      "postal_code" => "21202",
      "latitude" => "39.2904",
      "longitude" => "-76.6122",
      "full_name" => "Jane Citizen",
      "region_code" => "MD"
    )

    expect(scrubbed).to eq(
      "code" => "[FILTERED]",
      "street" => "[FILTERED]",
      "street2" => "[FILTERED]",
      "postal_code" => "[FILTERED]",
      "latitude" => "[FILTERED]",
      "longitude" => "[FILTERED]",
      "full_name" => "[FILTERED]",
      "region_code" => "MD"
    )
  end

  # @lat: [[sway-logging-design#Why .redact_anthropic_key exists separately from Rails' filter]]
  describe "ParameterFilter value-scrub behavior (Rails limitation)" do
    let(:pf) { ActiveSupport::ParameterFilter.new(filters) }

    it "does NOT scrub sk-ant- VALUES when bound to unrelated keys (Rails limitation)" do
      scrubbed = pf.filter("body" => "prefix sk-ant-leaked-value suffix")
      expect(scrubbed["body"]).to eq("prefix sk-ant-leaked-value suffix")
    end

    it "scrubs sk-ant- VALUES anywhere in a string via SwayLogging.redact_anthropic_key" do
      original = "prefix sk-ant-leaked-value suffix"
      redacted = SwayLogging.redact_anthropic_key(original)
      expect(redacted).to eq("prefix [FILTERED] suffix")
    end

    it "redact_anthropic_key handles a value with no key (no-op)" do
      expect(SwayLogging.redact_anthropic_key("safe payload, no key here")).to eq(
        "safe payload, no key here"
      )
    end

    it "redact_anthropic_key handles multiple key instances in one string" do
      input = "first sk-ant-aaa then sk-ant-bbb_ccc"
      expect(SwayLogging.redact_anthropic_key(input)).to eq(
        "first [FILTERED] then [FILTERED]"
      )
    end
  end

  # @lat: [[sway-logging-design#What .log_exception protects against]]
  describe "SwayLogging.log_exception invokes redact_anthropic_key" do
    it "redacts sk-ant- values from the exception message before logging" do
      captured_messages = ["seed"].drop(1)
      allow(Rails.logger).to receive(:error) { |msg| captured_messages << msg.to_s }

      err = StandardError.new("upstream returned sk-ant-leaked-value for that request")
      SwayLogging.log_exception("test.event", exception: err)

      joined = captured_messages.join("\n")
      expect(joined).to include("[FILTERED]")
      expect(joined).not_to include("sk-ant-leaked-value")
    end

    it "redacts sk-ant- values from the exception full_message / backtrace dump" do
      captured_messages = ["seed"].drop(1)
      allow(Rails.logger).to receive(:error) { |msg| captured_messages << msg.to_s }

      err = StandardError.new("safe")
      err.set_backtrace(["lib/some_file.rb:42:in `block in execute' /* sk-ant-trace-leaked */"])
      SwayLogging.log_exception("test.event", exception: err)

      joined = captured_messages.join("\n")
      expect(joined).to include("[FILTERED]")
      expect(joined).not_to include("sk-ant-trace-leaked")
    end
  end
end
