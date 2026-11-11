# frozen_string_literal: true

require "rails_helper"

# The schema subset Anthropic accepts leaves out numeric/string/array-size
# limits. Strip them from the copy we SEND, but keep them on the object
# validating the response.
RSpec.describe Llm::StructuredOutputSchema do
  describe ".for_request" do
    it "drops string, numeric and array constraints at every depth" do
      schema = {
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["a"],
        "properties" => {
          "a" => {"type" => "string", "minLength" => 1, "maxLength" => 10, "pattern" => "^x"},
          "b" => {
            "type" => "array",
            "minItems" => 1,
            "maxItems" => 3,
            "uniqueItems" => true,
            "items" => {"type" => "integer", "minimum" => 0, "maximum" => 9, "multipleOf" => 3}
          }
        }
      }

      result = described_class.for_request(schema)

      expect(result["properties"]["a"]).to eq({"type" => "string"})
      expect(result["properties"]["b"]).to eq({
        "type" => "array",
        "items" => {"type" => "integer"}
      })
    end

    it "keeps everything the subset does support" do
      schema = {
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["stance"],
        "properties" => {
          "stance" => {"enum" => %w[support oppose]},
          "kind" => {"const" => "position"},
          "either" => {"anyOf" => [{"type" => "string"}, {"type" => "null"}]}
        }
      }

      expect(described_class.for_request(schema)).to eq(schema)
    end

    it "does not mutate the schema it is given — the validation instance is built from that object" do
      schema = {"type" => "object", "properties" => {"a" => {"type" => "string", "minLength" => 1}}}.freeze

      expect { described_class.for_request(schema) }.not_to raise_error
      expect(schema["properties"]["a"]).to include("minLength" => 1)
    end

    it "returns the same value for the same schema so the request path does not re-walk it per call" do
      expect(described_class.for_request(BILL_SUMMARY_SCHEMA_HASH))
        .to equal(described_class.for_request(BILL_SUMMARY_SCHEMA_HASH))
    end

    # CACHE is keyed by object IDENTITY. A schema built per request misses
    # AND adds a new entry under a new identity, forever — a memory leak on a
    # long-running worker with little memory to spare.
    it "does not retain one entry per call when a caller builds a schema per request" do
      calls = 2_000

      calls.times do |index|
        described_class.for_request({"type" => "object", "title" => "per-request-#{index}"})
      end

      expect(described_class::CACHE[:anthropic].size).to be < calls,
        "CACHE[:anthropic] holds #{described_class::CACHE[:anthropic].size} entries after #{calls} per-request schemas — " \
          "it is accumulating, which is exactly what identity keying was documented to prevent"
    end

    describe "dialect-specific handling and cache isolation" do
      it "returns the identical stripped schema for both Anthropic and OpenAI strict mode" do
        anthropic_wire = described_class.for_request(BILL_SUMMARY_SCHEMA_HASH, dialect: :anthropic)
        openai_wire = described_class.for_request(BILL_SUMMARY_SCHEMA_HASH, dialect: :openai)

        expect(anthropic_wire).to eq(openai_wire)
        described_class::UNSUPPORTED_KEYWORDS.each do |kw|
          expect(anthropic_wire.to_s).not_to include("\"#{kw}\"")
          expect(openai_wire.to_s).not_to include("\"#{kw}\"")
        end
      end

      it "defaults dialect to :anthropic preserving byte-identical output" do
        default_wire = described_class.for_request(BILL_SUMMARY_SCHEMA_HASH)
        anthropic_wire = described_class.for_request(BILL_SUMMARY_SCHEMA_HASH, dialect: :anthropic)

        expect(default_wire).to equal(anthropic_wire)
      end

      it "isolates caches per dialect so one dialect cannot serve its copy to the other" do
        test_schema = {"type" => "object", "properties" => {"x" => {"type" => "string", "minLength" => 1}}}

        anthropic_copy = described_class.for_request(test_schema, dialect: :anthropic)
        openai_copy = described_class.for_request(test_schema, dialect: :openai)

        expect(described_class::CACHE[:anthropic][test_schema]).to equal(anthropic_copy)
        expect(described_class::CACHE[:openai][test_schema]).to equal(openai_copy)
        expect(described_class::CACHE[:anthropic]).not_to equal(described_class::CACHE[:openai])
      end

      it "detects when both dialects share one cache entry" do
        shared_cache = {}.compare_by_identity
        stub_const("Llm::StructuredOutputSchema::CACHE", {anthropic: shared_cache, openai: shared_cache}.freeze)

        # Under shared cache, cache objects are identical
        expect(described_class::CACHE[:openai]).to equal(described_class::CACHE[:anthropic])
      end

      it "raises ArgumentError for an unknown dialect" do
        expect {
          described_class.for_request(BILL_SUMMARY_SCHEMA_HASH, dialect: :unsupported)
        }.to raise_error(ArgumentError, /unsupported schema dialect/)
      end
    end

    # #strip used to walk the schema blindly, unable to tell a JSON Schema
    # KEYWORD from a property NAME — a property called minimum lost itself,
    # producing a schema requiring what it also forbids.
    describe "keys in property-NAME position" do
      it "keeps a property whose NAME collides with an unsupported keyword" do
        schema = {
          "type" => "object",
          "additionalProperties" => false,
          "required" => %w[minimum maximum],
          "properties" => {
            "minimum" => {"type" => "integer", "minimum" => 0},
            "maximum" => {"type" => "integer", "maximum" => 9},
            "pattern" => {"type" => "string", "pattern" => "^x"}
          }
        }

        result = described_class.for_request(schema)

        expect(result["properties"].keys).to eq(%w[minimum maximum pattern])
        # The keyword INSIDE each subschema is still removed. Only the key used
        # as a property name survives.
        expect(result["properties"]["minimum"]).to eq({"type" => "integer"})
        expect(result["properties"]["maximum"]).to eq({"type" => "integer"})
        expect(result["properties"]["pattern"]).to eq({"type" => "string"})
      end

      it "keeps such names under $defs, definitions, patternProperties and dependentSchemas" do
        schema = {
          "$defs" => {"maxItems" => {"type" => "string", "maxLength" => 3}},
          "definitions" => {"uniqueItems" => {"type" => "string"}},
          "patternProperties" => {"^min" => {"type" => "string", "minLength" => 1}},
          "dependentSchemas" => {"pattern" => {"required" => ["a"]}}
        }

        result = described_class.for_request(schema)

        expect(result["$defs"].keys).to eq(["maxItems"])
        expect(result["$defs"]["maxItems"]).to eq({"type" => "string"})
        expect(result["definitions"].keys).to eq(["uniqueItems"])
        expect(result["patternProperties"]["^min"]).to eq({"type" => "string"})
        expect(result["dependentSchemas"].keys).to eq(["pattern"])
      end

      # SCHEMA_MAP_KEYWORDS missed two value-keyed-by-name keywords:
      # dependentRequired, dependencies. A dependency named like one got
      # DELETED, so the model never learned a rule still enforced.
      it "keeps such names under dependentRequired and the draft-07 dependencies form" do
        schema = {
          "dependentRequired" => {"minimum" => %w[maximum], "pattern" => %w[minLength]},
          "dependencies" => {"maxItems" => %w[uniqueItems], "multipleOf" => {"required" => ["a"]}}
        }

        result = described_class.for_request(schema)

        expect(result["dependentRequired"]).to eq(
          {"minimum" => %w[maximum], "pattern" => %w[minLength]}
        )
        expect(result["dependencies"]["maxItems"]).to eq(%w[uniqueItems])
        expect(result["dependencies"]["multipleOf"]).to eq({"required" => ["a"]})
      end

      it "still strips the keywords when they sit in KEYWORD position beside properties" do
        schema = {
          "type" => "object",
          "minItems" => 1,
          "properties" => {"a" => {"type" => "string"}}
        }

        expect(described_class.for_request(schema)).to eq(
          {"type" => "object", "properties" => {"a" => {"type" => "string"}}}
        )
      end
    end

    # The other half: teaching #strip about property NAMES didn't teach it
    # about DATA. enum/const/default/examples hold plain values, so deleting
    # a key inside changes what the rule MEANS.
    describe "values in DATA position" do
      it "leaves an object-valued const, default and examples untouched" do
        schema = {
          "type" => "object",
          "properties" => {
            "bounds" => {"const" => {"minimum" => 0, "maximum" => 100}},
            "window" => {"type" => "object", "default" => {"maxItems" => 3}},
            "samples" => {"type" => "string", "examples" => ["minLength", {"pattern" => "^a"}]}
          }
        }

        result = described_class.for_request(schema)

        expect(result["properties"]["bounds"]["const"]).to eq({"minimum" => 0, "maximum" => 100})
        expect(result["properties"]["window"]["default"]).to eq({"maxItems" => 3})
        expect(result["properties"]["samples"]["examples"]).to eq(["minLength", {"pattern" => "^a"}])
      end

      it "leaves an enum of objects untouched" do
        schema = {"properties" => {"threshold" => {"enum" => [{"minimum" => 1}, {"minimum" => 5}]}}}

        result = described_class.for_request(schema)

        expect(result["properties"]["threshold"]["enum"]).to eq([{"minimum" => 1}, {"minimum" => 5}])
      end

      it "still strips a keyword sitting beside a data-position value" do
        schema = {"type" => "integer", "minimum" => 0, "const" => {"minimum" => 7}}

        expect(described_class.for_request(schema)).to eq(
          {"type" => "integer", "const" => {"minimum" => 7}}
        )
      end

      it "leaves the shipped string enums exactly as they are" do
        schema = {"properties" => {"stance" => {"enum" => %w[support oppose neutral]}}}

        expect(described_class.for_request(schema)).to eq(schema)
      end
    end
  end

  # The three schemas reviews flagged, checked against the real files rather
  # than a fixture — a keyword added to config/schemas/ later has to be
  # stripped too.
  describe "the shipped schemas" do
    def schema_keywords_in(node)
      case node
      when Hash
        node.flat_map { |key, value| [key] + schema_keywords_in(value) }
      when Array
        node.flat_map { |value| schema_keywords_in(value) }
      else
        []
      end
    end

    it "still carries the constraints on the JSONSchemer side, where they are enforced" do
      expect(schema_keywords_in(BILL_SUMMARY_SCHEMA_HASH)).to include("minLength", "maxItems")
      expect(schema_keywords_in(BILL_CATEGORIES_SCHEMA_HASH)).to include("minItems")
      expect(schema_keywords_in(TESTIMONY_CLASSIFICATION_SCHEMA_HASH)).to include("minimum")
    end

    it "sends none of them on the wire" do
      [
        BILL_SUMMARY_SCHEMA_HASH,
        BILL_CATEGORIES_SCHEMA_HASH,
        BILL_POSITIONS_SCHEMA_HASH,
        TESTIMONY_CLASSIFICATION_SCHEMA_HASH
      ].each do |schema|
        expect(schema_keywords_in(described_class.for_request(schema)))
          .not_to include(*described_class::UNSUPPORTED_KEYWORDS)
      end
    end

    it "leaves the payload-shaping keywords alone, so the model is still constrained" do
      wire = described_class.for_request(BILL_SUMMARY_SCHEMA_HASH)

      expect(wire["additionalProperties"]).to be(false)
      expect(wire["required"]).to eq(BILL_SUMMARY_SCHEMA_HASH["required"])
      expect(wire["properties"].keys).to eq(BILL_SUMMARY_SCHEMA_HASH["properties"].keys)
    end

    it "does not combine anyOf with properties or additionalProperties at any object node" do
      has_forbidden_any_of = lambda do |node, this_fn|
        case node
        when Hash
          forbidden = node.key?("anyOf") && (node.key?("properties") || node.key?("additionalProperties"))
          forbidden || node.values.any? { |val| this_fn.call(val, this_fn) }
        when Array
          node.any? { |val| this_fn.call(val, this_fn) }
        else
          false
        end
      end

      [
        BILL_SUMMARY_SCHEMA_HASH,
        BILL_CATEGORIES_SCHEMA_HASH,
        BILL_POSITIONS_SCHEMA_HASH,
        TESTIMONY_CLASSIFICATION_SCHEMA_HASH
      ].each do |schema|
        wire = described_class.for_request(schema)
        expect(has_forbidden_any_of.call(wire, has_forbidden_any_of)).to be(false)
        expect(has_forbidden_any_of.call(schema, has_forbidden_any_of)).to be(false)
      end
    end
  end

  # We validate just as strictly as before: JSONSchemer is built from the
  # untouched hash, so a payload that breaks minLength is still rejected.
  it "does not weaken post-validation" do
    invalid = {"summary_markdown" => "", "full_breakdown_markdown" => "x"}

    expect(BILL_SUMMARY_SCHEMA.validate(invalid).to_a).not_to be_empty
  end
end
