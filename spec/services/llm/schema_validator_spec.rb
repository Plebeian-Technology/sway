# frozen_string_literal: true

require "rails_helper"

# Llm::SchemaValidator is the parse-and-validate step both adapters share.
# Checks error messages name the provider, and a violation surfaces as
# Llm::SchemaError naming the bad field.

RSpec.describe Llm::SchemaValidator do
  let(:schema) { BILL_SUMMARY_SCHEMA }
  let(:valid_payload) do
    {
      "summary_markdown" => "Brief summary.",
      "full_breakdown_markdown" => "## Section\nDetailed breakdown.",
      "draft_org_positions" => [] #: Array[Hash[String, untyped]]
    }
  end

  describe ".parse_and_validate" do
    it "returns the parsed Hash when JSON parses and schema validates" do
      result = described_class.parse_and_validate(
        JSON.generate(valid_payload),
        provider_label: "claude",
        schema: schema
      )

      expect(result).to eq(valid_payload)
    end

    # When a response overshoots a repairable limit, it's trimmed not
    # thrown away. The old schema_hash: arg let a caller's limit silently
    # DROP items; replaced by the validator's own hash.
    describe "normalization" do
      it "degrades the overshoot and keeps the response, with no kwarg to enable it" do
        result = described_class.parse_and_validate(
          JSON.generate(
            "summary_markdown" => "Brief summary.",
            "full_breakdown_markdown" => "## Section",
            "categories" => %w[Health Taxes Housing Transit]
          ),
          provider_label: "claude",
          schema: schema
        )

        expect(result["categories"]).to eq(%w[Health Taxes Housing])
        expect(result["summary_markdown"]).to eq("Brief summary.")
      end

      it "reads its bound from the validator it was given, not from anywhere the caller controls" do
        tight = JSONSchemer.schema(
          BILL_SUMMARY_SCHEMA_HASH.deep_dup.tap { |hash|
            hash["properties"]["categories"]["maxItems"] = 1
          }
        )

        result = described_class.parse_and_validate(
          JSON.generate(
            "summary_markdown" => "Brief summary.",
            "full_breakdown_markdown" => "## Section",
            "categories" => %w[Health Taxes Housing Transit]
          ),
          provider_label: "claude",
          schema: tight
        )

        expect(result["categories"]).to eq(%w[Health])
      end

      it "still raises for a violation nothing can repair" do
        expect {
          described_class.parse_and_validate(
            JSON.generate({"summary_markdown" => "", "full_breakdown_markdown" => "x"}),
            provider_label: "claude",
            schema: schema
          )
        }.to raise_error(Llm::SchemaError, /Schema validation failed from claude/)
      end

      # cited_section_keys gets a different repair than an
      # ordinary maxItems field (see ResponseNormalizer#cap_items). No
      # repeats here, so 251 DISTINCT keys still raises.
      it "raises for an over-length cited_section_keys with no repeats to remove" do
        oversized = Array.new(251) { |i| "art_1__sec_#{i}" }

        expect {
          described_class.parse_and_validate(
            JSON.generate(valid_payload.merge("cited_section_keys" => oversized)),
            provider_label: "claude",
            schema: schema
          )
        }.to raise_error(Llm::SchemaError, /Schema validation failed from claude:.*cited_section_keys/)
      end

      # @lat: [[untrusted-text-in-prompts#Why an overshooting key list is deduped rather than refused]]
      it "accepts a cited_section_keys that overshoots only because of a repeated key" do
        real_keys = Array.new(250) { |i| "art_1__sec_#{i}" }

        result = described_class.parse_and_validate(
          JSON.generate(valid_payload.merge("cited_section_keys" => real_keys + [real_keys.first])),
          provider_label: "claude",
          schema: schema
        )

        expect(result["cited_section_keys"]).to eq(real_keys)
      end
    end

    # The production shape the cap used to hide — 250 real
    # citations plus one fabricated one past the cap, with no repeats for
    # #dedupe to remove. This only shows the step refuses rather than trims.
    describe "a citation that is both past the cap and fabricated" do
      it "is refused before SummaryCitationValidator ever runs" do
        bill = create(:bill)
        real_keys = Array.new(250) { |i| "art_1__sec_#{i}" }
        real_keys.each { |key| create(:bill_section_reference, bill: bill, key: key) }
        fabricated_key = "art_99__sec_999" # not among real_keys — no BillSectionReference carries it

        body = JSON.generate(valid_payload.merge("cited_section_keys" => real_keys + [fabricated_key]))

        expect {
          described_class.parse_and_validate(body, provider_label: "claude", schema: schema)
        }.to raise_error(Llm::SchemaError)
      end
    end

    it "tags JSON::ParserError messages with the provider label (claude)" do
      expect {
        described_class.parse_and_validate(
          "{not json",
          provider_label: "claude",
          schema: schema
        )
      }.to raise_error(Llm::SchemaError, /Malformed JSON from claude:/)
    end

    it "tags JSON::ParserError messages with the provider label (llama.cpp)" do
      expect {
        described_class.parse_and_validate(
          "{not json",
          provider_label: "llama.cpp",
          schema: schema
        )
      }.to raise_error(Llm::SchemaError, /Malformed JSON from llama\.cpp:/)
    end

    it "truncates a giant JSON::ParserError message to keep logs sane" do
      expect {
        described_class.parse_and_validate(
          "X" * 5000,
          provider_label: "claude",
          schema: schema
        )
      }.to raise_error(Llm::SchemaError) { |error|
        expect(error.message.length).to be <= 240 # 200 chars of message plus the "Malformed JSON from claude: " prefix
      }
    end

    it "raises Llm::SchemaError with data_pointer detail when schema rejects" do
      bad_payload = valid_payload.merge("summary_markdown" => 12345) # wrong type

      expect {
        described_class.parse_and_validate(
          JSON.generate(bad_payload),
          provider_label: "claude",
          schema: schema
        )
      }.to raise_error(Llm::SchemaError, /Schema validation failed from claude:.*summary_markdown/)
    end

    it "raises Llm::SchemaError with the first error message when no data_pointer is present" do
      # A required top-level key is missing, so the error lands at the root and
      # data_pointer is the empty string. The helper then falls back to the
      # error's own message text.
      bad_payload = valid_payload.except("summary_markdown")

      expect {
        described_class.parse_and_validate(
          JSON.generate(bad_payload),
          provider_label: "llama.cpp",
          schema: schema
        )
      }.to raise_error(Llm::SchemaError, /Schema validation failed from llama\.cpp/)
    end

    # Both adapters promise this helper raises provider-tagged messages so
    # triage stays grep-able. Only the malformed-JSON branch kept that
    # promise; the more-common schema branch left the tag off.
    it "tags BOTH failure branches with the provider, which is what makes triage grep-able" do
      %w[claude llama.cpp].each do |provider|
        expect {
          described_class.parse_and_validate("{not json", provider_label: provider, schema: schema)
        }.to raise_error(Llm::SchemaError, /from #{Regexp.escape(provider)}/)

        expect {
          described_class.parse_and_validate(
            JSON.generate(valid_payload.except("summary_markdown")),
            provider_label: provider,
            schema: schema
          )
        }.to raise_error(Llm::SchemaError, /from #{Regexp.escape(provider)}/)
      end
    end
  end
end
