# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Summary Editing",
  type: :system,
  js: true,
  phase16: true do
  let(:admin_phone) { "4105550002" }
  let(:sway_locale) { create(:sway_locale) }
  let(:legislator) do
    create(:legislator, district: create(:district, sway_locale: sway_locale))
  end
  # The Retry and Regenerate flows below both ask
  # GenerateBillSummaryService#runnable? whether there is anything to
  # summarize. It no longer looks at diff_content, so the bill needs
  # extracted_text — that is the text the prompt is built from.
  let(:bill) do
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      extracted_text: "Section 1. The Mayor shall submit an annual report."
    )
  end
  let(:sway_admin_user) do
    create(:user, :registered, phone: admin_phone)
  end

  around do |example|
    previous_admin_phones = User::ADMIN_PHONES.dup

    begin
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, [admin_phone])

      example.run
    ensure
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, previous_admin_phones)
    end
  end

  before { create(:user_legislator, user: sway_admin_user, legislator: legislator) }

  after { cleanup_summary_files(bill) }

  describe "summary editing flow" do
    # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Choosing the model for one regeneration#A new draft takes the place of the text in the box]]
    it "shows the published summary in the box and the model's draft beside it" do
      bill.update!(summary: "The public summary an admin wrote by hand.")
      create(:bill_llm_provisioning, :with_diff_content, :completed, bill: bill)

      sign_in_as(sway_admin_user)
      navigate_to_llm_accordion(bill)

      textarea = find("[data-testid='textarea-llm-summary']", wait: 10)
      expect(textarea.value).to eq("The public summary an admin wrote by hand.")

      # "Test summary" is the :completed trait's llm_summary. It is offered,
      # one click from the box, and it is not in the box.
      expect(page).to have_css(
        "[data-testid='llm-draft-body']",
        text: "Test summary",
        wait: 10
      )
      expect(page).to have_css("[data-testid='btn-use-llm-draft']")
    end

    it "editing and saving summary updates bills.summary while preserving llm_summary" do
      create(:bill_llm_provisioning, :with_diff_content, :completed, bill: bill)

      sign_in_as(sway_admin_user)
      navigate_to_llm_accordion(bill)

      textarea = find("[data-testid='textarea-llm-summary']", wait: 10)
      textarea.set("")
      textarea.set("Edited admin summary for users")

      click_testid("btn-save-summary")

      expect(page).to have_text("Summary saved.", wait: 10)

      expect(bill.reload.summary).to eq("Edited admin summary for users")
      expect(bill.bill_llm_provisioning.reload.llm_summary).to eq(
        "Test summary"
      )
    end

    # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    it "offers the three models beside the Regenerate button, under the Public summary box" do
      create(:bill_llm_provisioning, :with_diff_content, :completed, bill: bill)

      sign_in_as(sway_admin_user)
      navigate_to_llm_accordion(bill)

      picker = find("[data-testid='select-summary-model']", wait: 10)
      expect(picker.text).to include("Haiku 5.5")

      picker.click
      AdminSetting::SUPPORTED_MODEL_LABELS.each_value do |label|
        expect(page).to have_text(label, wait: 5)
      end
    end

    it "allows searching in the combobox to filter per-run model options" do
      create(:bill_llm_provisioning, :with_diff_content, :completed, bill: bill)

      sign_in_as(sway_admin_user)
      navigate_to_llm_accordion(bill)

      picker = find("[data-testid='select-summary-model']", wait: 10)
      picker.click

      search_input = find("input[placeholder='Search models...']", wait: 5)
      search_input.fill_in(with: "Opus")

      within("[role='listbox']") do
        expect(page).to have_text("Opus 5.5", wait: 5)
        expect(page).to have_no_text("Haiku 5.5")
      end
    end
  end

  describe "error and edge states" do
    it "shows error message and retry button on failed generation" do
      create(:bill_llm_provisioning, :with_diff_content, :failed, bill: bill)

      sign_in_as(sway_admin_user)
      navigate_to_llm_accordion(bill)

      expect(page).to have_css(
        "[data-testid='llm-status-badge']",
        text: "Failed",
        wait: 10
      )
      expect(page).to have_css("[data-testid='llm-error-message']")
      expect(page).to have_text("Summary generation failed")
      expect(page).to have_text("Pipeline error:")
      expect(page).to have_css(
        "[data-testid='btn-retry-summary']",
        text: "Retry"
      )
    end

    it "retry button on failure re-enqueues generation" do
      create(:bill_llm_provisioning, :with_diff_content, :failed, bill: bill)

      sign_in_as(sway_admin_user)
      navigate_to_llm_accordion(bill)

      stub_pipeline_success(bill)

      expect(page).to have_css("[data-testid='btn-retry-summary']", wait: 10)
      click_testid("btn-retry-summary")

      expect(page).to have_css(
        "[data-testid='llm-status-badge']",
        text: "Queued…",
        wait: 10
      )
    end

    it "regeneration shows confirmation dialog and re-enqueues on confirm" do
      create(:bill_llm_provisioning, :with_diff_content, :completed, bill: bill)

      sign_in_as(sway_admin_user)
      navigate_to_llm_accordion(bill)

      stub_pipeline_success(bill, summary_text: "Regenerated summary")

      expect(page).to have_css(
        "[data-testid='btn-regenerate-summary']",
        wait: 10
      )
      click_testid("btn-regenerate-summary")

      expect(page).to have_css("[data-testid='confirmation-dialog']", wait: 10)
      # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Choosing the model for one regeneration#The confirm dialog names the model]]
      expect(page).to have_text(
        "This will replace the model's draft summary. The published summary below is not changed by this."
      )

      click_testid("btn-confirm-dialog-confirm")

      expect(page).to have_css(
        "[data-testid='llm-status-badge']",
        text: "Queued…",
        wait: 10
      )
    end

    it "regeneration can be canceled via confirmation dialog" do
      create(:bill_llm_provisioning, :with_diff_content, :completed, bill: bill)

      sign_in_as(sway_admin_user)
      navigate_to_llm_accordion(bill)

      expect(page).to have_css(
        "[data-testid='btn-regenerate-summary']",
        wait: 10
      )
      click_testid("btn-regenerate-summary")

      expect(page).to have_css("[data-testid='confirmation-dialog']", wait: 10)

      click_testid("btn-confirm-dialog-cancel")

      expect(page).to have_no_css(
        "[data-testid='confirmation-dialog']",
        wait: 10
      )
      expect(page).to have_css(
        "[data-testid='llm-status-badge']",
        text: "Ready"
      )
    end
  end
end
