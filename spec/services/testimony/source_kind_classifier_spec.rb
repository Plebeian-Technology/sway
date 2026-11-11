# frozen_string_literal: true

require "rails_helper"

# The model-backed half of the kind-of-source
# guard. Mirrors Testimony::AttachmentClassifier — rules first, a model only
# for the tail the rules cannot confidently settle on their own, and a
# classifier with no model connection under test so the suite never reaches
# for llama.cpp.
RSpec.describe Testimony::SourceKindClassifier do
  def kind_letter(position, text, offset:, sender_address: nil, sender_domain: nil)
    {
      "position" => position,
      "character_offset" => offset,
      "characters" => text.length,
      "sender_address" => sender_address,
      "sender_domain" => sender_domain
    }
  end

  describe ".build" do
    it "returns a classifier with no model connection in test" do
      classifier = described_class.build

      full_text = "From: a@example.com\nI am the President of the Downtown Merchants Association.\n"
      letters = [kind_letter(0, full_text, offset: 0, sender_address: "a@example.com", sender_domain: "example.com")]

      augmented, = classifier.call(text: full_text, letters: letters)

      # No model to confirm the tail kind, so it falls back to the safe kind.
      expect(augmented.first["source_kind"]).to eq("person_speaking_for_self")
    end
  end

  describe "#call" do
    it "derives the kinds the model is asked about by subtracting the rule-decided kinds" do
      expect(described_class::MODEL_PASS_KINDS).to eq(
        Testimony::SourceKindRules::KINDS - described_class::RULE_DECIDED_KINDS
      )
      expect(described_class::MODEL_PASS_KINDS).to match_array(%i[named_organization person_speaking_for_org])
    end

    it "writes a source_kind onto every letter, drawn from the four-value list" do
      classifier = described_class.new(llm: nil)
      texts = [
        "From: a@example.com\nOn behalf of the Department of Transportation, we object.\n",
        "From: b@example.com\nAlex Example\n100 Example Street\nBaltimore, MD 21201\n"
      ]
      full_text = texts.join("\n----\n")
      offset_0 = 0
      # @lat: [[rbs-signatures#Why a provably-safe value still needs a guard]]
      offset_1 = full_text.index(texts[1]) || raise("texts[1] not found in full_text")
      letters = [
        kind_letter(0, texts[0], offset: offset_0, sender_address: "a@example.com", sender_domain: "baltimorecity.gov"),
        kind_letter(1, texts[1], offset: offset_1, sender_address: "b@example.com", sender_domain: "gmail.com")
      ]

      augmented, = classifier.call(text: full_text, letters: letters)

      expect(augmented.pluck("source_kind")).to eq(%w[public_body person_speaking_for_self])
      expect(Testimony::SourceKindRules::KINDS.map(&:to_s)).to include(*augmented.pluck("source_kind"))
    end

    it "classifying the same letter twice gives the same kind" do
      classifier = described_class.new(llm: nil)
      text = "From: a@example.com\nJust a resident who cares about this.\n"
      letters = [kind_letter(0, text, offset: 0, sender_address: "a@example.com", sender_domain: "gmail.com")]

      first, = classifier.call(text: text, letters: letters)
      second, = classifier.call(text: text, letters: letters)

      expect(first.first["source_kind"]).to eq(second.first["source_kind"])
    end

    it "leaves every letter carrying its original fields alongside the new ones" do
      classifier = described_class.new(llm: nil)
      text = "From: a@example.com\nJust a resident.\n"
      letters = [kind_letter(0, text, offset: 0, sender_address: "a@example.com", sender_domain: "gmail.com")]

      augmented, = classifier.call(text: text, letters: letters)

      expect(augmented.first).to include("position" => 0, "sender_address" => "a@example.com")
      expect(augmented.first).to have_key("source_evidence")
    end

    it "adds the number of letters of each kind to the returned counts" do
      classifier = described_class.new(llm: nil)
      texts = [
        "From: a@example.com\nOn behalf of the Department of Transportation, we object.\n",
        "From: b@example.com\nAlex Example\n100 Example Street\nBaltimore, MD 21201\n"
      ]
      full_text = texts.join("\n----\n")
      letters = [
        kind_letter(0, texts[0], offset: 0, sender_address: "a@example.com", sender_domain: "baltimorecity.gov"),
        kind_letter(1, texts[1], offset: full_text.index(texts[1]) || raise("texts[1] not found in full_text"), sender_address: "b@example.com", sender_domain: "gmail.com")
      ]

      _augmented, counts = classifier.call(text: full_text, letters: letters)

      expect(counts["public_body_letters"]).to eq(1)
      expect(counts["person_speaking_for_self_letters"]).to eq(1)
      expect(counts["named_organization_letters"]).to eq(0)
      expect(counts["person_speaking_for_org_letters"]).to eq(0)
    end

    it "falls back a MODEL_PASS_KINDS letter to person_speaking_for_self when there is no model connection" do
      classifier = described_class.new(llm: nil)
      text = <<~TEXT
        From: jane@baltimorehousing.org
        I have reviewed this bill closely.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT

      letters = [kind_letter(0, text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org")]

      augmented, = classifier.call(text: text, letters: letters)

      expect(augmented.first["source_kind"]).to eq("person_speaking_for_self")
    end

    it "asks the model for a MODEL_PASS_KINDS letter and applies its answer" do
      adapter = instance_double(Llm::LlamacppAdapter, provider_label: "llamacpp")
      allow(adapter).to receive(:generate_source_kind_classification).and_return(
        {"classifications" => [{"position" => 0, "kind" => "person_speaking_for_org"}]}
      )
      classifier = described_class.new(llm: adapter, enabled: true)

      text = <<~TEXT
        From: jane@baltimorehousing.org
        I have reviewed this bill closely.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT
      letters = [kind_letter(0, text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org")]

      augmented, = classifier.call(text: text, letters: letters)

      expect(augmented.first["source_kind"]).to eq("person_speaking_for_org")
      # @lat: [[testimony-letters#What a letter says about who is speaking]]
      expect(augmented.first["source_evidence"]).to include(
        "role" => "Executive Director", "org_name" => "the Baltimore Housing Coalition"
      )
    end

    it "rejects a model answer that does not match the expected shape and falls back to publishing nothing" do
      adapter = instance_double(Llm::LlamacppAdapter, provider_label: "llamacpp")
      allow(adapter).to receive(:generate_source_kind_classification).and_return({"classifications" => "not an array"})
      classifier = described_class.new(llm: adapter, enabled: true)

      text = <<~TEXT
        From: jane@baltimorehousing.org
        I have reviewed this bill closely.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT
      letters = [kind_letter(0, text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org")]

      augmented, = classifier.call(text: text, letters: letters)

      expect(augmented.first["source_kind"]).to eq("person_speaking_for_self")
    end

    it "rejects a model answer naming a kind outside MODEL_PASS_KINDS and falls back" do
      adapter = instance_double(Llm::LlamacppAdapter, provider_label: "llamacpp")
      allow(adapter).to receive(:generate_source_kind_classification).and_return(
        {"classifications" => [{"position" => 0, "kind" => "public_body"}]}
      )
      classifier = described_class.new(llm: adapter, enabled: true)

      text = <<~TEXT
        From: jane@baltimorehousing.org
        I have reviewed this bill closely.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT
      letters = [kind_letter(0, text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org")]

      augmented, = classifier.call(text: text, letters: letters)

      expect(augmented.first["source_kind"]).to eq("person_speaking_for_self")
    end

    it "falls back gracefully when the model call raises" do
      adapter = instance_double(Llm::LlamacppAdapter, provider_label: "llamacpp")
      allow(adapter).to receive(:generate_source_kind_classification).and_raise(Llm::TransportError, "boom")
      classifier = described_class.new(llm: adapter, enabled: true)

      text = <<~TEXT
        From: jane@baltimorehousing.org
        I have reviewed this bill closely.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT
      letters = [kind_letter(0, text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org")]

      expect { classifier.call(text: text, letters: letters) }.not_to raise_error
      augmented, = classifier.call(text: text, letters: letters)
      expect(augmented.first["source_kind"]).to eq("person_speaking_for_self")
    end

    # WR-04. A failed model pass writes the SAME verdict a confident model
    # pass writes, so a Claude outage during one run is indistinguishable
    # from a real reading afterwards — and every organization's own letter on
    # that bill then trips the private-individual refusal, with nothing on
    # the screen to say why. The artifact has to carry the difference.
    it "counts the letters a failed model call fell back on" do
      adapter = instance_double(Llm::LlamacppAdapter, provider_label: "llamacpp")
      allow(adapter).to receive(:generate_source_kind_classification).and_raise(Llm::TransportError, "boom")
      classifier = described_class.new(llm: adapter, enabled: true)

      text = <<~TEXT
        From: jane@baltimorehousing.org
        I have reviewed this bill closely.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT
      letters = [kind_letter(0, text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org")]

      _, counts = classifier.call(text: text, letters: letters)

      expect(counts["source_kind_model_fallbacks"]).to eq(1)
    end

    # B3. The counter existed so a Claude outage is distinguishable from a
    # confident verdict. It incremented on the two rescue paths inside
    # #model_results and on neither of the two paths that skip the model
    # entirely — which produce the SAME artifact, with the count still
    # reading 0. In production the loud one is a failed Llm::Client.build: a
    # missing key or a changed LLM_PROVIDER rewrites every letter the rules
    # read as an organization's own voice down to a person speaking for
    # themselves, and reports that nothing fell back.
    it "counts the tail letters it fell back on when no model connection was supplied" do
      classifier = described_class.new(llm: nil)

      text = <<~TEXT
        From: jane@baltimorehousing.org
        I have reviewed this bill closely.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT
      letters = [kind_letter(0, text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org")]

      _, counts = classifier.call(text: text, letters: letters)

      expect(counts["source_kind_model_fallbacks"]).to eq(1)
    end

    # The organization branch is the product intent of this whole phase, and
    # under Rails.env.test? no letter could ever carry it — .build returned a
    # classifier with no model, so every tail letter fell back. An injected
    # adapter makes the branch reachable through the real service instead of
    # through hand-built fixtures alone.
    it "reads an injected model's verdict, so the organization branch is reachable in a spec" do
      adapter = instance_double(Llm::LlamacppAdapter, provider_label: "llamacpp")
      allow(adapter).to receive(:generate_source_kind_classification).and_return(
        {"classifications" => [{"position" => 0, "kind" => "named_organization"}]}
      )
      classifier = described_class.build(llm: adapter)

      text = <<~TEXT
        From: jane@baltimorehousing.org
        I have reviewed this bill closely.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT
      letters = [kind_letter(0, text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org")]

      augmented, counts = classifier.call(text: text, letters: letters)

      expect(augmented.first["source_kind"]).to eq("named_organization")
      expect(counts["source_kind_model_fallbacks"]).to eq(0)
    end

    it "counts no fallback when the model was never asked" do
      classifier = described_class.new(llm: nil)
      text = "From: resident@gmail.com\nI support this bill.\n"
      letters = [kind_letter(0, text, offset: 0, sender_address: "resident@gmail.com", sender_domain: "gmail.com")]

      _, counts = classifier.call(text: text, letters: letters)

      expect(counts["source_kind_model_fallbacks"]).to eq(0)
    end

    # B2. apply_one_classification looked a model reply's position up in
    # rule_result_by_position, which holds EVERY letter in the bill, not just
    # the letters actually sent to the model in this batch. A reply naming a
    # position outside its own batch used to rewrite that letter's verdict —
    # including a letter a rule had already settled — even though the model
    # was never asked about it. Two already-settled letters (positions 0 and
    # 1, decided by rule alone, never sent to the model) sit alongside one
    # tail letter (position 2) that IS sent to the model; the model's reply
    # names all three positions, and only position 2's answer may apply.
    it "refuses a model answer naming a position outside the batch that was actually asked" do
      settled_public_body = "From: clerk@baltimorecity.gov\nOn behalf of the Department of Transportation, we object.\n"
      settled_person_speaking_for_self = "From: alex@gmail.com\nI support this bill as a resident.\n"
      tail_person_speaking_for_org = <<~TEXT
        From: jane@baltimorehousing.org
        I have reviewed this bill closely.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT
      texts = [settled_public_body, settled_person_speaking_for_self, tail_person_speaking_for_org]
      full_text = texts.join("\n----\n")
      # @lat: [[rbs-signatures#Why a provably-safe value still needs a guard]]
      letters = [
        kind_letter(0, texts[0], offset: full_text.index(texts[0]) || raise("texts[0] not found in full_text"), sender_address: "clerk@baltimorecity.gov"),
        kind_letter(1, texts[1], offset: full_text.index(texts[1]) || raise("texts[1] not found in full_text"), sender_address: "alex@gmail.com"),
        kind_letter(2, texts[2], offset: full_text.index(texts[2]) || raise("texts[2] not found in full_text"), sender_address: "jane@baltimorehousing.org")
      ]

      adapter = instance_double(Llm::LlamacppAdapter, provider_label: "llamacpp")
      allow(adapter).to receive(:generate_source_kind_classification).and_return(
        {"classifications" => [
          {"position" => 0, "kind" => "named_organization"},
          {"position" => 1, "kind" => "named_organization"},
          {"position" => 2, "kind" => "person_speaking_for_org"}
        ]}
      )
      classifier = described_class.new(llm: adapter, enabled: true)

      augmented, = classifier.call(text: full_text, letters: letters)

      expect(augmented[0]["source_kind"]).to eq("public_body")
      expect(augmented[1]["source_kind"]).to eq("person_speaking_for_self")
      expect(augmented[2]["source_kind"]).to eq("person_speaking_for_org")
    end

    it "warns when two classifications in a batch name the same position, and the last one wins" do
      text = <<~TEXT
        From: jane@baltimorehousing.org
        I have reviewed this bill closely.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT
      letters = [kind_letter(0, text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org")]

      adapter = instance_double(Llm::LlamacppAdapter, provider_label: "llamacpp")
      allow(adapter).to receive(:generate_source_kind_classification).and_return(
        {"classifications" => [
          {"position" => 0, "kind" => "person_speaking_for_org"},
          {"position" => 0, "kind" => "named_organization"}
        ]}
      )
      classifier = described_class.new(llm: adapter, enabled: true)

      expect(SwayLogging).to receive(:warn).with("source_kind_classifier.duplicate_position_in_batch", position: 0)

      augmented, = classifier.call(text: text, letters: letters)

      expect(augmented.first["source_kind"]).to eq("named_organization")
    end

    it "resets the model-fallback count at the start of each #call, so a second bill does not inherit the first's tally" do
      adapter = instance_double(Llm::LlamacppAdapter, provider_label: "llamacpp")
      allow(adapter).to receive(:generate_source_kind_classification).and_raise(Llm::TransportError, "boom")
      classifier = described_class.new(llm: adapter, enabled: true)

      text = <<~TEXT
        From: jane@baltimorehousing.org
        I have reviewed this bill closely.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT
      letters = [kind_letter(0, text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org")]

      _, first_counts = classifier.call(text: text, letters: letters)
      _, second_counts = classifier.call(text: text, letters: letters)

      expect(first_counts["source_kind_model_fallbacks"]).to eq(1)
      expect(second_counts["source_kind_model_fallbacks"]).to eq(1)
    end

    it "returns an empty letters array and zero counts for no letters" do
      classifier = described_class.new(llm: nil)

      augmented, counts = classifier.call(text: "", letters: [])

      expect(augmented).to eq([])
      expect(counts.values).to all(eq(0))
    end

    it "skips excluded letters from LLM tail classification and excludes them from kind counts" do
      adapter = instance_double(Llm::LlamacppAdapter, provider_label: "llamacpp")
      expect(adapter).not_to receive(:generate_source_kind_classification)
      classifier = described_class.new(llm: adapter, enabled: true)

      text = <<~TEXT
        From: jane@baltimorehousing.org
        I have reviewed this bill closely.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT
      letters = [
        kind_letter(0, text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org").merge("excluded" => true)
      ]

      augmented, counts = classifier.call(text: text, letters: letters)

      expect(augmented.first["source_kind"]).to eq("person_speaking_for_self")
      expect(counts["person_speaking_for_self_letters"]).to eq(0)
      expect(counts["source_kind_model_fallbacks"]).to eq(0)
    end
  end

  describe "OpenRouter routing from the selected classification model" do
    let(:openrouter_adapter) { instance_double(Llm::OpenRouterAdapter, provider_label: "openrouter") }

    text = <<~TEXT
      From: jane@baltimorehousing.org
      I have reviewed this bill closely.

      Jane Doe
      Executive Director of the Baltimore Housing Coalition
    TEXT

    [
      ["Deepseek Pro Latest", "~deepseek/deepseek-pro-latest"],
      ["Deepseek Flash Latest", "~deepseek/deepseek-flash-latest"],
      ["OpenRouter Auto", "openrouter/auto"]
    ].each do |display_name, api_model|
      it "routes #{display_name} to OpenRouter adapter with api_model #{api_model} when environment is claude" do
        with_app_config(:llm, llm_provider: "claude") do
          AdminSetting.singleton.update_columns(classification_model: display_name)

          expect(openrouter_adapter).to receive(:generate_source_kind_classification).with(
            prompt: anything,
            model: api_model,
            schema: anything
          ).and_return("classifications" => [{"position" => 0, "kind" => "named_organization"}])

          classifier = described_class.new(llm: openrouter_adapter, enabled: true)
          letters = [kind_letter(0, text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org")]

          augmented, = classifier.call(text: text, letters: letters)
          expect(augmented.first["source_kind"]).to eq("named_organization")
        end
      end

      it "routes #{display_name} to OpenRouter adapter with api_model #{api_model} when environment is llamacpp" do
        with_app_config(:llm, llm_provider: "llamacpp") do
          AdminSetting.singleton.update_columns(classification_model: display_name)

          expect(openrouter_adapter).to receive(:generate_source_kind_classification).with(
            prompt: anything,
            model: api_model,
            schema: anything
          ).and_return("classifications" => [{"position" => 0, "kind" => "named_organization"}])

          classifier = described_class.new(llm: openrouter_adapter, enabled: true)
          letters = [kind_letter(0, text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org")]

          augmented, = classifier.call(text: text, letters: letters)
          expect(augmented.first["source_kind"]).to eq("named_organization")
        end
      end
    end

    it "falls back to CLASSIFIER_MODEL when classification_model setting is blank" do
      AdminSetting.singleton.update_columns(classification_model: "")
      claude_adapter = instance_double(Llm::ClaudeAdapter, provider_label: "claude")
      classifier = described_class.new(llm: claude_adapter)
      expect(classifier.send(:model_for, claude_adapter)).to eq(described_class::CLASSIFIER_MODEL)
    end

    it "is independent of summarization_model configuration" do
      AdminSetting.singleton.update_columns(
        summarization_model: "Deepseek Pro Latest",
        classification_model: "claude-haiku-5-5"
      )
      claude_adapter = instance_double(Llm::ClaudeAdapter, provider_label: "claude")
      classifier = described_class.new(llm: claude_adapter)
      expect(classifier.send(:model_for, claude_adapter)).to eq("claude-haiku-5-5")
    end

    it "raises ArgumentError for unknown adapter provider labels" do
      unknown_adapter = double("UnknownAdapter", provider_label: "unknown_provider")
      classifier = described_class.new(llm: unknown_adapter)
      expect {
        classifier.send(:model_for, unknown_adapter)
      }.to raise_error(ArgumentError, /unknown adapter provider/)
    end

    it "builds OpenRouter adapter when classification_model is an OpenRouter choice" do
      allow(Rails.env).to receive(:test?).and_return(false)
      AdminSetting.singleton.update_columns(classification_model: "Deepseek Pro Latest")
      allow(Llm::Client).to receive(:build).with(provider: "openrouter").and_return(openrouter_adapter)

      classifier = described_class.build
      expect(classifier.send(:llm)).to eq(openrouter_adapter)
    end

    # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes#Resolving an inference route from the chosen model]]
    it "keeps the model paired with the adapter when settings change after build" do
      with_app_config(:llm, llm_provider: "llamacpp", llamacpp_model: "local-after-change") do
        allow(Rails.env).to receive(:test?).and_return(false)
        AdminSetting.singleton.update_columns(classification_model: "Deepseek Pro Latest")
        allow(Llm::Client).to receive(:build).with(provider: "openrouter").and_return(openrouter_adapter)
        classifier = described_class.build
        AdminSetting.singleton.update_columns(classification_model: "claude-sonnet-5-5")
        allow(openrouter_adapter).to receive(:generate_source_kind_classification)
          .and_return("classifications" => [{"position" => 0, "kind" => "named_organization"}])
        letters = [kind_letter(0, text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org")]

        classifier.call(text: text, letters: letters)

        expect(openrouter_adapter).to have_received(:generate_source_kind_classification)
          .with(hash_including(model: "~deepseek/deepseek-pro-latest"))
      end
    end
  end

  describe "OpenRouter decision model dispatch" do
    let(:decision_adapter) { instance_double(Llm::OpenRouterAdapter, provider_label: "openrouter") }
    let(:decision_route) do
      Llm::RouteResolver::Route.new(
        provider: :openrouter,
        api_model: "scaledown/classify-1",
        reasoning_effort: nil,
        mode: :decision
      )
    end
    let(:org_letter_text) do
      <<~TEXT
        From: jane@baltimorehousing.org
        We write to express our support for this legislation.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT
    end
    let(:named_org_letter_text) do
      <<~TEXT
        From: info@baltimorehousing.org
        On behalf of the Baltimore Housing Coalition, we urge support for this bill.
      TEXT
    end
    let(:chat_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }
    let(:chat_route) do
      Llm::RouteResolver::Route.new(
        provider: :claude,
        api_model: "claude-haiku-5-5",
        reasoning_effort: nil,
        mode: :chat
      )
    end
    let(:classifier) { described_class.new(llm: decision_adapter, route: decision_route) }
    let(:spokesperson_letter_text) do
      <<~TEXT
        From: jane@baltimorehousing.org
        We strongly support this legislation to expand affordable housing.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT
    end

    it "defines MIN_DECISION_CONFIDENCE as 0.5" do
      expect(described_class::MIN_DECISION_CONFIDENCE).to eq(0.5)
    end

    it "dispatches tail letters via adapter.generate_decisions when route is a decision model" do
      letters = [
        kind_letter(0, org_letter_text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org")
      ]

      expect(decision_adapter).to receive(:generate_decisions).with(
        model: "scaledown/classify-1",
        state: {
          "letter_0" => "From: jane@baltimorehousing.org We write to express our support for this legislation. Jane Doe Executive Director of the Baltimore Housing Coalition"
        },
        questions: {
          "letter_0" => {
            "type" => "choice",
            "instructions" => "Determine whether letter 0 is written by an organization in its own voice, by an individual explicitly writing on behalf of a named organization with a role title, or by a private person speaking only for themselves.",
            "criteria" => {
              "named_organization" => "The letter speaks in the voice of an organization itself ('we', 'our organization') naming the organization as author.",
              "person_speaking_for_org" => "An individual signs the letter with their own name, a role title, and a named organization they represent.",
              "person_speaking_for_self" => "A private resident speaking for themselves, or neither organizational reading is clearly supported."
            }
          }
        }
      ).and_return(
        {
          "answers" => {
            "letter_0" => {
              "type" => "choice",
              "choice" => "person_speaking_for_org",
              "confidence" => 0.85
            }
          }
        }
      )

      classifier = described_class.new(llm: decision_adapter, route: decision_route)
      augmented, counts = classifier.call(text: org_letter_text, letters: letters)

      expect(augmented.first["source_kind"]).to eq("person_speaking_for_org")
      expect(augmented.first["source_evidence"]).to include(
        "role" => "Executive Director",
        "org_name" => "the Baltimore Housing Coalition"
      )
      expect(counts["person_speaking_for_org_letters"]).to eq(1)
      expect(counts["source_kind_model_fallbacks"]).to eq(0)
    end

    it "accepts named_organization choice when confidence is >= 0.5" do
      letters = [
        kind_letter(0, named_org_letter_text, offset: 0, sender_address: "info@baltimorehousing.org", sender_domain: "baltimorehousing.org")
      ]

      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "letter_0" => {
              "type" => "choice",
              "choice" => "named_organization",
              "confidence" => 0.60
            }
          }
        }
      )

      classifier = described_class.new(llm: decision_adapter, route: decision_route)
      augmented, counts = classifier.call(text: named_org_letter_text, letters: letters)

      expect(augmented.first["source_kind"]).to eq("named_organization")
      expect(counts["named_organization_letters"]).to eq(1)
    end

    it "reads confidence from probabilities hash if confidence key is absent" do
      letters = [
        kind_letter(0, named_org_letter_text, offset: 0, sender_address: "info@baltimorehousing.org", sender_domain: "baltimorehousing.org")
      ]

      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "letter_0" => {
              "type" => "choice",
              "choice" => "named_organization",
              "probabilities" => {
                "named_organization" => 0.75,
                "person_speaking_for_self" => 0.25
              }
            }
          }
        }
      )

      classifier = described_class.new(llm: decision_adapter, route: decision_route)
      augmented, = classifier.call(text: named_org_letter_text, letters: letters)

      expect(augmented.first["source_kind"]).to eq("named_organization")
    end

    it "falls back to person_speaking_for_self when confidence is below 0.5 without counting as fallback outage" do
      letters = [
        kind_letter(0, org_letter_text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org")
      ]

      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "letter_0" => {
              "type" => "choice",
              "choice" => "person_speaking_for_org",
              "confidence" => 0.45
            }
          }
        }
      )

      classifier = described_class.new(llm: decision_adapter, route: decision_route)
      augmented, counts = classifier.call(text: org_letter_text, letters: letters)

      expect(augmented.first["source_kind"]).to eq("person_speaking_for_self")
      expect(counts["source_kind_model_fallbacks"]).to eq(0)
    end

    it "rejects confidence of Float::INFINITY and falls back safely" do
      letters = [
        kind_letter(0, named_org_letter_text, offset: 0, sender_address: "info@baltimorehousing.org", sender_domain: "baltimorehousing.org")
      ]

      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "letter_0" => {
              "type" => "choice",
              "choice" => "named_organization",
              "confidence" => Float::INFINITY
            }
          }
        }
      )

      classifier = described_class.new(llm: decision_adapter, route: decision_route)
      augmented, counts = classifier.call(text: named_org_letter_text, letters: letters)

      expect(augmented.first["source_kind"]).to eq("person_speaking_for_self")
      expect(counts["source_kind_model_fallbacks"]).to eq(0)
    end

    it "rejects non-numeric string confidence '0.99' and falls back safely" do
      letters = [
        kind_letter(0, named_org_letter_text, offset: 0, sender_address: "info@baltimorehousing.org", sender_domain: "baltimorehousing.org")
      ]

      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "letter_0" => {
              "type" => "choice",
              "choice" => "named_organization",
              "confidence" => "0.99"
            }
          }
        }
      )

      classifier = described_class.new(llm: decision_adapter, route: decision_route)
      augmented, counts = classifier.call(text: named_org_letter_text, letters: letters)

      expect(augmented.first["source_kind"]).to eq("person_speaking_for_self")
      expect(counts["source_kind_model_fallbacks"]).to eq(0)
    end

    it "falls back to person_speaking_for_self when model chooses person_speaking_for_org but rules found no evidence" do
      letters = [
        kind_letter(0, named_org_letter_text, offset: 0, sender_address: "info@baltimorehousing.org", sender_domain: "baltimorehousing.org")
      ]

      allow(decision_adapter).to receive(:generate_decisions).and_return(
        {
          "answers" => {
            "letter_0" => {
              "type" => "choice",
              "choice" => "person_speaking_for_org",
              "confidence" => 0.90
            }
          }
        }
      )

      classifier = described_class.new(llm: decision_adapter, route: decision_route)
      augmented, = classifier.call(text: named_org_letter_text, letters: letters)

      expect(augmented.first["source_kind"]).to eq("person_speaking_for_self")
    end

    it "truncates oversized text in decision state" do
      long_text = "On behalf of the Baltimore Housing Coalition, we urge support: " + ("A" * 3000)
      letters = [
        kind_letter(0, long_text, offset: 0, sender_address: "info@baltimorehousing.org", sender_domain: "baltimorehousing.org")
      ]

      expect(decision_adapter).to receive(:generate_decisions) do |args|
        state_entry = args[:state]["letter_0"]
        expect(state_entry.length).to be < 2200
        expect(state_entry).to end_with(Testimony::SourceKindPromptBuilder::TEXT_TRUNCATION_NOTICE)
        {
          "answers" => {
            "letter_0" => {"type" => "choice", "choice" => "named_organization", "confidence" => 0.8}
          }
        }
      end

      classifier = described_class.new(llm: decision_adapter, route: decision_route)
      classifier.call(text: long_text, letters: letters)
    end

    it "rescues transport and schema errors, logs warning, increments fallback letters, and falls back safely" do
      letters = [
        kind_letter(0, org_letter_text, offset: 0, sender_address: "jane@baltimorehousing.org", sender_domain: "baltimorehousing.org")
      ]

      allow(decision_adapter).to receive(:generate_decisions).and_raise(
        Llm::TransportError.new("connection timeout")
      )
      allow(SwayLogging).to receive(:warn)

      classifier = described_class.new(llm: decision_adapter, route: decision_route)
      augmented, counts = classifier.call(text: org_letter_text, letters: letters)

      expect(augmented.first["source_kind"]).to eq("person_speaking_for_self")
      expect(counts["source_kind_model_fallbacks"]).to eq(1)
      expect(SwayLogging).to have_received(:warn).with(
        "source_kind_classifier.llm_failure",
        hash_including(candidate_count: 1, error_class: "Llm::TransportError")
      )
    end

    describe "Confidence boundaries and extraction" do
      it "rejects confidence of 0.499 and safely falls back to person_speaking_for_self without incrementing model fallbacks" do
        letters = [kind_letter(0, named_org_letter_text, offset: 0)]
        allow(decision_adapter).to receive(:generate_decisions).and_return(
          {
            "answers" => {
              "letter_0" => {
                "type" => "choice",
                "choice" => "named_organization",
                "confidence" => 0.499
              }
            }
          }
        )

        augmented, counts = classifier.call(text: named_org_letter_text, letters: letters)

        expect(augmented.first["source_kind"]).to eq("person_speaking_for_self")
        expect(counts["source_kind_model_fallbacks"]).to eq(0)
      end

      it "accepts confidence of exactly 0.500 as named_organization" do
        letters = [kind_letter(0, named_org_letter_text, offset: 0)]
        allow(decision_adapter).to receive(:generate_decisions).and_return(
          {
            "answers" => {
              "letter_0" => {
                "type" => "choice",
                "choice" => "named_organization",
                "confidence" => 0.500
              }
            }
          }
        )

        augmented, counts = classifier.call(text: named_org_letter_text, letters: letters)

        expect(augmented.first["source_kind"]).to eq("named_organization")
        expect(counts["named_organization_letters"]).to eq(1)
        expect(counts["source_kind_model_fallbacks"]).to eq(0)
      end

      it "accepts confidence of 0.501 as named_organization" do
        letters = [kind_letter(0, named_org_letter_text, offset: 0)]
        allow(decision_adapter).to receive(:generate_decisions).and_return(
          {
            "answers" => {
              "letter_0" => {
                "type" => "choice",
                "choice" => "named_organization",
                "confidence" => 0.501
              }
            }
          }
        )

        augmented, counts = classifier.call(text: named_org_letter_text, letters: letters)

        expect(augmented.first["source_kind"]).to eq("named_organization")
        expect(counts["named_organization_letters"]).to eq(1)
      end

      it "rejects confidence of 0.0 and negative confidence" do
        letters = [
          kind_letter(0, named_org_letter_text, offset: 0),
          kind_letter(1, named_org_letter_text, offset: 0)
        ]
        allow(decision_adapter).to receive(:generate_decisions).and_return(
          {
            "answers" => {
              "letter_0" => {"type" => "choice", "choice" => "named_organization", "confidence" => 0.0},
              "letter_1" => {"type" => "choice", "choice" => "named_organization", "confidence" => -0.5}
            }
          }
        )

        augmented, counts = classifier.call(text: named_org_letter_text, letters: letters)

        expect(augmented[0]["source_kind"]).to eq("person_speaking_for_self")
        expect(augmented[1]["source_kind"]).to eq("person_speaking_for_self")
        expect(counts["source_kind_model_fallbacks"]).to eq(0)
      end

      it "accepts confidence of 1.0" do
        letters = [kind_letter(0, named_org_letter_text, offset: 0)]
        allow(decision_adapter).to receive(:generate_decisions).and_return(
          {
            "answers" => {
              "letter_0" => {
                "type" => "choice",
                "choice" => "named_organization",
                "confidence" => 1.0
              }
            }
          }
        )

        augmented, counts = classifier.call(text: named_org_letter_text, letters: letters)

        expect(augmented.first["source_kind"]).to eq("named_organization")
        expect(counts["named_organization_letters"]).to eq(1)
      end

      it "falls back when confidence is a non-numeric string or nil" do
        letters = [
          kind_letter(0, named_org_letter_text, offset: 0),
          kind_letter(1, named_org_letter_text, offset: 0)
        ]
        allow(decision_adapter).to receive(:generate_decisions).and_return(
          {
            "answers" => {
              "letter_0" => {"type" => "choice", "choice" => "named_organization", "confidence" => "very_high"},
              "letter_1" => {"type" => "choice", "choice" => "named_organization", "confidence" => nil}
            }
          }
        )

        augmented, = classifier.call(text: named_org_letter_text, letters: letters)

        expect(augmented[0]["source_kind"]).to eq("person_speaking_for_self")
        expect(augmented[1]["source_kind"]).to eq("person_speaking_for_self")
      end

      it "extracts confidence from symbol keys :confidence" do
        letters = [kind_letter(0, named_org_letter_text, offset: 0)]
        allow(decision_adapter).to receive(:generate_decisions).and_return(
          {
            "answers" => {
              letter_0: {
                choice: :named_organization,
                confidence: 0.88
              }
            }
          }
        )

        augmented, = classifier.call(text: named_org_letter_text, letters: letters)

        expect(augmented.first["source_kind"]).to eq("named_organization")
      end

      it "extracts confidence from probabilities hash with symbol and string keys when confidence is absent" do
        letters = [
          kind_letter(0, named_org_letter_text, offset: 0),
          kind_letter(1, named_org_letter_text, offset: 0)
        ]
        allow(decision_adapter).to receive(:generate_decisions).and_return(
          {
            "answers" => {
              "letter_0" => {
                "type" => "choice",
                "choice" => "named_organization",
                "probabilities" => {"named_organization" => 0.75}
              },
              "letter_1" => {
                "type" => "choice",
                "choice" => "named_organization",
                "probabilities" => {named_organization: 0.82}
              }
            }
          }
        )

        augmented, = classifier.call(text: named_org_letter_text, letters: letters)

        expect(augmented[0]["source_kind"]).to eq("named_organization")
        expect(augmented[1]["source_kind"]).to eq("named_organization")
      end
    end

    describe "Evidence integrity and rule authority" do
      it "preserves role and org_name evidence when rules and model agree on person_speaking_for_org" do
        letters = [kind_letter(0, spokesperson_letter_text, offset: 0, sender_address: "jane@baltimorehousing.org")]

        allow(decision_adapter).to receive(:generate_decisions).and_return(
          {
            "answers" => {
              "letter_0" => {
                "type" => "choice",
                "choice" => "person_speaking_for_org",
                "confidence" => 0.90
              }
            }
          }
        )

        augmented, counts = classifier.call(text: spokesperson_letter_text, letters: letters)

        expect(augmented.first["source_kind"]).to eq("person_speaking_for_org")
        expect(augmented.first["source_evidence"]).to include(
          "role" => "Executive Director",
          "org_name" => "the Baltimore Housing Coalition"
        )
        expect(counts["person_speaking_for_org_letters"]).to eq(1)
      end

      it "overrides person_speaking_for_org to named_organization if model confidently chooses named_organization" do
        letters = [kind_letter(0, spokesperson_letter_text, offset: 0, sender_address: "jane@baltimorehousing.org")]

        allow(decision_adapter).to receive(:generate_decisions).and_return(
          {
            "answers" => {
              "letter_0" => {
                "type" => "choice",
                "choice" => "named_organization",
                "confidence" => 0.85
              }
            }
          }
        )

        augmented, counts = classifier.call(text: spokesperson_letter_text, letters: letters)

        expect(augmented.first["source_kind"]).to eq("named_organization")
        expect(augmented.first["source_evidence"]).to be_nil
        expect(counts["named_organization_letters"]).to eq(1)
      end
    end

    describe "Batching, out-of-batch answers, and duplicate positions" do
      it "ignores answers with positions outside the current batch" do
        letters = [kind_letter(5, named_org_letter_text, offset: 0)]

        allow(decision_adapter).to receive(:generate_decisions).and_return(
          {
            "answers" => {
              "letter_5" => {"type" => "choice", "choice" => "named_organization", "confidence" => 0.8},
              "letter_999" => {"type" => "choice", "choice" => "named_organization", "confidence" => 0.95}
            }
          }
        )

        augmented, = classifier.call(text: named_org_letter_text, letters: letters)

        expect(augmented.first["position"]).to eq(5)
        expect(augmented.first["source_kind"]).to eq("named_organization")
      end

      it "safely isolates a malformed answer to its own letter while preserving sibling letters" do
        text_0 = named_org_letter_text
        text_1 = named_org_letter_text
        full_text = "#{text_0}\n----\n#{text_1}"
        letters = [
          kind_letter(0, text_0, offset: 0),
          kind_letter(1, text_1, offset: text_0.length + 6)
        ]

        allow(decision_adapter).to receive(:generate_decisions).and_return(
          {
            "answers" => {
              "letter_0" => "not_a_hash",
              "letter_1" => {"type" => "choice", "choice" => "named_organization", "confidence" => 0.8}
            }
          }
        )

        augmented, counts = classifier.call(text: full_text, letters: letters)

        expect(augmented[0]["source_kind"]).to eq("person_speaking_for_self")
        expect(augmented[1]["source_kind"]).to eq("named_organization")
        expect(counts["named_organization_letters"]).to eq(1)
        expect(counts["person_speaking_for_self_letters"]).to eq(1)
      end

      it "splits 26 tail letters into batches of 25 and 1" do
        letters = (0..25).map do |i|
          kind_letter(i, named_org_letter_text, offset: 0)
        end

        batch_sizes = []
        allow(decision_adapter).to receive(:generate_decisions) do |args|
          batch_sizes << args[:questions].length
          answers = args[:questions].keys.to_h do |key|
            [key, {"type" => "choice", "choice" => "named_organization", "confidence" => 0.9}]
          end
          {"answers" => answers}
        end

        augmented, counts = classifier.call(text: named_org_letter_text, letters: letters)

        expect(batch_sizes).to eq([25, 1])
        expect(augmented.length).to eq(26)
        expect(counts["named_organization_letters"]).to eq(26)
        expect(counts["source_kind_model_fallbacks"]).to eq(0)
      end
    end

    describe "Network errors and transport fallback counters" do
      it "rescues Faraday::TimeoutError and increments model fallback letters" do
        letters = [
          kind_letter(0, named_org_letter_text, offset: 0),
          kind_letter(1, named_org_letter_text, offset: 0)
        ]

        allow(decision_adapter).to receive(:generate_decisions).and_raise(
          Faraday::TimeoutError.new("Execution expired")
        )
        allow(SwayLogging).to receive(:warn)

        augmented, counts = classifier.call(text: named_org_letter_text, letters: letters)

        expect(augmented[0]["source_kind"]).to eq("person_speaking_for_self")
        expect(augmented[1]["source_kind"]).to eq("person_speaking_for_self")
        expect(counts["source_kind_model_fallbacks"]).to eq(2)
        expect(SwayLogging).to have_received(:warn).with(
          "source_kind_classifier.llm_failure",
          hash_including(candidate_count: 2, error_class: "Faraday::TimeoutError")
        )
      end

      it "rescues Faraday::ConnectionFailed and increments model fallback letters" do
        letters = [kind_letter(0, named_org_letter_text, offset: 0)]

        allow(decision_adapter).to receive(:generate_decisions).and_raise(
          Faraday::ConnectionFailed.new("Connection refused")
        )
        allow(SwayLogging).to receive(:warn)

        augmented, counts = classifier.call(text: named_org_letter_text, letters: letters)

        expect(augmented[0]["source_kind"]).to eq("person_speaking_for_self")
        expect(counts["source_kind_model_fallbacks"]).to eq(1)
        expect(SwayLogging).to have_received(:warn).with(
          "source_kind_classifier.llm_failure",
          hash_including(candidate_count: 1, error_class: "Faraday::ConnectionFailed")
        )
      end
    end

    describe "Text truncation and prompt sanitization" do
      it "does not append truncation notice when letter text is exactly 2,000 characters" do
        exact_text = "On behalf of the Baltimore Housing Coalition: " + ("X" * (2_000 - 46))
        expect(exact_text.length).to eq(2_000)

        letters = [kind_letter(0, exact_text, offset: 0)]

        expect(decision_adapter).to receive(:generate_decisions) do |args|
          entry = args[:state]["letter_0"]
          expect(entry.length).to eq(2_000)
          expect(entry).not_to include(Testimony::SourceKindPromptBuilder::TEXT_TRUNCATION_NOTICE)
          {
            "answers" => {
              "letter_0" => {"type" => "choice", "choice" => "named_organization", "confidence" => 0.8}
            }
          }
        end

        classifier.call(text: exact_text, letters: letters)
      end

      it "appends truncation notice when letter text is 2,001 characters" do
        over_text = "On behalf of the Baltimore Housing Coalition: " + ("X" * (2_001 - 46))
        expect(over_text.length).to eq(2_001)

        letters = [kind_letter(0, over_text, offset: 0)]

        expect(decision_adapter).to receive(:generate_decisions) do |args|
          entry = args[:state]["letter_0"]
          notice = Testimony::SourceKindPromptBuilder::TEXT_TRUNCATION_NOTICE
          expect(entry).to end_with(notice)
          expect(entry.length).to eq(2_000 + notice.length)
          {
            "answers" => {
              "letter_0" => {"type" => "choice", "choice" => "named_organization", "confidence" => 0.8}
            }
          }
        end

        classifier.call(text: over_text, letters: letters)
      end
    end

    describe "Chat model vs decision model routing" do
      it "never calls generate_decisions on chat models and routes through generate_source_kind_classification" do
        chat_classifier = described_class.new(llm: chat_adapter, route: chat_route)

        expect(chat_adapter).not_to respond_to(:generate_decisions)
        expect(chat_adapter).to receive(:generate_source_kind_classification).and_return(
          {"classifications" => [{"position" => 0, "kind" => "named_organization"}]}
        )

        letters = [kind_letter(0, named_org_letter_text, offset: 0)]
        augmented, = chat_classifier.call(text: named_org_letter_text, letters: letters)

        expect(augmented.first["source_kind"]).to eq("named_organization")
      end
    end

    it "resolves decision model purpose when purpose: :decision is passed to .build" do
      allow(Rails.env).to receive(:test?).and_return(false)
      AdminSetting.singleton.update_columns(decision_model: "ScaleDown Classify Latest")
      allow(Llm::Client).to receive(:build).with(provider: "openrouter").and_return(decision_adapter)

      classifier = described_class.build(purpose: :decision)
      expect(classifier.send(:llm)).to eq(decision_adapter)
      expect(classifier.send(:model_for, decision_adapter)).to eq("scaledown/classify-1")
    end
  end
end
