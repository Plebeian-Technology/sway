# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "sway_locale")
require Rails.root.join("db", "seeds", "models", "seed_llm_bill_summarization_instruction")

RSpec.describe "Admin::SystemPrompts", type: :request do
  include_context "SessionDouble"

  include_examples "requires sway admin",
    verb: :get,
    path: "/admin/system_prompts"

  def system_prompt_entry(id)
    inertia.props[:prompts].find { |entry| entry[:id] == id }
  end

  def all_system_prompt_text
    inertia.props[:prompts].filter_map { |entry| entry[:system_prompt] }.join("\n")
  end

  context "as a sway admin" do
    let(:admin) { create(:user, :sway_admin) }

    before do
      SeedSwayLocale.run
      session_hash[:user_id] = admin.id
      create(:category, name: "Housing", active: true)
      SeedLlmBillSummarizationInstruction.run
    end

    it "renders the system prompts page" do
      get "/admin/system_prompts"

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component("admin/SystemPrompts")
    end

    it "lists the seven prompt cards in pipeline order, expanding bill summary per locale" do
      get "/admin/system_prompts"

      expect(inertia.props[:prompts].length).to eq(7)
      expect(inertia.props[:prompts].pluck(:id)).to eq(
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

    it "names the real builder class behind each prompt" do
      get "/admin/system_prompts"

      expect(inertia.props[:prompts].pluck(:builder)).to eq(
        [
          BillSummaryPromptBuilder.name,
          BillSummaryPromptBuilder.name,
          BillSummaryPromptBuilder.name,
          BillPositionsPromptBuilder.name,
          BillCategoryPromptBuilder.name,
          Testimony::ClassificationPromptBuilder.name,
          Testimony::SourceKindPromptBuilder.name
        ]
      )
    end

    it "attaches sway_locale_name to per-locale cards and nil to singletons" do
      get "/admin/system_prompts"

      locale_cards = inertia.props[:prompts].first(3)
      expect(locale_cards.pluck(:sway_locale_name)).to eq(
        %w[
          baltimore-maryland-united_states
          congress-congress-united_states
          maryland-maryland-united_states
        ]
      )

      singleton_cards = inertia.props[:prompts].drop(3)
      expect(singleton_cards.pluck(:sway_locale_name)).to all(be_nil)
    end

    it "renders each jurisdiction's prompt with solely its own legislative body context" do
      get "/admin/system_prompts"

      baltimore_card = system_prompt_entry("bill_summary_baltimore-maryland-united_states")
      expect(baltimore_card[:system_prompt]).to include("* **City Council.** A 15-member legislative body")
      expect(baltimore_card[:system_prompt]).not_to include("General Assembly")
      expect(baltimore_card[:system_prompt]).not_to include("House of Representatives (435 voting members)")

      maryland_card = system_prompt_entry("bill_summary_maryland-maryland-united_states")
      expect(maryland_card[:system_prompt]).to include("* **General Assembly.** It is bicameral, comprising the House of Delegates")
      expect(maryland_card[:system_prompt]).not_to include("A 15-member legislative body")
      expect(maryland_card[:system_prompt]).not_to include("House of Representatives (435 voting members)")

      congress_card = system_prompt_entry("bill_summary_congress-congress-united_states")
      expect(congress_card[:system_prompt]).to include("* **Congress.** A bicameral legislature comprising the House of Representatives")
      expect(congress_card[:system_prompt]).not_to include("General Assembly")
      expect(congress_card[:system_prompt]).not_to include("A 15-member legislative body")
    end

    it "carries each prompt's text with a matching character count" do
      get "/admin/system_prompts"

      inertia.props[:prompts].each do |entry|
        expect(entry[:system_prompt]).to be_a(String)
        expect(entry[:system_prompt]).to be_present
        expect(entry[:character_count]).to eq(entry[:system_prompt].length)
        expect(entry[:unavailable_reason]).to be_nil
      end
    end

    it "renders the taxonomy branch the live active category list produces" do
      create(:category, name: "Retired Topic", active: false)

      get "/admin/system_prompts"

      summary = system_prompt_entry("bill_summary_baltimore-maryland-united_states")[:system_prompt]
      expect(summary).to include("Housing")
      expect(summary).not_to include("Retired Topic")
      expect(summary).not_to include("Do NOT emit `categories` at all")
      expect(inertia.props[:active_category_count]).to eq(1)
    end

    it "leaks no per-call content into any system prompt" do
      get "/admin/system_prompts"

      text = all_system_prompt_text
      expect(text).not_to include("## Bill metadata")
      expect(text).not_to include("## Bill diff")
      expect(text).not_to include("## Documents")
      expect(text).not_to include("## Letters")
    end

    it "carries no per-instance boundary delimiter" do
      get "/admin/system_prompts"

      expect(all_system_prompt_text).not_to match(/-[0-9a-f]{16}/)
    end

    it "sends the category prompt under the summarization model, not the classification one" do
      AdminSetting.singleton.update!(
        summarization_model: "claude-opus-5-5",
        classification_model: "claude-haiku-5-5"
      )

      get "/admin/system_prompts"

      expect(inertia.props[:models].deep_symbolize_keys).to eq(
        {summarization: "claude-opus-5-5", classification: "claude-haiku-5-5"}
      )
      expect(system_prompt_entry("bill_categories")[:model]).to eq("claude-opus-5-5")
      expect(system_prompt_entry("testimony_classification")[:model]).to eq("claude-haiku-5-5")
    end

    it "links out to the page that changes those models" do
      get "/admin/system_prompts"

      expect(inertia.props[:llm_settings_path]).to eq(admin_llm_settings_path)
    end

    it "builds no bill row to render the prompts" do
      expect { get "/admin/system_prompts" }.not_to change(Bill, :count)
    end

    # The literal is also typed into LlmSettings.tsx and placeholderRegistry.ts.
    it "is served at the path the frontend hard-codes" do
      expect(admin_system_prompts_path).to eq("/admin/system_prompts")
    end

    context "when a locale lacks summarization instructions" do
      before do
        baltimore = SwayLocale.resolve_by_computed_name("baltimore-maryland-united_states") || raise("missing locale")
        baltimore.llm_bill_summarization_instruction&.destroy!
      end

      it "marks that locale card unavailable with an alert naming the table and seeder" do
        get "/admin/system_prompts"

        card = system_prompt_entry("bill_summary_baltimore-maryland-united_states")
        expect(card[:system_prompt]).to be_nil
        expect(card[:character_count]).to be_nil
        expect(card[:unavailable_reason]).to include("llm_bill_summarization_instructions")
        expect(card[:unavailable_reason]).to include("SeedLlmBillSummarizationInstruction")
      end
    end

    context "when a locale is not declared in JurisdictionRulesRegistry" do
      before do
        create(:sway_locale, city: "Philadelphia", state: "Pennsylvania", country: "United States")
      end

      it "excludes that undeclared locale from prompt preview cards" do
        get "/admin/system_prompts"

        card = system_prompt_entry("bill_summary_philadelphia-pennsylvania-united_states")
        expect(card).to be_nil
      end
    end
  end

  context "as a sway admin with no active categories" do
    let(:admin) { create(:user, :sway_admin) }

    before do
      session_hash[:user_id] = admin.id
      SeedSwayLocale.run
      SeedLlmBillSummarizationInstruction.run
    end

    it "reports that no categorisation prompt is sent, and renders the other six" do
      get "/admin/system_prompts"

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:active_category_count]).to eq(0)

      categories = system_prompt_entry("bill_categories")
      expect(categories[:system_prompt]).to be_nil
      expect(categories[:character_count]).to be_nil
      expect(categories[:unavailable_reason]).to be_present

      others = inertia.props[:prompts].reject { |entry| entry[:id] == "bill_categories" }
      expect(others.map { |entry| entry[:system_prompt].present? }).to eq([true, true, true, true, true, true])
    end

    it "renders the summary prompt's no-taxonomy branch" do
      get "/admin/system_prompts"

      expect(system_prompt_entry("bill_summary_baltimore-maryland-united_states")[:system_prompt]).to include("Do NOT emit `categories` at all")
    end
  end
end
