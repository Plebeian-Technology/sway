# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BILL_SUMMARY_SCHEMA" do
  # @lat: [[bill-llm-schema-validation-design#Why the schemas are read once at boot and never frozen]]
  it "is a JSONSchemer::Schema instance loaded at boot" do
    expect(BILL_SUMMARY_SCHEMA).to be_a(JSONSchemer::Schema)
  end

  it "accepts a minimal valid payload" do
    payload = {
      "summary_markdown" => "A short summary.",
      "draft_org_positions" => [] #: Array[Hash[String, String]]
    }
    expect(BILL_SUMMARY_SCHEMA.valid?(payload)).to be(true)
  end

  it "accepts a payload with the optional full_breakdown_markdown" do
    payload = {
      "summary_markdown" => "A short summary.",
      "full_breakdown_markdown" => "Section by section.",
      "draft_org_positions" => [
        {"org_name" => "ACLU", "stance" => "support", "summary" => "Protects rights."}
      ]
    }
    expect(BILL_SUMMARY_SCHEMA.valid?(payload)).to be(true)
  end

  # @lat: [[bill-llm-schema-validation-design#Why the positions schema is split from the summary schema]]
  it "accepts a payload WITHOUT draft_org_positions and WITHOUT cited_section_keys" do
    payload = {"summary_markdown" => "A short summary."}
    expect(BILL_SUMMARY_SCHEMA.valid?(payload)).to be(true)
  end

  # cited_section_keys is optional. It names the bill sections the summary
  # leaned on, so a claim can be traced back to the text it came from.
  it "accepts a payload WITH cited_section_keys" do
    payload = {
      "summary_markdown" => "A short summary.",
      "cited_section_keys" => ["art_14__sec_301"]
    }
    expect(BILL_SUMMARY_SCHEMA.valid?(payload)).to be(true)
  end

  it "accepts a payload that still nests draft_org_positions (paste_summary back-compat, RESEARCH Pitfall 4)" do
    payload = {
      "summary_markdown" => "A short summary.",
      "draft_org_positions" => [
        {"org_name" => "ACLU", "stance" => "support", "summary" => "Protects rights."}
      ],
      "cited_section_keys" => ["art_14__sec_301"]
    }
    expect(BILL_SUMMARY_SCHEMA.valid?(payload)).to be(true)
  end

  it "rejects a payload with cited_section_keys entries of the wrong type" do
    payload = {
      "summary_markdown" => "A short summary.",
      "cited_section_keys" => [1, 2] #: Array[Integer]
    }
    errors = BILL_SUMMARY_SCHEMA.validate(payload).to_a
    pointers = errors.pluck("data_pointer")
    expect(pointers).to include("/cited_section_keys/0")
  end

  it "rejects an empty object reporting summary_markdown as the ONLY missing required key" do
    errors = BILL_SUMMARY_SCHEMA.validate({}).to_a
    pointers = errors.pluck("data_pointer")
    expect(pointers).to include("")
    # json_schemer points a "missing required key" error at the parent object
    # (an empty pointer, ""); the error details say which key is missing.
    missing_details = errors.pluck("details").compact
    missing_keys = missing_details.flat_map { |d| Array(d["missing_keys"]) }
    expect(missing_keys).to include("summary_markdown")
    # Pin the loosened rule: draft_org_positions is optional now, so it must
    # never be reported as missing.
    expect(missing_keys).not_to include("draft_org_positions")
  end

  it "rejects an org position with a stance outside the enum" do
    payload = {
      "summary_markdown" => "Summary.",
      "draft_org_positions" => [
        {"org_name" => "X", "stance" => "wrong", "summary" => "..."}
      ]
    }
    errors = BILL_SUMMARY_SCHEMA.validate(payload).to_a
    enum_error = errors.find { |e| e["data_pointer"] == "/draft_org_positions/0/stance" }
    expect(enum_error).not_to be_nil
    expect(enum_error&.[]("type")).to eq("enum")
  end

  it "rejects a payload missing required org_name on an org position" do
    payload = {
      "summary_markdown" => "Summary.",
      "draft_org_positions" => [
        {"stance" => "support", "summary" => "..."}
      ]
    }
    errors = BILL_SUMMARY_SCHEMA.validate(payload).to_a
    pointers = errors.pluck("data_pointer")
    expect(pointers).to include("/draft_org_positions/0")
  end

  it "rejects a payload missing required stance on an org position" do
    payload = {
      "summary_markdown" => "Summary.",
      "draft_org_positions" => [
        {"org_name" => "ACLU", "summary" => "..."}
      ]
    }
    errors = BILL_SUMMARY_SCHEMA.validate(payload).to_a
    pointers = errors.pluck("data_pointer")
    expect(pointers).to include("/draft_org_positions/0")
  end
end

# The shape for a positions-only payload (the half built from testimony) used
# to live inside BILL_SUMMARY_SCHEMA. It now has its own schema file in the
# repo, loaded at boot by config/initializers/bill_positions_schema.rb, the
# same way bill_categories_schema.rb works.
RSpec.describe "BILL_POSITIONS_SCHEMA" do
  it "is a JSONSchemer::Schema instance loaded at boot" do
    expect(BILL_POSITIONS_SCHEMA).to be_a(JSONSchemer::Schema)
  end

  it "accepts a well-formed positions payload" do
    payload = {
      "draft_org_positions" => [
        {"org_name" => "ACLU", "stance" => "support", "summary" => "Protects rights."}
      ]
    }
    expect(BILL_POSITIONS_SCHEMA.valid?(payload)).to be(true)
  end

  it "rejects an unknown top-level key" do
    payload = {
      "draft_org_positions" => [], #: Array[untyped]
      "extra_key" => "nope"
    }
    expect(BILL_POSITIONS_SCHEMA.valid?(payload)).to be(false)
  end

  it "rejects an unknown key inside an org position item" do
    payload = {
      "draft_org_positions" => [
        {"org_name" => "ACLU", "stance" => "support", "summary" => "x", "extra_key" => "nope"}
      ]
    }
    expect(BILL_POSITIONS_SCHEMA.valid?(payload)).to be(false)
  end

  it "rejects a stance outside the enum" do
    payload = {
      "draft_org_positions" => [
        {"org_name" => "X", "stance" => "wrong", "summary" => "..."}
      ]
    }
    errors = BILL_POSITIONS_SCHEMA.validate(payload).to_a
    enum_error = errors.find { |e| e["data_pointer"] == "/draft_org_positions/0/stance" }
    expect(enum_error).not_to be_nil
    expect(enum_error&.[]("type")).to eq("enum")
  end

  it "rejects a payload missing draft_org_positions" do
    errors = BILL_POSITIONS_SCHEMA.validate({}).to_a
    missing_details = errors.pluck("details").compact
    missing_keys = missing_details.flat_map { |d| Array(d["missing_keys"]) }
    expect(missing_keys).to include("draft_org_positions")
  end

  it "rejects a payload missing required stance on an org position" do
    payload = {
      "draft_org_positions" => [
        {"org_name" => "ACLU", "summary" => "..."}
      ]
    }
    errors = BILL_POSITIONS_SCHEMA.validate(payload).to_a
    pointers = errors.pluck("data_pointer")
    expect(pointers).to include("/draft_org_positions/0")
  end

  # @lat: [[bill-llm-schema-validation-design#Why bill_positions.json's bounds are tested for drift against bill_summary.json]]
  describe "the bounds on the model's answer" do
    # Named with the file's prefix convention rather than `positions` /
    # `entry`: these are declared on Object for Steep, and a generic name there
    # makes every call of that name in the whole test target resolve to this
    # one (the C-WR-06 lesson, recorded in sig-test/object_spec_methods.rbs).
    def positions_body(entries)
      {"draft_org_positions" => entries}
    end

    def positions_entry(org_name: "ACLU", summary: "Protects rights.")
      {"org_name" => org_name, "stance" => "support", "summary" => summary}
    end

    it "accepts a list at the cap" do
      payload = positions_body(Array.new(50) { positions_entry })

      expect(BILL_POSITIONS_SCHEMA.valid?(payload)).to be(true)
    end

    it "rejects a list past the cap" do
      errors = BILL_POSITIONS_SCHEMA.validate(positions_body(Array.new(51) { positions_entry })).to_a

      expect(errors.pluck("type")).to include("maxItems")
    end

    it "rejects an organization name past its bound" do
      payload = positions_body([positions_entry(org_name: "a" * 201)])
      errors = BILL_POSITIONS_SCHEMA.validate(payload).to_a
      name_error = errors.find { |e| e["data_pointer"] == "/draft_org_positions/0/org_name" }

      expect(name_error&.[]("type")).to eq("maxLength")
    end

    it "rejects a rationale past its bound" do
      payload = positions_body([positions_entry(summary: "a" * 1001)])
      errors = BILL_POSITIONS_SCHEMA.validate(payload).to_a
      summary_error = errors.find { |e| e["data_pointer"] == "/draft_org_positions/0/summary" }

      expect(summary_error&.[]("type")).to eq("maxLength")
    end

    # An entry naming nobody is the shape that draws a card with a blank
    # heading and an Approve button, so it is refused rather than stored.
    it "rejects an empty organization name" do
      payload = positions_body([positions_entry(org_name: "")])

      expect(BILL_POSITIONS_SCHEMA.valid?(payload)).to be(false)
    end

    it "rejects an empty rationale" do
      payload = positions_body([positions_entry(summary: "")])

      expect(BILL_POSITIONS_SCHEMA.valid?(payload)).to be(false)
    end

    # @lat: [[bill-llm-schema-validation-design#Why bill_positions.json's bounds are tested for drift against bill_summary.json]]
    it "applies the same bounds on the paste contract" do
      body = {"summary_markdown" => "A summary."}
      at_cap = positions_body(Array.new(50) { positions_entry })
      past_cap = positions_body(Array.new(51) { positions_entry })
      long_name = positions_body([positions_entry(org_name: "a" * 201)])
      long_summary = positions_body([positions_entry(summary: "a" * 1001)])
      no_name = positions_body([positions_entry(org_name: "")])

      expect(BILL_SUMMARY_SCHEMA.valid?(body.merge(at_cap))).to be(true)
      expect(BILL_SUMMARY_SCHEMA.valid?(body.merge(past_cap))).to be(false)
      expect(BILL_SUMMARY_SCHEMA.valid?(body.merge(long_name))).to be(false)
      expect(BILL_SUMMARY_SCHEMA.valid?(body.merge(long_summary))).to be(false)
      expect(BILL_SUMMARY_SCHEMA.valid?(body.merge(no_name))).to be(false)
    end

    # @lat: [[bill-llm-schema-validation-design#Why bill_positions.json's bounds are tested for drift against bill_summary.json]]
    it "offers the same stance words on both contracts" do
      stance_enum = lambda do |schema_hash|
        schema_hash
          .fetch("properties")
          .fetch("draft_org_positions")
          .fetch("items")
          .fetch("properties")
          .fetch("stance")
          .fetch("enum")
      end

      expect(stance_enum.call(BILL_SUMMARY_SCHEMA_HASH))
        .to eq(stance_enum.call(BILL_POSITIONS_SCHEMA_HASH))
      # And the list the rest of the app answers from is that same list, not a
      # third copy typed out in Ruby.
      expect(BillLlmProvisioning::DRAFT_POSITIONS)
        .to eq(stance_enum.call(BILL_POSITIONS_SCHEMA_HASH))
    end

    # @lat: [[bill-llm-schema-validation-design#Why bill_positions.json's bounds are tested for drift against bill_summary.json]]
    it "bounds cited_section_keys at what the prompt can offer" do
      body = {"summary_markdown" => "A summary."}
      key_cap = BillSummaryPromptBuilder::MAX_CITATION_KEYS
      key_length = BillSummaryPromptBuilder::MAX_METADATA_FIELD_CHARS

      at_cap = {"cited_section_keys" => Array.new(key_cap) { "art-1-s-1" }}
      past_cap = {"cited_section_keys" => Array.new(key_cap + 1) { "art-1-s-1" }}
      long_key = {"cited_section_keys" => ["k" * (key_length + 1)]}

      expect(BILL_SUMMARY_SCHEMA.valid?(body.merge(at_cap))).to be(true)
      expect(BILL_SUMMARY_SCHEMA.validate(body.merge(past_cap)).to_a.pluck("type")).to include("maxItems")
      expect(BILL_SUMMARY_SCHEMA.validate(body.merge(long_key)).to_a.pluck("type")).to include("maxLength")
    end

    it "still refuses an empty citation key, which names no section at all" do
      body = {"summary_markdown" => "A summary.", "cited_section_keys" => [""]}

      expect(BILL_SUMMARY_SCHEMA.valid?(body)).to be(false)
    end

    # @lat: [[bill-llm-schema-validation-design#Why bill_positions.json's bounds are tested for drift against bill_summary.json]]
    it "bounds a category name at what a Category record can hold" do
      body = {"summary_markdown" => "A summary."}
      long = {"categories" => ["c" * (Category::MAX_NAME_CHARS + 1)]}

      expect(BILL_SUMMARY_SCHEMA.validate(body.merge(long)).to_a.pluck("type")).to include("maxLength")
      expect(BILL_CATEGORIES_SCHEMA.validate(long).to_a.pluck("type")).to include("maxLength")
      expect(BILL_CATEGORIES_SCHEMA.valid?({"categories" => ["c" * Category::MAX_NAME_CHARS]})).to be(true)
    end

    # cited_news_urls is optional and bounded by 5 items, max 1000 chars each
    it "accepts a payload with valid cited_news_urls" do
      payload = {
        "summary_markdown" => "A summary.",
        "cited_news_urls" => [
          "https://www.thebaltimorebanner.com/article-1",
          "https://baltimorefishbowl.com/article-2"
        ]
      }
      expect(BILL_SUMMARY_SCHEMA.valid?(payload)).to be(true)
    end

    it "bounds cited_news_urls at 5 items and 1000 chars per url" do
      body = {"summary_markdown" => "A summary."}
      at_cap = {"cited_news_urls" => Array.new(5) { |i| "https://news.example.com/story/#{i}" }}
      past_cap = {"cited_news_urls" => Array.new(6) { |i| "https://news.example.com/story/#{i}" }}
      long_url = {"cited_news_urls" => ["https://news.example.com/#{"a" * 1000}"]}

      expect(BILL_SUMMARY_SCHEMA.valid?(body.merge(at_cap))).to be(true)
      expect(BILL_SUMMARY_SCHEMA.validate(body.merge(past_cap)).to_a.pluck("type")).to include("maxItems")
      expect(BILL_SUMMARY_SCHEMA.validate(body.merge(long_url)).to_a.pluck("type")).to include("maxLength")
    end

    it "rejects non-string entries in cited_news_urls" do
      body = {"summary_markdown" => "A summary.", "cited_news_urls" => [123]}
      expect(BILL_SUMMARY_SCHEMA.valid?(body)).to be(false)
    end

    # @lat: [[bill-llm-schema-validation-design#Why bill_positions.json's bounds are tested for drift against bill_summary.json]]
    describe "news source attribution on draft_org_positions" do
      it "accepts a draft position with complete news source attribution" do
        valid_news_entry = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant protections as vital civil rights.",
          "bill_news_article_id" => 42,
          "text_version_id" => 10,
          "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing.",
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        payload = {"draft_org_positions" => [valid_news_entry]}

        expect(BILL_POSITIONS_SCHEMA.valid?(payload)).to be(true)
        expect(BILL_SUMMARY_SCHEMA.valid?(payload.merge("summary_markdown" => "Summary."))).to be(true)
      end

      it "accepts null speaker_name and speaker_role for official organizational statements" do
        entry = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant protections as vital civil rights.",
          "bill_news_article_id" => 42,
          "text_version_id" => 10,
          "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing.",
          "speaker_name" => nil,
          "speaker_role" => nil
        }
        payload = {"draft_org_positions" => [entry]}

        expect(BILL_POSITIONS_SCHEMA.valid?(payload)).to be(true)
      end

      it "accepts a news draft omitting speaker_name and speaker_role entirely" do
        entry = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant protections as vital civil rights.",
          "bill_news_article_id" => 42,
          "text_version_id" => 10,
          "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing."
        }
        payload = {"draft_org_positions" => [entry]}

        expect(BILL_POSITIONS_SCHEMA.valid?(payload)).to be(true)
      end

      it "accepts evidence_excerpt at the 1000 character boundary" do
        entry = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant protections as vital civil rights.",
          "bill_news_article_id" => 42,
          "text_version_id" => 10,
          "evidence_excerpt" => "a" * 1000,
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        payload = {"draft_org_positions" => [entry]}

        expect(BILL_POSITIONS_SCHEMA.valid?(payload)).to be(true)
      end

      it "rejects evidence_excerpt exceeding 1000 characters" do
        entry = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant protections as vital civil rights.",
          "bill_news_article_id" => 42,
          "text_version_id" => 10,
          "evidence_excerpt" => "a" * 1001,
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        payload = {"draft_org_positions" => [entry]}
        errors = BILL_POSITIONS_SCHEMA.validate(payload).to_a
        excerpt_error = errors.find { |e| e["data_pointer"] == "/draft_org_positions/0/evidence_excerpt" }

        expect(excerpt_error&.[]("type")).to eq("maxLength")
      end

      it "rejects an empty evidence_excerpt" do
        entry = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant protections as vital civil rights.",
          "bill_news_article_id" => 42,
          "text_version_id" => 10,
          "evidence_excerpt" => "",
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        payload = {"draft_org_positions" => [entry]}
        errors = BILL_POSITIONS_SCHEMA.validate(payload).to_a
        excerpt_error = errors.find { |e| e["data_pointer"] == "/draft_org_positions/0/evidence_excerpt" }

        expect(excerpt_error&.[]("type")).to eq("minLength")
      end

      it "rejects non-integer bill_news_article_id or text_version_id" do
        entry = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant protections as vital civil rights.",
          "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing.",
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director"
        }
        string_article = entry.merge("bill_news_article_id" => "42", "text_version_id" => 10)
        string_version = entry.merge("bill_news_article_id" => 42, "text_version_id" => "10")

        expect(BILL_POSITIONS_SCHEMA.valid?({"draft_org_positions" => [string_article]})).to be(false)
        expect(BILL_POSITIONS_SCHEMA.valid?({"draft_org_positions" => [string_version]})).to be(false)
      end

      it "rejects speaker_name or speaker_role exceeding 200 characters" do
        entry = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant protections as vital civil rights.",
          "bill_news_article_id" => 42,
          "text_version_id" => 10,
          "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing."
        }
        long_name = entry.merge("speaker_name" => "a" * 201, "speaker_role" => "Director")
        long_role = entry.merge("speaker_name" => "Jane Doe", "speaker_role" => "a" * 201)

        errors_name = BILL_POSITIONS_SCHEMA.validate({"draft_org_positions" => [long_name]}).to_a
        errors_role = BILL_POSITIONS_SCHEMA.validate({"draft_org_positions" => [long_role]}).to_a

        expect(errors_name.find { |e| e["data_pointer"] == "/draft_org_positions/0/speaker_name" }&.[]("type")).to eq("maxLength")
        expect(errors_role.find { |e| e["data_pointer"] == "/draft_org_positions/0/speaker_role" }&.[]("type")).to eq("maxLength")
      end

      it "rejects non-string non-null values for speaker_name and speaker_role" do
        entry = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant protections as vital civil rights.",
          "bill_news_article_id" => 42,
          "text_version_id" => 10,
          "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing."
        }
        int_name = entry.merge("speaker_name" => 123, "speaker_role" => "Director")
        int_role = entry.merge("speaker_name" => "Jane Doe", "speaker_role" => 123)

        expect(BILL_POSITIONS_SCHEMA.valid?({"draft_org_positions" => [int_name]})).to be(false)
        expect(BILL_POSITIONS_SCHEMA.valid?({"draft_org_positions" => [int_role]})).to be(false)
      end

      it "rejects unrecognized properties on news-attributed draft positions" do
        entry = {
          "org_name" => "ACLU of Maryland",
          "stance" => "support",
          "summary" => "Supports tenant protections as vital civil rights.",
          "bill_news_article_id" => 42,
          "text_version_id" => 10,
          "evidence_excerpt" => "We strongly support this legislation to safeguard fair housing.",
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director",
          "source_url" => "https://example.com/story"
        }
        payload = {"draft_org_positions" => [entry]}
        errors = BILL_POSITIONS_SCHEMA.validate(payload).to_a
        disallowed = errors.find { |e| e["data_pointer"] == "/draft_org_positions/0/source_url" }

        expect(disallowed&.[]("type")).to eq("schema")
        expect(disallowed&.[]("schema_pointer")).to eq("/properties/draft_org_positions/items/additionalProperties")
      end

      it "enforces identical news attribution property definitions on both schema contracts" do
        extract_props = lambda do |schema_hash|
          schema_hash
            .fetch("properties")
            .fetch("draft_org_positions")
            .fetch("items")
            .fetch("properties")
            .slice("bill_news_article_id", "text_version_id", "evidence_excerpt", "speaker_name", "speaker_role")
        end

        expect(extract_props.call(BILL_SUMMARY_SCHEMA_HASH))
          .to eq(extract_props.call(BILL_POSITIONS_SCHEMA_HASH))

        expected_definitions = {
          "bill_news_article_id" => {"type" => "integer"},
          "text_version_id" => {"type" => "integer"},
          "evidence_excerpt" => {"type" => "string", "minLength" => 1, "maxLength" => 1000},
          "speaker_name" => {"type" => ["string", "null"], "maxLength" => 200},
          "speaker_role" => {"type" => ["string", "null"], "maxLength" => 200}
        }
        expect(extract_props.call(BILL_POSITIONS_SCHEMA_HASH)).to eq(expected_definitions)
      end
    end
  end
end
