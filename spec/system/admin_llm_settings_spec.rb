# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-categories-spec#The bill categories browser spec#The smoke-test fallback for the admin screens]]
RSpec.describe "Admin LLM Settings",
  type: :system,
  js: true,
  phase16: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }

  # @lat: [[admin-gate-shared-examples#Admin-gate shared examples#The admin trait replaces the configured phone list]]
  let(:sway_admin_user) { create(:user, :sway_admin) }

  before { create(:user_legislator, user: sway_admin_user, legislator: legislator) }

  describe "sway-admin round-trip" do
    it "lets the admin change the active Claude model from Haiku to Sonnet" do
      sign_in_as(sway_admin_user)

      visit "/admin/llm_settings"
      wait_until_loaded

      # Heading and description, worded as the UI design specifies.
      expect(page).to have_text("LLM Settings")
      expect(page).to have_text("Select the Claude models used by the bill summarization job and the testimony attachment classifier.")

      expect(page).to have_text("Model Selection")
      expect(page).to have_text("Summarization model")

      # What is selected now: the friendly Haiku label, from the seeded
      # default. Look it up by id, because the page layout may render its own
      # dropdown (the locale switcher) somewhere else.
      trigger = find_by_id("summarization-model")
      expect(trigger).to have_text("Haiku 5.5 — fast & cheap (default)")

      # Open the Radix Select dropdown — the options render outside the
      # trigger's part of the page, so search the whole page for
      # [role="option"].
      trigger.click
      expect(page).to have_css("[role='option']", wait: 5)

      find("[role='option']", text: "Sonnet 5.5 — balanced").click

      click_button "Save settings"

      # The flash notice appears after the save redirects.
      expect(page).to have_text("Model updated.", wait: 10)

      # The dropdown now shows the friendly Sonnet label, sent by the server in
      # the partial reload after the redirect.
      expect(page).to have_text("Sonnet 5.5 — balanced")

      AdminSetting.singleton.reload
      expect(AdminSetting.singleton.summarization_model).to eq("claude-sonnet-5-5")
      expect(AdminSetting.singleton.updated_by_id).to eq(sway_admin_user.id)
    end

    # @lat: [[llm-summaries#LLM bill summaries#Settings live in the database#A refused save names the field that moved]]
    it "lets the admin change the testimony classification model without moving the summarization model" do
      sign_in_as(sway_admin_user)

      visit "/admin/llm_settings"
      wait_until_loaded

      expect(page).to have_text("Testimony classification model")

      trigger = find_by_id("classification-model")
      expect(trigger).to have_text("Haiku 5.5 — fast & cheap (default)")

      trigger.click
      expect(page).to have_css("[role='option']", wait: 5)
      find("[role='option']", text: "Sonnet 5.5 — balanced").click

      click_button "Save settings"

      expect(page).to have_text("Model updated.", wait: 10)

      AdminSetting.singleton.reload
      expect(AdminSetting.singleton.classification_model).to eq("claude-sonnet-5-5")
      expect(AdminSetting.singleton.summarization_model).to eq("claude-haiku-5-5")
      expect(AdminSetting.singleton.updated_by_id).to eq(sway_admin_user.id)
    end

    it "lets the admin change the decision model without moving other models" do
      sign_in_as(sway_admin_user)

      visit "/admin/llm_settings"
      wait_until_loaded

      expect(page).to have_text("Decision model")

      trigger = find_by_id("decision-model")
      trigger.click
      expect(page).to have_css("[role='option']", wait: 5)
      find("[role='option']", text: "Jev Latest").click

      click_button "Save settings"

      expect(page).to have_text("Model updated.", wait: 10)

      AdminSetting.singleton.reload
      expect(AdminSetting.singleton.decision_model).to eq("Jev Latest")
      expect(AdminSetting.singleton.summarization_model).to eq("claude-haiku-5-5")
      expect(AdminSetting.singleton.classification_model).to eq("claude-haiku-5-5")
      expect(AdminSetting.singleton.updated_by_id).to eq(sway_admin_user.id)
    end
  end

  # @lat: [[llm-summaries#LLM bill summaries#Settings live in the database#A refused save names the field that moved]]
  describe "two admins editing at once" do
    # @lat: [[admin-gate-shared-examples#Admin-gate shared examples#The admin trait replaces the configured phone list]]
    let(:other_editor) { create(:user, :registered) }

    it "does not revert a knob this admin never touched" do
      sign_in_as(sway_admin_user)

      visit "/admin/llm_settings"
      wait_until_loaded
      expect(find_by_id("classification-model")).to have_text("Haiku 5.5 — fast & cheap (default)")

      # Admin B moves the classification model up a level for a difficult
      # batch while admin A is still sitting on the loaded page.
      AdminSetting.singleton.update!(
        classification_model: "claude-sonnet-5-5",
        updated_by_id: other_editor.id
      )

      trigger = find_by_id("summarization-model")
      trigger.click
      expect(page).to have_css("[role='option']", wait: 5)
      find("[role='option']", text: "Opus 5.5 — maximum quality").click
      click_button "Save settings"
      expect(page).to have_text("Model updated.", wait: 10)

      AdminSetting.singleton.reload
      expect(AdminSetting.singleton.summarization_model).to eq("claude-opus-5-5")
      expect(AdminSetting.singleton.classification_model).to eq("claude-sonnet-5-5"),
        "admin B's classification change was silently reverted by a save that never touched that field"
    end

    it "refuses to overwrite a knob that moved under it, and says so" do
      sign_in_as(sway_admin_user)

      visit "/admin/llm_settings"
      wait_until_loaded
      expect(find_by_id("summarization-model")).to have_text("Haiku 5.5 — fast & cheap (default)")

      # Admin B changes the SAME setting admin A is about to change.
      AdminSetting.singleton.update!(
        summarization_model: "claude-sonnet-5-5",
        updated_by_id: other_editor.id
      )

      trigger = find_by_id("summarization-model")
      trigger.click
      expect(page).to have_css("[role='option']", wait: 5)
      find("[role='option']", text: "Opus 5.5 — maximum quality").click
      click_button "Save settings"

      expect(page).to have_text("changed", wait: 10)

      AdminSetting.singleton.reload
      expect(AdminSetting.singleton.summarization_model).to eq("claude-sonnet-5-5"),
        "admin A's stale save landed on top of admin B's without either of them being told"
      expect(AdminSetting.singleton.updated_by_id).to eq(other_editor.id)
    end
  end

  describe "non-admin denial" do
    it "redirects a non-admin away from /admin/llm_settings" do
      non_admin = create(:user, :registered)
      create(:user_legislator, user: non_admin, legislator: legislator)
      sign_in_as(non_admin) # despite the name it only signs in; admin depends on the phone

      visit "/admin/llm_settings"

      # @lat: [[admin-gate-shared-examples#Admin-gate shared examples#Incomplete registration can mask the admin gate]]
      expect(page).to have_current_path("/feed", ignore_query: true, wait: 10)
      expect(page).to have_text("Feed", wait: 10)

      expect(page).to have_no_text("LLM Settings")
      expect(page).to have_no_text("Summarization model")
    end
  end

  # @lat: [[capybara-wait-semantics#Waiting on the side effect instead]]
  describe "keyboard-only model change" do
    it "lets the admin change the active model via Tab + Space + ArrowDown + Enter" do
      sign_in_as(sway_admin_user)

      visit "/admin/llm_settings"
      wait_until_loaded

      trigger = find_by_id("summarization-model")
      expect(trigger).to have_text("Haiku 5.5 — fast & cheap (default)")

      page.execute_script("document.getElementById('summarization-model').focus()")

      # Radix accepts Space, Enter, or ArrowDown to open the listbox.
      trigger.send_keys(:space)
      expect(page).to have_css("[role='option']", wait: 5)

      search_input = find("[data-slot='combobox-input']", wait: 5)
      search_input.send_keys(:arrow_down)

      sonnet_option = find("[role='option'][data-highlighted]", text: "Sonnet 5.5 — balanced", wait: 5)
      expect(sonnet_option["data-highlighted"]).not_to be_nil

      search_input.send_keys(:enter)

      # @lat: [[capybara-wait-semantics#Waiting on the side effect instead]]
      expect(page).to have_no_css("[role='option']")
      expect(trigger).to have_text("Sonnet 5.5 — balanced")

      save_button = find(:button, text: /\ASave setting/, wait: 5)
      save_button.send_keys(:enter)

      expect(page).to have_text("Model updated.", wait: 10)

      AdminSetting.singleton.reload
      expect(AdminSetting.singleton.summarization_model).to eq("claude-sonnet-5-5")
      expect(AdminSetting.singleton.updated_by_id).to eq(sway_admin_user.id)
    end
  end

  # @lat: [[admin-llm-settings-controller-design#Dynamic model catalog and offered model actions]]
  describe "offered models management" do
    before do
      openrouter_payload = {
        data: [
          {
            id: "openai/gpt-4o",
            name: "OpenAI: GPT-4o",
            supported_parameters: ["structured_outputs"]
          }
        ]
      }.to_json

      stub_request(:get, "https://openrouter.ai/api/v1/models?supported_parameters=structured_outputs")
        .to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: openrouter_payload)
    end

    it "lets the admin add an OpenRouter model and remove a non-active offered model" do
      sign_in_as(sway_admin_user)

      visit "/admin/llm_settings"
      wait_until_loaded

      expect(page).to have_text("Offered Models")

      haiku_remove = find("[data-testid='btn-remove-model-claude-haiku-5-5']")
      expect(haiku_remove).to be_disabled

      add_trigger = find_by_id("add-openrouter-model")
      add_trigger.click
      expect(page).to have_css("[role='option']", wait: 5)

      find("[role='option']", text: "OpenAI: GPT-4o").click
      click_button "Add model"

      expect(page).to have_text("Model added to offered list.", wait: 10)

      AdminSetting.singleton.reload
      expect(AdminSetting.singleton.offered_models_list).to include("openai/gpt-4o")

      new_remove = find("[data-testid='btn-remove-model-openai/gpt-4o']", wait: 5)
      expect(new_remove).not_to be_disabled
      new_remove.click

      expect(page).to have_text("Model removed from offered list.", wait: 10)

      AdminSetting.singleton.reload
      expect(AdminSetting.singleton.offered_models_list).not_to include("openai/gpt-4o")
    end
  end

  # @lat: [[llm-summaries#LLM bill summaries#Settings live in the database#The browser settings test uses only offered models]]
end
