# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Org Positions", type: :system, js: true, phase16: true do
  let(:admin_phone) { "4105550001" }
  let(:sway_locale) { create(:sway_locale) }
  let(:legislator) do
    create(:legislator, district: create(:district, sway_locale: sway_locale))
  end
  # @lat: [[admin-organization-positions-browser-tests#Conditional bill fixture]]
  let(:bill) do
    @bill_materialized = true
    create(:bill, sway_locale: sway_locale, legislator: legislator)
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

  after { cleanup_summary_files(bill) if @bill_materialized }

  describe "draft org positions display" do
    # @lat: [[admin-organization-positions-browser-tests#Rendering existing drafts is not a generation test]]
    it "renders a card per draft org position carried on the provisioning row" do
      create(:bill_llm_provisioning, :with_diff_content, :completed, :with_drafts, bill: bill)

      sign_in_as(sway_admin_user)
      navigate_to_positions_tab(bill)

      expect(page).to have_css(
        "[data-testid='org-position-card-test-org-0']",
        wait: 10
      )
      expect(page).to have_text("Test Org")
      expect(page).to have_css("[data-testid='btn-approve-org-position']")
      expect(page).to have_css("[data-testid='btn-reject-org-position']")
    end

    it "shows no org positions message when none generated" do
      # There has to be testimony, or the UI shows its "not run yet" message
      # instead — positions are only ever generated from testimony.
      create(
        :bill_llm_provisioning,
        :with_diff_content,
        bill: bill,
        generation_status: "completed",
        llm_summary: "Test summary",
        llm_full_breakdown: "## Test",
        extracted_testimony: "Testimony submitted in support of the bill.",
        draft_org_positions: []
      )

      sign_in_as(sway_admin_user)
      navigate_to_positions_tab(bill)

      expect(page).to have_text("No draft positions generated.", wait: 10)
    end

    it "shows the no-testimony message when the bill has no testimony" do
      create(
        :bill_llm_provisioning,
        :with_diff_content,
        bill: bill,
        generation_status: "completed",
        llm_summary: "Test summary",
        llm_full_breakdown: "## Test",
        draft_org_positions: []
      )

      sign_in_as(sway_admin_user)
      navigate_to_positions_tab(bill)

      expect(page).to have_css("[data-testid='llm-no-testimony']", wait: 10)
      expect(page).to have_text("No public testimony available for this bill")
    end

    # @lat: [[admin-organization-positions-browser-tests#Drafts without testimony are blocked]]
    it "warns and disables Approve when drafts outlive the testimony they came from" do
      create(
        :bill_llm_provisioning,
        :with_diff_content,
        bill: bill,
        generation_status: "completed",
        llm_summary: "Test summary",
        llm_full_breakdown: "## Test",
        draft_org_positions: [
          {
            "org_name" => "Stranded Org",
            "stance" => "support",
            "summary" => "Supports"
          }
        ]
      )

      sign_in_as(sway_admin_user)
      navigate_to_positions_tab(bill)

      expect(page).to have_css("[data-testid='org-position-card-stranded-org-0']", wait: 10)
      expect(page).to have_css("[data-testid='llm-no-testimony']")
      expect(page).to have_text("cannot be approved")

      within("[data-testid='org-position-card-stranded-org-0']") do
        expect(page).to have_css("[data-testid='btn-approve-org-position'][disabled]")
        # Reject and Edit are the admin's two ways out, so they stay usable.
        expect(page).to have_no_css("[data-testid='btn-reject-org-position'][disabled]")
        expect(page).to have_no_css("[data-testid='btn-edit-org-position'][disabled]")
      end
    end

    # @lat: [[organization-position-removal#A draft with no testimony behind it is not approvable]]
    # @lat: [[admin-organization-positions-browser-tests#Retracted evidence is separately blocked]]
    it "warns and disables Approve on a draft whose own evidence was retracted" do
      create(
        :bill_llm_provisioning,
        :with_diff_content,
        :with_testimony,
        bill: bill,
        generation_status: "completed",
        llm_summary: "Test summary",
        llm_full_breakdown: "## Test",
        draft_org_positions: [
          {
            "org_name" => "Retracted Org",
            "stance" => "support",
            "summary" => "Supports",
            "evidence_retracted_at" => "2026-07-01T00:00:00Z"
          }
        ]
      )

      sign_in_as(sway_admin_user)
      navigate_to_positions_tab(bill)

      expect(page).to have_css("[data-testid='org-position-card-retracted-org-0']", wait: 10)

      within("[data-testid='org-position-card-retracted-org-0']") do
        expect(page).to have_css("[data-testid='org-position-evidence-retracted']")
        expect(page).to have_text("no longer on this bill")
        expect(page).to have_css("[data-testid='btn-approve-org-position'][disabled]")
        expect(page).to have_no_css("[data-testid='btn-reject-org-position'][disabled]")
      end

      # The bill HAS testimony, so the bill-level notice must be absent. That
      # is what makes this example about the per-draft mark alone.
      expect(page).to have_no_css("[data-testid='llm-no-testimony']")
    end
  end

  describe "approving an org position" do
    it "creates an OrganizationBillPosition record" do
      create(:bill_llm_provisioning, :with_diff_content, :completed, :with_drafts, bill: bill)

      sign_in_as(sway_admin_user)
      navigate_to_positions_tab(bill)

      expect(page).to have_css(
        "[data-testid='org-position-card-test-org-0']",
        wait: 10
      )

      within("[data-testid='org-position-card-test-org-0']") do
        click_testid("btn-approve-org-position")
      end

      # @lat: [[capybara-wait-semantics#Waiting on the side effect instead]]
      expect(page).to have_no_css(
        "[data-testid='org-position-card-test-org-0']",
        wait: 10
      )

      expect(OrganizationBillPosition.where(bill: bill).count).to eq(1)
      # @lat: [[admin-organization-positions-browser-tests#Exact counts pin organization reuse]]
      expect(Organization.where(sway_locale: sway_locale).count).to eq(1)
      expect(Organization.where(sway_locale: sway_locale).first&.name).to eq("Test Org")
    end
  end

  describe "approving an edited org position" do
    it "persists amended stance + summary to OrganizationBillPosition and audit log" do
      create(
        :bill_llm_provisioning,
        :with_diff_content,
        :with_testimony,
        bill: bill,
        generation_status: "completed",
        llm_summary: "Test summary",
        llm_full_breakdown: "## Test",
        draft_org_positions: [
          {
            "org_name" => "Editable Org",
            "stance" => "support",
            "summary" => "Original support summary."
          }
        ]
      )

      sign_in_as(sway_admin_user)
      navigate_to_positions_tab(bill)

      expect(page).to have_css(
        "[data-testid='org-position-card-editable-org-0']",
        wait: 10
      )

      within("[data-testid='org-position-card-editable-org-0']") do
        click_testid("btn-edit-org-position")
        find("[data-testid='textarea-edit-summary']").set("Amended oppose summary.")
      end

      # @lat: [[admin-organization-positions-browser-tests#The edited approval uses a real control click]]
      within("[data-testid='org-position-card-editable-org-0']") do
        click_testid("select-edit-stance-trigger")
      end
      find("[role='option']", text: "Oppose", wait: 5).click

      within("[data-testid='org-position-card-editable-org-0']") do
        click_testid("btn-save-edit-org-position")
        click_testid("btn-approve-org-position")
      end

      # Wait for something visible — the card disappears when the page reloads
      # part of itself after the approval — not for the progress bar, which
      # races.
      expect(page).to have_no_css(
        "[data-testid='org-position-card-editable-org-0']",
        wait: 10
      )

      # (a) The saved record carries the edited stance and summary, not the
      # original draft values.
      position = OrganizationBillPosition.where(bill: bill).last
      expect(position).to be_present
      expect(position.support).to eq("AGAINST")
      expect(position.summary).to eq("Amended oppose summary.")

      # @lat: [[admin-organization-positions-browser-tests#The audit event records the decision only]]
      entry = PipelineActivityLogEntry
        .where(event_type: "org_position_decision")
        .order(:id)
        .last
      expect(entry).to be_present
      expect(entry.payload["decision"]).to eq("approved")
      expect(entry.payload["org_name"]).to eq("Editable Org")
      expect(entry.payload["bill_id"]).to eq(bill.id)
    end
  end

  describe "rejecting an org position" do
    it "removes it from the list" do
      create(
        :bill_llm_provisioning,
        :with_diff_content,
        :with_testimony,
        bill: bill,
        generation_status: "completed",
        llm_summary: "Test summary",
        llm_full_breakdown: "## Test",
        draft_org_positions: [
          {
            "org_name" => "Keep Org",
            "stance" => "support",
            "summary" => "Supports"
          },
          {
            "org_name" => "Remove Org",
            "stance" => "oppose",
            "summary" => "Opposes"
          }
        ]
      )

      sign_in_as(sway_admin_user)
      navigate_to_positions_tab(bill)

      expect(page).to have_css(
        "[data-testid='org-position-card-keep-org-0']",
        wait: 10
      )
      expect(page).to have_css("[data-testid='org-position-card-remove-org-1']")

      within("[data-testid='org-position-card-remove-org-1']") do
        click_testid("btn-reject-org-position")
      end

      expect(page).to have_no_css(
        "[data-testid='org-position-card-remove-org-1']",
        wait: 10
      )
      navigate_to_positions_tab(bill)
      expect(page).to have_css("[data-testid='org-position-card-keep-org-0']")

      expect(
        bill.bill_llm_provisioning.reload.draft_org_positions.length
      ).to eq(1)
    end
  end
end
