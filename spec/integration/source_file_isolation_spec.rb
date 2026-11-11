# frozen_string_literal: true

require "rails_helper"

# @lat: [[explanation/llm-summaries#Two adapters, one client#The job never names an SDK]]
RSpec.describe "GenerateBillSummaryJob source-file isolation" do
  let(:job_source) do
    Rails.root.join("app", "jobs", "generate_bill_summary_job.rb").read
  end

  let(:non_comment_lines) do
    # Drop lines that are nothing but a comment (any leading whitespace, then
    # `#`). A trailing comment stays attached to its code line, so a line like
    # `Llm::Client.build  # see ...` would still count — the strictest way to
    # read this rule.
    job_source.lines.reject { |line| line.strip.start_with?("#") }
  end

  it "contains zero non-comment references to OpenAI::Client (SDK isolation contract)" do
    matching = non_comment_lines.select { |line| line.include?("OpenAI::Client") }
    expect(matching).to be_empty,
      "expected zero non-comment OpenAI::Client refs in app/jobs/generate_bill_summary_job.rb; " \
      "found: #{matching.inspect}"
  end

  it "contains zero non-comment references to Anthropic::Client (SDK isolation contract)" do
    matching = non_comment_lines.select { |line| line.include?("Anthropic::Client") }
    expect(matching).to be_empty,
      "expected zero non-comment Anthropic::Client refs in app/jobs/generate_bill_summary_job.rb; " \
      "found: #{matching.inspect}"
  end

  it "documents the by-design SDK refs in the adapter layer (sanity counter-assertion)" do
    claude_source = Rails.root.join("app", "services", "llm", "claude_connection.rb").read
    llamacpp_source = Rails.root.join("app", "services", "llm", "llamacpp_adapter.rb").read

    expect(claude_source).to include("Anthropic::Client"),
      "Llm::ClaudeConnection SHOULD reference Anthropic::Client — that is the SDK isolation contract"
    expect(llamacpp_source).to include("OpenAI::Client"),
      "Llm::LlamacppAdapter SHOULD reference OpenAI::Client — that is the SDK isolation contract"
  end
end
