# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "sway_locale")
require Rails.root.join("db", "seeds", "models", "seed_llm_bill_summarization_instruction")

RSpec.describe AdminSystemPromptCatalog do
  subject(:catalog) { described_class.new(llm_settings_path: "/admin/llm_settings") }

  def catalog_entry(props, id)
    props[:prompts].find { |entry| entry[:id] == id }
  end

  def catalog_text_for(props, id)
    catalog_entry(props, id)[:system_prompt]
  end

  context "with an active taxonomy and seeded jurisdictions" do
    let!(:category) { create(:category, name: "Housing", active: true) }
    let!(:locales) do
      SeedSwayLocale.run
      SeedLlmBillSummarizationInstruction.run
      catalog.send(:sway_locales)
    end

    it "returns seven prompts with per-locale bill summary cards in pipeline order" do
      expect(catalog.as_props[:prompts].pluck(:id)).to eq(
        %w[
          bill_summary_baltimore-maryland-united_states
          bill_summary_congress-congress-united_states
          bill_summary_maryland-maryland-united_states
          bill_positions
          bill_categories
          testimony_classification
          testimony_source_kind
        ]
      )
    end

    it "matches what BillSummaryPromptBuilder produces for each locale's placeholder bill" do
      props = catalog.as_props

      locales.each do |locale|
        expected = BillSummaryPromptBuilder.new(
          Bill.new(sway_locale: locale),
          active_categories: [category]
        ).system_prompt

        expect(catalog_text_for(props, "bill_summary_#{locale.name}")).to eq(expected)
      end
    end

    it "produces identical text from a persisted Baltimore bill and the Baltimore placeholder card" do
      baltimore = SwayLocale.resolve_by_computed_name("baltimore-maryland-united_states") || raise("missing locale")
      persisted_bill = create(:bill, sway_locale: baltimore, title: "An ordinance concerning housing")

      props = catalog.as_props
      card_text = catalog_text_for(props, "bill_summary_baltimore-maryland-united_states")

      expect(card_text).to eq(BillSummaryPromptBuilder.new(persisted_bill, active_categories: [category]).system_prompt)
    end

    it "renders jurisdiction-authentic worked examples on each per-locale bill summary card" do
      props = catalog.as_props
      baltimore_card = catalog_text_for(props, "bill_summary_baltimore-maryland-united_states")
      maryland_card = catalog_text_for(props, "bill_summary_maryland-maryland-united_states")
      congress_card = catalog_text_for(props, "bill_summary_congress-congress-united_states")

      expect(baltimore_card).to include("CB 23-0312", "Baltimore City Code")
      expect(baltimore_card).not_to include("Annotated Code of Maryland")
      expect(baltimore_card).not_to include("United States Code")

      expect(maryland_card).to include("HB 452", "Annotated Code of Maryland")
      expect(maryland_card).not_to include("Baltimore City Code")
      expect(maryland_card).not_to include("CB 23-0312")

      expect(congress_card).to include("H.R. 2030", "United States Code")
      expect(congress_card).not_to include("Baltimore City Code")
      expect(congress_card).not_to include("CB 23-0312")
    end

    it "renders exactly what each builder produces from a real, fully populated input for singleton prompts" do
      bill = create(:bill, title: "An ordinance concerning annual lead-paint inspections")
      create(
        :bill_llm_provisioning,
        :with_testimony,
        bill: bill,
        llm_summary: "This bill requires annual lead-paint inspections for pre-1978 rental units."
      )
      bill.reload
      active = [category]
      documents = [{name: "DOF Report CB 23-0312", text: "The Department of Finance reports that..."}] #: Array[Testimony::ClassificationPromptBuilder::document]
      candidates = [{position: 0, text: "The Maryland Tenants Union supports this bill."}] #: Array[Testimony::SourceKindPromptBuilder::candidate]

      props = catalog.as_props

      expect(catalog_text_for(props, "bill_positions"))
        .to eq(BillPositionsPromptBuilder.new(bill).system_prompt)
      expect(catalog_text_for(props, "bill_categories"))
        .to eq(BillCategoryPromptBuilder.new(bill, active_categories: active).system_prompt)
      expect(catalog_text_for(props, "testimony_classification"))
        .to eq(Testimony::ClassificationPromptBuilder.new(documents).system_prompt)
      expect(catalog_text_for(props, "testimony_source_kind"))
        .to eq(Testimony::SourceKindPromptBuilder.new(candidates).system_prompt)
    end

    it "counts characters, not bytes, which differ over the categoriser's en dash" do
      catalog.as_props[:prompts].each do |entry|
        next if entry[:system_prompt].nil?

        expect(entry[:character_count]).to eq(entry[:system_prompt].length)
      end

      categories = catalog_entry(catalog.as_props, "bill_categories")
      expect(categories[:system_prompt]).to include("1\u2013")
      expect(categories[:character_count]).to be < categories[:system_prompt].bytesize
    end

    it "produces the same prompts on a second call" do
      expect(described_class.new(llm_settings_path: "/admin/llm_settings").as_props[:prompts])
        .to eq(described_class.new(llm_settings_path: "/admin/llm_settings").as_props[:prompts])
    end

    it "carries no per-instance boundary delimiter" do
      joined = catalog.as_props[:prompts].filter_map { |entry| entry[:system_prompt] }.join("\n")

      expect(joined).not_to match(/-[0-9a-f]{16}/)
    end

    it "names the active categories in order(:name), leaving inactive ones out" do
      create(:category, name: "Zoning", active: true)
      create(:category, name: "Education", active: true)
      create(:category, name: "Retired Topic", active: false)

      props = catalog.as_props

      expect(catalog_text_for(props, "bill_categories")).to include("Education, Housing, Zoning")
      expect(catalog_text_for(props, "bill_categories")).not_to include("Retired Topic")
      expect(props[:active_category_count]).to eq(3)
    end

    it "reads both models from the singleton settings row" do
      AdminSetting.singleton.update!(
        summarization_model: "claude-opus-5-5",
        classification_model: "claude-haiku-5-5"
      )

      props = described_class.new(llm_settings_path: "/admin/llm_settings").as_props

      expect(props[:models]).to eq({summarization: "claude-opus-5-5", classification: "claude-haiku-5-5"})
      expect(catalog_entry(props, "bill_positions")[:model]).to eq("claude-opus-5-5")
      expect(catalog_entry(props, "testimony_source_kind")[:model]).to eq("claude-haiku-5-5")
    end
  end

  context "when a locale has no summarization instruction record" do
    it "returns an unavailable reason naming the table and seeder, with nil prompt text" do
      locale = create(:sway_locale, :baltimore)

      props = catalog.as_props
      card = catalog_entry(props, "bill_summary_#{locale.name}")

      expect(card[:system_prompt]).to be_nil
      expect(card[:character_count]).to be_nil
      expect(card[:unavailable_reason]).to eq(
        "No summarization prompt is sent for #{locale.name}. There is no legislative body " \
        "description in llm_bill_summarization_instructions for this locale. Run " \
        "SeedLlmBillSummarizationInstruction to seed it."
      )
    end
  end

  context "when a locale is not declared in JurisdictionRulesRegistry" do
    it "excludes the undeclared locale from catalog prompts" do
      undeclared_locale = create(
        :sway_locale,
        city: "bethesda",
        state: "MD",
        country: "United States"
      )
      props = catalog.as_props
      card = catalog_entry(props, "bill_summary_#{undeclared_locale.name}")

      expect(card).to be_nil
      expect(props[:prompts].pluck(:id)).not_to include("bill_summary_#{undeclared_locale.name}")
    end

    it "does not invoke BillSummaryPromptBuilder or emit missing context warnings" do
      undeclared_locale = create(
        :sway_locale,
        city: "bethesda",
        state: "MD",
        country: "United States"
      )
      undeclared_locale.create_llm_bill_summarization_instruction!(
        legislative_body_makeup: "A City Council serving four-year terms."
      )
      allow(SwayLogging).to receive(:warn)

      catalog.as_props

      expect(SwayLogging).not_to have_received(:warn).with(
        "bill_summary_prompt.missing_jurisdictional_context",
        any_args
      )
    end
  end

  context "when a declared locale has blank legislative body makeup" do
    it "returns an unavailable reason naming the table and seeder" do
      locale = create(:sway_locale, :baltimore)
      locale.create_llm_bill_summarization_instruction!(legislative_body_makeup: "   ")

      props = catalog.as_props
      card = catalog_entry(props, "bill_summary_#{locale.name}")

      expect(card[:system_prompt]).to be_nil
      expect(card[:character_count]).to be_nil
      expect(card[:unavailable_reason]).to eq(
        "No summarization prompt is sent for #{locale.name}. There is no legislative body " \
        "description in llm_bill_summarization_instructions for this locale. Run " \
        "SeedLlmBillSummarizationInstruction to seed it."
      )
    end
  end

  context "when jurisdiction rules declare law_rules engine unavailable" do
    it "rejects the locale from sway_locales without checking legacy law_source" do
      locale = create(:sway_locale, city: "annapolis", state: "maryland", country: "united_states")
      rules = locale.declared_jurisdiction_rules
      expect(rules.respond_to?(:law_source)).to be false

      expect(catalog.send(:sway_locales)).not_to include(locale)
    end
  end

  context "with no active categories" do
    let!(:locales) do
      SeedSwayLocale.run
      SeedLlmBillSummarizationInstruction.run
      catalog.send(:sway_locales)
    end

    it "reports the categories prompt as not sent, with no text and no count" do
      entry = catalog_entry(catalog.as_props, "bill_categories")

      expect(entry[:system_prompt]).to be_nil
      expect(entry[:character_count]).to be_nil
      expect(entry[:unavailable_reason]).to eq(described_class::EMPTY_TAXONOMY_REASON)
    end

    it "renders the summary prompt's empty-taxonomy branch verbatim for each locale" do
      props = catalog.as_props

      locales.each do |locale|
        expected = BillSummaryPromptBuilder.new(
          Bill.new(sway_locale: locale),
          active_categories: []
        ).system_prompt

        expect(catalog_text_for(props, "bill_summary_#{locale.name}")).to eq(expected)
      end
    end
  end
end
