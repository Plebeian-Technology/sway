# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-summary-reporting#System verification for reader reports and admin triage]]
RSpec.describe "Bill summary reporting and admin triage", type: :system, js: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:sway_admin_user) { create(:user, :sway_admin) }
  let(:regular_user) { create(:user) }
  let(:bill) do
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      title: "Municipal Clean Water Act",
      external_id: "BILL-2026-CW1",
      summary: "This bill regulates municipal stormwater runoff.",
      link: "https://legistar.example.com/legislation/cw1"
    )
  end
  let!(:provisioning) do
    create(
      :bill_llm_provisioning,
      :completed,
      bill: bill,
      llm_summary: bill.summary
    )
  end

  before do
    create(:user_legislator, user: sway_admin_user, legislator: legislator)
    create(:user_legislator, user: regular_user, legislator: legislator)
  end

  describe "Admin interface" do
    it "navigates from /admin tool card to /admin/bill_summary_reports" do
      sign_in_as(sway_admin_user)
      visit "/admin"
      wait_until_loaded

      expect(page).to have_text("Bill Summary Reports")
      click_link "Bill Summary Reports"
      wait_until_loaded

      expect(page).to have_current_path("/admin/bill_summary_reports")
      expect(page).to have_text("Review, triage, and resolve reader-submitted reports")
    end

    it "triages, resolves, and navigates to bill creator" do
      report = create(
        :bill_summary_report,
        bill: bill,
        user: regular_user,
        reason: "factual_inaccuracy",
        details: "Section 3 penalty amounts are incorrect.",
        status: :pending
      )

      sign_in_as(sway_admin_user)
      visit "/admin/bill_summary_reports"
      wait_until_loaded

      expect(page).to have_text("BILL-2026-CW1")
      expect(page).to have_text("Section 3 penalty amounts are incorrect.")

      # Verify link to bill creator summary tab exists
      creator_link = find("[data-testid='btn-bill-creator-#{report.id}']")
      expect(creator_link[:href]).to include("/admin/bill_creator/#{bill.id}/summary")

      # Resolve the report via dialog
      click_testid("btn-resolve-#{report.id}")
      wait_until_loaded

      expect(page).to have_text("Mark Report as Resolved")
      fill_in "action-admin-notes", with: "Remediated in Bill Creator and released."
      click_testid("btn-confirm-action")
      wait_until_loaded
      expect(page).to have_no_text("Mark Report as Resolved")
      expect(page).to have_text("Report ##{report.id} updated.")

      expect(report.reload.status).to eq("resolved")
      expect(report.admin_notes).to eq("Remediated in Bill Creator and released.")
      expect(report.resolved_by_id).to eq(sway_admin_user.id)
    end
  end

  describe "Reader bill page reporting" do
    it "renders the unreviewed notice bar with report button and source text link" do
      visit bill_path(bill)
      wait_until_loaded

      expect(page).to have_css("[data-testid='ai-summary-notice-bar']")
      expect(page).to have_css("[data-testid='bill-source-text-link']")
      expect(page).to have_css("[data-testid='btn-report-inaccurate-summary']")

      source_link = find("[data-testid='bill-source-text-link']")
      expect(source_link[:href]).to eq("https://legistar.example.com/legislation/cw1")
    end

    it "allows a reader to submit a summary inaccuracy report" do
      visit bill_path(bill)
      wait_until_loaded

      click_testid("btn-report-inaccurate-summary")
      wait_until_loaded

      expect(page).to have_text("Report Inaccurate Summary")
      expect(page).to have_css("[data-testid='report-summary-form']")

      # Select reason
      find_by_id("reason-factual_inaccuracy").click

      # Enter details
      fill_in "report-details", with: "The summary incorrectly states that fines apply to residential homes."

      # Submit
      click_testid("btn-submit-report")
      wait_until_loaded

      expect(page).to have_css("[data-testid='report-confirmation-view']", wait: 10)
      expect(page).to have_text("Thank you for your report")

      created_report = BillSummaryReport.where(bill: bill).last
      expect(created_report).to be_present
      expect(created_report.reason).to eq("factual_inaccuracy")
      expect(created_report.details).to eq("The summary incorrectly states that fines apply to residential homes.")
      expect(created_report.summary_snapshot).to eq(bill.summary)
      expect(created_report.summary_ai_unreviewed).to be(true)
    end

    it "renders mobile bottom sheet with >= 44px touch targets, client validation, nil link fallback, and mobile admin report cards" do
      page.current_window.resize_to(390, 844)
      visit bill_path(bill)
      wait_until_loaded

      report_btn = find("[data-testid='btn-report-inaccurate-summary']")
      expect(page.evaluate_script("arguments[0].getBoundingClientRect().height", report_btn.native).round).to be >= 44
      report_btn.click
      wait_until_loaded

      dialog_content = find("[role='dialog']")
      expect(dialog_content[:class]).to include("max-sm:fixed", "max-sm:bottom-0", "max-sm:rounded-t-2xl")
      expect(find("[data-testid='btn-submit-report']")).to be_disabled

      target_label = find("label[for='reason-factual_inaccuracy']")
      page.execute_script("arguments[0].click();", target_label.native)
      fill_in "report-details", with: "Too short"
      expect(find("[data-testid='btn-submit-report']")).to be_disabled

      bill_without_link = create(
        :bill,
        sway_locale: sway_locale,
        legislator: legislator,
        title: "Urban Tree Canopy Program",
        external_id: "BILL-2026-TREE",
        summary: "This bill expands urban forestry grant programs.",
        scheduled_release_date_utc: 5.days.ago
      )
      bill_without_link.update_column(:link, nil)
      create(:bill_llm_provisioning, :completed, bill: bill_without_link, llm_summary: bill_without_link.summary)

      visit bill_path(bill_without_link)
      wait_until_loaded
      expect(page).to have_css("[data-testid='ai-summary-notice-bar']")
      expect(page).to have_no_css("[data-testid='bill-source-text-link']")
      expect(page).to have_css("[data-testid='btn-report-inaccurate-summary']")

      report_pending = create(
        :bill_summary_report,
        bill: bill,
        user: regular_user,
        reason: "factual_inaccuracy",
        details: "Mobile triage card test.",
        status: :pending
      )
      sign_in_as(sway_admin_user)
      visit "/admin/bill_summary_reports"
      wait_until_loaded
      expect(page).to have_css("[data-testid='mobile-report-cards']")
      expect(page).to have_css("[data-testid='report-card-#{report_pending.id}']")
    end
  end
end
