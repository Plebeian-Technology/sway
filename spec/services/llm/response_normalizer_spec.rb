# frozen_string_literal: true

require "rails_helper"

# Stripping keywords from the SENT schema while validating the ORIGINAL hash
# risks the API obeying one, loosening output while validation stays strict.
# Pins the repair safeguard, not API behavior.
RSpec.describe Llm::ResponseNormalizer do
  describe ".call" do
    it "truncates an array that overshoots maxItems" do
      schema = {
        "type" => "object",
        "properties" => {
          "categories" => {"type" => "array", "maxItems" => 3, "items" => {"type" => "string"}}
        }
      }
      payload = {"categories" => %w[Health Taxes Housing Transit]}

      expect(described_class.call(payload, schema))
        .to eq({"categories" => %w[Health Taxes Housing]})
    end

    it "leaves an array within maxItems byte-identical" do
      schema = {"type" => "array", "maxItems" => 3}

      expect(described_class.call(%w[a b], schema)).to eq(%w[a b])
    end

    it "descends into nested objects and arrays" do
      schema = {
        "type" => "object",
        "properties" => {
          "outer" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "properties" => {"inner" => {"type" => "array", "maxItems" => 1}}
            }
          }
        }
      }
      payload = {"outer" => [{"inner" => %w[a b c]}, {"inner" => %w[d]}]}

      expect(described_class.call(payload, schema))
        .to eq({"outer" => [{"inner" => %w[a]}, {"inner" => %w[d]}]})
    end

    it "leaves keys the schema does not describe alone" do
      schema = {"type" => "object", "properties" => {"a" => {"type" => "string"}}}
      payload = {"a" => "x", "undeclared" => [1, 2, 3]}

      expect(described_class.call(payload, schema)).to eq(payload)
    end

    # The keywords we deliberately do NOT repair. Each one either has nothing
    # sensible to fall back to, or repairing it would change what the response
    # MEANS, which is worse than failing loudly.
    it "does not invent content to satisfy minItems" do
      schema = {"type" => "object", "properties" => {"a" => {"type" => "array", "minItems" => 2}}}
      payload = {"a" => []}

      expect(described_class.call(payload, schema)).to eq(payload)
    end

    it "does not clamp a numeric against minimum — that would reassign the value's meaning" do
      schema = {"type" => "object", "properties" => {"index" => {"type" => "integer", "minimum" => 0}}}
      payload = {"index" => -3}

      expect(described_class.call(payload, schema)).to eq(payload)
    end

    it "does not truncate a string against maxLength" do
      schema = {"type" => "object", "properties" => {"a" => {"type" => "string", "maxLength" => 2}}}
      payload = {"a" => "abcdef"}

      expect(described_class.call(payload, schema)).to eq(payload)
    end

    it "tolerates a payload whose shape disagrees with the schema" do
      schema = {"type" => "object", "properties" => {"a" => {"type" => "array", "maxItems" => 1}}}

      expect(described_class.call({"a" => "not an array"}, schema)).to eq({"a" => "not an array"})
      expect(described_class.call("not an object", schema)).to eq("not an object")
      expect(described_class.call(nil, schema)).to be_nil
    end

    it "reports the degradation instead of applying it silently" do
      schema = {"type" => "array", "maxItems" => 1}

      expect(SwayLogging).to receive(:warn).with(
        "llm.response_normalizer.truncated_array",
        hash_including(max_items: 1, received: 3)
      )

      described_class.call(%w[a b c], schema)
    end

    # cited_section_keys gets a different repair from an ordinary maxItems
    # field like categories — see #cap_items for the full reasoning
    # This payload has no repeats, so nothing changes.
    it "leaves cited_section_keys alone when nothing in it repeats, even past maxItems" do
      schema = {
        "type" => "object",
        "properties" => {
          "cited_section_keys" => {"type" => "array", "maxItems" => 3, "items" => {"type" => "string"}}
        }
      }
      payload = {"cited_section_keys" => %w[a b c d]}

      expect(described_class.call(payload, schema)).to eq(payload)
    end

    # The repair #cap_items gives cited_section_keys instead of a position
    # trim: remove a repeated entry, keep every distinct one.
    it "removes a repeated entry from cited_section_keys instead of trimming by position" do
      schema = {
        "type" => "object",
        "properties" => {
          "cited_section_keys" => {"type" => "array", "maxItems" => 3, "items" => {"type" => "string"}}
        }
      }
      payload = {"cited_section_keys" => %w[a b a]}

      expect(described_class.call(payload, schema)).to eq({"cited_section_keys" => %w[a b]})
    end

    it "still trims a same-shaped field that is not cited_section_keys" do
      schema = {
        "type" => "object",
        "properties" => {
          "other_keys" => {"type" => "array", "maxItems" => 3, "items" => {"type" => "string"}}
        }
      }
      payload = {"other_keys" => %w[a b c d]}

      expect(described_class.call(payload, schema)).to eq({"other_keys" => %w[a b c]})
    end
  end

  # The real-world case, run end to end against the actual schema.
  describe "the shipped bill_summary contract" do
    it "keeps a four-category summary instead of discarding a paid-for response" do
      payload = {
        "summary_markdown" => "What changed.",
        "full_breakdown_markdown" => "## Section 1",
        "categories" => %w[Health Taxes Housing Transit]
      }

      normalized = described_class.call(payload, BILL_SUMMARY_SCHEMA_HASH)

      expect(normalized["categories"]).to eq(%w[Health Taxes Housing])
      expect(BILL_SUMMARY_SCHEMA.validate(normalized).to_a).to be_empty
    end

    it "still fails a response with nothing usable in it, rather than inventing one" do
      payload = {"summary_markdown" => "", "full_breakdown_markdown" => "x"}

      normalized = described_class.call(payload, BILL_SUMMARY_SCHEMA_HASH)

      expect(BILL_SUMMARY_SCHEMA.validate(normalized).to_a).not_to be_empty
    end

    # A 251-entry cited_section_keys with no repeats still fails
    # validation — nothing to de-duplicate, so it stays 251 long. See
    # Llm::SchemaValidator spec for what happens to that failure.
    it "still fails a 251-entry cited_section_keys when every entry is distinct" do
      payload = {
        "summary_markdown" => "What changed.",
        "cited_section_keys" => Array.new(251) { |i| "art_1__sec_#{i}" }
      }

      normalized = described_class.call(payload, BILL_SUMMARY_SCHEMA_HASH)

      expect(normalized["cited_section_keys"].length).to eq(251)
      expect(BILL_SUMMARY_SCHEMA.validate(normalized).to_a).not_to be_empty
    end

    # Blocker fix: a 251-entry cited_section_keys overshooting ONLY from a
    # repeat is 250 distinct keys — an honest answer the old trim-nothing
    # refused. #dedupe removes the repeat instead.
    it "accepts a 251-entry cited_section_keys when one entry is a repeat" do
      real_keys = Array.new(250) { |i| "art_1__sec_#{i}" }
      payload = {
        "summary_markdown" => "What changed.",
        "cited_section_keys" => real_keys + [real_keys.first]
      }

      normalized = described_class.call(payload, BILL_SUMMARY_SCHEMA_HASH)

      expect(normalized["cited_section_keys"]).to eq(real_keys)
      expect(BILL_SUMMARY_SCHEMA.validate(normalized).to_a).to be_empty
    end

    # cited_news_urls is NOT in NO_TRIM_FIELDS, so overshoots are trimmed to 5
    it "truncates cited_news_urls when it exceeds maxItems (unlike cited_section_keys which is in NO_TRIM_FIELDS)" do
      urls = Array.new(6) { |i| "https://news.example.com/article_#{i}" }
      payload = {
        "summary_markdown" => "What changed.",
        "cited_news_urls" => urls
      }

      normalized = described_class.call(payload, BILL_SUMMARY_SCHEMA_HASH)

      expect(normalized["cited_news_urls"]).to eq(urls.first(5))
      expect(BILL_SUMMARY_SCHEMA.validate(normalized).to_a).to be_empty
    end
  end
end
