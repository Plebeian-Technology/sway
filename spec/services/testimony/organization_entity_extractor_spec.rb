# frozen_string_literal: true

require "rails_helper"

RSpec.describe Testimony::OrganizationEntityExtractor do
  def make_letter(
    position: 0,
    text: "Test letter body",
    offset: 0,
    characters: nil,
    source_kind: "named_organization",
    repeat: false,
    source_evidence: nil
  )
    {
      "position" => position,
      "character_offset" => offset,
      "characters" => characters || text.length,
      "text" => text,
      "source_kind" => source_kind,
      "repeat" => repeat,
      "source_evidence" => source_evidence
    }
  end

  let(:mock_adapter) do
    instance_double(Llm::OpenRouterAdapter, provider_label: "openrouter")
  end

  let(:extraction_route) do
    Llm::RouteResolver::Route.new(
      provider: :openrouter,
      api_model: "scaledown/extract",
      reasoning_effort: nil,
      mode: :extraction
    )
  end

  describe ".build" do
    it "returns an extractor with llm: nil in test environment by default" do
      extractor = described_class.build
      expect(extractor.send(:llm)).to be_nil

      letter = make_letter(
        position: 0,
        text: "We represent Greater Baltimore Tech Coalition.",
        source_evidence: {"org_name" => "Greater Baltimore Tech Coalition"}
      )
      augmented, counts = extractor.call(text: letter["text"], letters: [letter])

      expect(augmented.first["extracted_org"]).to eq({
        "org_name" => "Greater Baltimore Tech Coalition",
        "summary" => nil
      })
      expect(counts).to eq({
        "org_entity_extracted_letters" => 1,
        "org_entity_extraction_fallbacks" => 0
      })
    end

    it "accepts a custom llm adapter" do
      extractor = described_class.build(llm: mock_adapter)
      expect(extractor.send(:llm)).to eq(mock_adapter)
    end

    it "resolves extraction route when not in test env" do
      allow(Rails.env).to receive(:test?).and_return(false)
      allow(Llm::RouteResolver).to receive(:resolve).with(purpose: :extraction).and_return(extraction_route)
      allow(Llm::Client).to receive(:build).with(provider: "openrouter").and_return(mock_adapter)

      extractor = described_class.build
      expect(extractor.send(:llm)).to eq(mock_adapter)
      expect(extractor.send(:model_for, mock_adapter)).to eq("scaledown/extract")
    end

    it "rescues adapter build failure, logs warning, and returns disabled extractor" do
      allow(Rails.env).to receive(:test?).and_return(false)
      allow(Llm::RouteResolver).to receive(:resolve).and_raise(StandardError.new("catalog unreachable"))
      allow(SwayLogging).to receive(:warn)

      extractor = described_class.build
      expect(extractor.send(:llm)).to be_nil
      expect(SwayLogging).to have_received(:warn).with(
        "organization_entity_extractor.adapter_unavailable",
        hash_including(error_class: "StandardError")
      )
    end
  end

  describe "#call" do
    it "returns empty array and zero counts when letters is empty" do
      extractor = described_class.new(llm: nil)
      augmented, counts = extractor.call(text: "", letters: [])

      expect(augmented).to eq([])
      expect(counts).to eq({
        "org_entity_extracted_letters" => 0,
        "org_entity_extraction_fallbacks" => 0
      })
    end

    it "skips repeat letters and sets extracted_org to nil with zero adapter calls" do
      extractor = described_class.new(llm: mock_adapter, route: extraction_route)
      allow(mock_adapter).to receive(:respond_to?).with(:generate_entity_extraction).and_return(true)
      expect(mock_adapter).not_to receive(:generate_entity_extraction)

      letter = make_letter(
        position: 0,
        text: "Downtown Merchants Association letter",
        repeat: true,
        source_evidence: {"org_name" => "Downtown Merchants Association"}
      )

      augmented, counts = extractor.call(text: letter["text"], letters: [letter])

      expect(augmented.first["extracted_org"]).to be_nil
      expect(counts).to eq({
        "org_entity_extracted_letters" => 0,
        "org_entity_extraction_fallbacks" => 0
      })
    end

    it "skips constituent self-letters and sets extracted_org to nil with zero adapter calls" do
      extractor = described_class.new(llm: mock_adapter, route: extraction_route)
      allow(mock_adapter).to receive(:respond_to?).with(:generate_entity_extraction).and_return(true)
      expect(mock_adapter).not_to receive(:generate_entity_extraction)

      letter = make_letter(
        position: 0,
        text: "I am a resident writing on my own behalf.",
        source_kind: "person_speaking_for_self",
        repeat: false
      )

      augmented, counts = extractor.call(text: letter["text"], letters: [letter])

      expect(augmented.first["extracted_org"]).to be_nil
      expect(counts).to eq({
        "org_entity_extracted_letters" => 0,
        "org_entity_extraction_fallbacks" => 0
      })
    end

    it "extracts org_name and summary for nameable letters when adapter returns top-level hash" do
      letter_text = "From: director@bmorechamber.org\nSubject: Support Bill 24-001\n\nWe at the Baltimore Chamber of Commerce urge support for this bill to spur local retail growth."
      letter = make_letter(
        position: 0,
        text: letter_text,
        source_kind: "named_organization",
        repeat: false
      )

      allow(mock_adapter).to receive(:respond_to?).with(:generate_entity_extraction).and_return(true)
      expect(mock_adapter).to receive(:generate_entity_extraction).with(
        model: "scaledown/extract",
        content: "We at the Baltimore Chamber of Commerce urge support for this bill to spur local retail growth.",
        entities: described_class::EXTRACTION_ENTITIES
      ).and_return({
        "org_name" => "Baltimore Chamber of Commerce",
        "summary" => "Urges support for the bill to spur local retail growth."
      })

      extractor = described_class.new(llm: mock_adapter, route: extraction_route)
      augmented, counts = extractor.call(text: letter_text, letters: [letter])

      expect(augmented.first["extracted_org"]).to eq({
        "org_name" => "Baltimore Chamber of Commerce",
        "summary" => "Urges support for the bill to spur local retail growth."
      })
      expect(counts).to eq({
        "org_entity_extracted_letters" => 1,
        "org_entity_extraction_fallbacks" => 0
      })
    end

    it "unwraps nested entities hash and handles symbol keys" do
      letter_text = "On behalf of Citizens for Clean Transit, we oppose the funding reallocation."
      letter = make_letter(
        position: 1,
        text: letter_text,
        source_kind: "person_speaking_for_org",
        repeat: false
      )

      allow(mock_adapter).to receive(:respond_to?).with(:generate_entity_extraction).and_return(true)
      expect(mock_adapter).to receive(:generate_entity_extraction).and_return({
        entities: {
          org_name: "Citizens for Clean Transit",
          summary: "Opposes the funding reallocation."
        }
      })

      extractor = described_class.new(llm: mock_adapter, route: extraction_route)
      augmented, counts = extractor.call(text: letter_text, letters: [letter])

      expect(augmented.first["extracted_org"]).to eq({
        "org_name" => "Citizens for Clean Transit",
        "summary" => "Opposes the funding reallocation."
      })
      expect(counts["org_entity_extracted_letters"]).to eq(1)
      expect(counts["org_entity_extraction_fallbacks"]).to eq(0)
    end

    it "sets summary to nil when summary is empty or whitespace" do
      letter_text = "Baltimore Planning Department reports the zoning analysis."
      letter = make_letter(
        position: 2,
        text: letter_text,
        source_kind: "public_body",
        repeat: false
      )

      allow(mock_adapter).to receive(:respond_to?).with(:generate_entity_extraction).and_return(true)
      expect(mock_adapter).to receive(:generate_entity_extraction).and_return({
        "org_name" => "Baltimore Planning Department",
        "summary" => "   "
      })

      extractor = described_class.new(llm: mock_adapter, route: extraction_route)
      augmented, counts = extractor.call(text: letter_text, letters: [letter])

      expect(augmented.first["extracted_org"]).to eq({
        "org_name" => "Baltimore Planning Department",
        "summary" => nil
      })
      expect(counts["org_entity_extracted_letters"]).to eq(1)
      expect(counts["org_entity_extraction_fallbacks"]).to eq(0)
    end

    it "windows letters exceeding 6,000 characters to 4,500 head + notice + 1,500 tail" do
      head_marker = "START_OF_ORGANIZATION_LETTER"
      tail_marker = "END_OF_ORGANIZATION_LETTER"
      long_body = "#{head_marker} #{"A" * 5_000} MIDDLE #{"B" * 2_000} #{tail_marker}"
      letter = make_letter(
        position: 0,
        text: long_body,
        source_kind: "named_organization"
      )

      allow(mock_adapter).to receive(:respond_to?).with(:generate_entity_extraction).and_return(true)
      expect(mock_adapter).to receive(:generate_entity_extraction) do |kwargs|
        content = kwargs[:content]
        expect(content.length).to be < long_body.length
        expect(content).to start_with(head_marker)
        expect(content).to end_with(tail_marker)
        expect(content).to include("\n[...middle of letter omitted for length...]\n")
        {
          "org_name" => "Test Organization",
          "summary" => "Summary of long letter."
        }
      end

      extractor = described_class.new(llm: mock_adapter, route: extraction_route)
      augmented, counts = extractor.call(text: long_body, letters: [letter])

      expect(augmented.first["extracted_org"]["org_name"]).to eq("Test Organization")
      expect(counts["org_entity_extracted_letters"]).to eq(1)
    end

    it "falls back to source_evidence org_name and increments fallbacks when adapter raises" do
      letter_text = "Letter content for failing adapter."
      letter = make_letter(
        position: 0,
        text: letter_text,
        source_kind: "person_speaking_for_org",
        source_evidence: {"org_name" => "Fallback Alliance"}
      )

      allow(mock_adapter).to receive(:respond_to?).with(:generate_entity_extraction).and_return(true)
      allow(mock_adapter).to receive(:generate_entity_extraction).and_raise(
        Llm::TransportError.new("OpenRouter connection timed out")
      )
      allow(SwayLogging).to receive(:warn)

      extractor = described_class.new(llm: mock_adapter, route: extraction_route)
      augmented, counts = extractor.call(text: letter_text, letters: [letter])

      expect(augmented.first["extracted_org"]).to eq({
        "org_name" => "Fallback Alliance",
        "summary" => nil
      })
      expect(counts).to eq({
        "org_entity_extracted_letters" => 1,
        "org_entity_extraction_fallbacks" => 1
      })
      expect(SwayLogging).to have_received(:warn).with(
        "organization_entity_extractor.llm_failure",
        hash_including(error_class: "Llm::TransportError")
      )
    end

    it "falls back and increments fallbacks when adapter returns blank org_name" do
      letter_text = "Letter content where extraction fails to identify org."
      letter = make_letter(
        position: 0,
        text: letter_text,
        source_kind: "named_organization",
        source_evidence: nil
      )

      allow(mock_adapter).to receive(:respond_to?).with(:generate_entity_extraction).and_return(true)
      allow(mock_adapter).to receive(:generate_entity_extraction).and_return({
        "org_name" => "   ",
        "summary" => "Some summary without org"
      })
      allow(SwayLogging).to receive(:warn)

      extractor = described_class.new(llm: mock_adapter, route: extraction_route)
      augmented, counts = extractor.call(text: letter_text, letters: [letter])

      expect(augmented.first["extracted_org"]).to be_nil
      expect(counts).to eq({
        "org_entity_extracted_letters" => 0,
        "org_entity_extraction_fallbacks" => 1
      })
      expect(SwayLogging).to have_received(:warn).with(
        "organization_entity_extractor.llm_failure",
        hash_including(error_class: "BlankOrgName")
      )
    end

    it "falls back and increments fallbacks when letter body is blank after envelope stripping" do
      raw_text = "From: sender@example.com\nTo: council@baltimorecity.gov\nSubject: Empty\n\n   \n"
      letter = make_letter(
        position: 0,
        text: raw_text,
        source_kind: "named_organization",
        source_evidence: {"org_name" => "Empty Letter Org"}
      )

      extractor = described_class.new(llm: mock_adapter, route: extraction_route)
      allow(mock_adapter).to receive(:respond_to?).with(:generate_entity_extraction).and_return(true)
      expect(mock_adapter).not_to receive(:generate_entity_extraction)

      augmented, counts = extractor.call(text: raw_text, letters: [letter])

      expect(augmented.first["extracted_org"]).to eq({
        "org_name" => "Empty Letter Org",
        "summary" => nil
      })
      expect(counts).to eq({
        "org_entity_extracted_letters" => 1,
        "org_entity_extraction_fallbacks" => 1
      })
    end

    it "falls back and increments fallbacks when adapter does not support entity extraction" do
      claude_adapter = instance_double(Llm::ClaudeAdapter, provider_label: "claude")

      letter = make_letter(
        position: 0,
        text: "Letter text for unsupported adapter.",
        source_kind: "named_organization",
        source_evidence: {"org_name" => "Claude Fallback Org"}
      )

      extractor = described_class.new(llm: claude_adapter, enabled: true)
      augmented, counts = extractor.call(text: letter["text"], letters: [letter])

      expect(augmented.first["extracted_org"]).to eq({
        "org_name" => "Claude Fallback Org",
        "summary" => nil
      })
      expect(counts).to eq({
        "org_entity_extracted_letters" => 1,
        "org_entity_extraction_fallbacks" => 1
      })
    end

    it "in disabled mode populates fallback from source_evidence without stripping letter text or incrementing fallbacks" do
      letter = make_letter(
        position: 0,
        text: "Disabled mode letter text.",
        source_kind: "named_organization",
        source_evidence: {"org_name" => "Static Source Org"}
      )

      expect(Testimony::ExtractedText).not_to receive(:strip_envelope)
      extractor = described_class.new(llm: nil)
      augmented, counts = extractor.call(text: letter["text"], letters: [letter])

      expect(augmented.first["extracted_org"]).to eq({
        "org_name" => "Static Source Org",
        "summary" => nil
      })
      expect(counts).to eq({
        "org_entity_extracted_letters" => 1,
        "org_entity_extraction_fallbacks" => 0
      })
    end
  end
end
