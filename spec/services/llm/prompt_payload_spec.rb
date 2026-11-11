# frozen_string_literal: true

require "rails_helper"

# Llm::PromptPayload checks its own argument types at runtime. Steep already
# checks them statically; this pins the TypeError at the boundary, so bad
# input fails here, not inside the Anthropic SDK.
RSpec.describe Llm::PromptPayload do
  describe ".new" do
    it "constructs successfully with two String fields" do
      payload = described_class.new(system_prompt: "sys", user_message: "user")
      expect(payload.system_prompt).to eq("sys")
      expect(payload.user_message).to eq("user")
    end

    it "accepts empty strings (length is not enforced here)" do
      payload = described_class.new(system_prompt: "", user_message: "")
      expect(payload.system_prompt).to eq("")
      expect(payload.user_message).to eq("")
    end

    it "raises TypeError when system_prompt is nil" do
      expect {
        described_class.new(system_prompt: nil, user_message: "user")
      }.to raise_error(TypeError, /system_prompt must be a String/)
    end

    it "raises TypeError when user_message is nil" do
      expect {
        described_class.new(system_prompt: "sys", user_message: nil)
      }.to raise_error(TypeError, /user_message must be a String/)
    end

    it "raises TypeError when system_prompt is a non-String (e.g. Integer)" do
      expect {
        described_class.new(system_prompt: 42, user_message: "user")
      }.to raise_error(TypeError, /system_prompt must be a String \(got Integer\)/)
    end

    it "raises TypeError when user_message is a non-String (e.g. StringIO)" do
      expect {
        described_class.new(system_prompt: "sys", user_message: StringIO.new("oops"))
      }.to raise_error(TypeError, /user_message must be a String \(got StringIO\)/)
    end
  end
end
