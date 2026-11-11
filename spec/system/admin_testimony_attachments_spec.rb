# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-creator-testimony-attachments]]
RSpec.describe "Admin testimony attachments", type: :system, js: true do
  def positions_tab = "[data-testid='positions-tab']"
  def summary_tab = "[data-testid='summary-tab']"

  let(:admin_phone) { "4105551242" }
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:bill) { create(:bill, sway_locale: sway_locale, legislator: legislator) }
  let(:sway_admin_user) do
    create(:user, :registered, phone: admin_phone)
  end

  # One row of the mirror FetchHearingsService writes, in the shape
  # #mirror_entries really builds: a display name, the Legistar id as a string,
  # the two statuses, and the row's own error text.
  def attachment_row(filename:, id:, download: "succeeded", extraction: "succeeded", error: nil)
    {
      "filename" => filename,
      "attachment_id" => id,
      "download_status" => download,
      "extraction_status" => extraction,
      "error" => error
    }
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

  # @lat: [[bill-creator-testimony-attachments#Each warning answers a different question]]
  it "names the documents that need an answer and leaves the bill's summary standing" do
    create(
      :bill_llm_provisioning,
      :with_diff_content,
      :completed,
      :with_testimony,
      bill: bill,
      testimony_attachments: [
        attachment_row(filename: "Bikemore testimony.pdf", id: "9001"),
        attachment_row(
          filename: "Scanned agency letter.pdf",
          id: "9002",
          extraction: "extraction_failed",
          error: "no text layer found in PDF"
        ),
        attachment_row(
          filename: "Community letters bundle.pdf",
          id: "9003",
          error: "extracted text truncated to 500000 chars (was 712371)"
        )
      ]
    )

    sign_in_as(sway_admin_user)
    navigate_to_positions_tab(bill)

    # The document whose text never arrived, under the one heading whose advice
    # — paste it in below — is true for it.
    expect(page).to have_css("[data-testid='llm-testimony-attachment-warning']", wait: 10)
    within("[data-testid='llm-testimony-attachment-warning']") do
      expect(page).to have_text("Scanned agency letter.pdf")
      expect(page).to have_text("no text layer found in PDF")
      # The way out, which the hands-on expectation names as part of the state:
      # marked failed, with a readable reason AND a prompt to paste the text.
      # This is the one list where pasting actually helps, which is why the
      # other three say something different.
      expect(page).to have_text("Paste the testimony text into Supplemental testimony")
    end

    # The document that WAS read but cut short. It is a separate list because
    # its text IS in the prompt, so "paste this document in" would be wrong.
    # The operator saw exactly this shape twice on bill 25-0064, with the
    # character counts.
    expect(page).to have_css("[data-testid='llm-testimony-attachment-truncated']")
    within("[data-testid='llm-testimony-attachment-truncated']") do
      expect(page).to have_text("Community letters bundle.pdf")
      expect(page).to have_text("500000")
      expect(page).to have_text("712371")
    end

    # @lat: [[bill-creator-testimony-attachments#Bill Creator testimony attachment warnings#The clean attachment assertion is scoped to its component]]
    within(positions_tab) { expect(page).to have_no_text("Bikemore testimony.pdf") }

    navigate_to_summary_tab(bill)

    # And the bill did not fail. The summary is on screen and ready, which is
    # the half of test 3 that the attachment lists cannot say by themselves.
    expect(page).to have_css("[data-testid='llm-status-badge']", text: "Ready")
    expect(page).to have_css("[data-testid='textarea-llm-summary']")
  end

  # The other shape of the same surface, and the reason it is worth an example:
  # LlmSummaryTestimonyAttachmentWarning draws nothing at all when every row is
  # clean, so every assertion above passes on a screen that reports healthy
  # documents as problems. Only this one fails for that.
  it "says nothing about attachments when every one of them was read" do
    create(
      :bill_llm_provisioning,
      :with_diff_content,
      :completed,
      :with_testimony,
      bill: bill,
      testimony_attachments: [
        attachment_row(filename: "Bikemore testimony.pdf", id: "9001"),
        attachment_row(filename: "Neighborhood association letter.pdf", id: "9002")
      ]
    )

    sign_in_as(sway_admin_user)
    navigate_to_positions_tab(bill)

    # All four lists, because each answers a different question and each has its
    # own way of being drawn by mistake.
    expect(page).to have_no_css("[data-testid='llm-testimony-attachment-warning']")
    expect(page).to have_no_css("[data-testid='llm-testimony-attachment-truncated']")
    expect(page).to have_no_css("[data-testid='llm-testimony-attachment-reused']")
    expect(page).to have_no_css("[data-testid='llm-testimony-attachment-denied']")
    within(positions_tab) { expect(page).to have_no_text("Bikemore testimony.pdf") }

    navigate_to_summary_tab(bill)
    expect(page).to have_css("[data-testid='llm-status-badge']", text: "Ready", wait: 10)
  end

  # @lat: [[bill-creator-testimony-attachments#Polling updates attachment warnings without a page load]]
  it "lists the documents a hearing fetch brought in, with no reload" do
    provisioning = create(
      :bill_llm_provisioning,
      :with_diff_content,
      :completed,
      bill: bill,
      testimony_attachments: nil
    )
    create(:legislation_pipeline_run, :running, bill: bill)

    sign_in_as(sway_admin_user)
    navigate_to_summary_tab(bill)

    expect(page).to have_css("[data-testid='bill-pipeline-refresh-status']", wait: 10)

    navigate_to_positions_tab(bill)
    expect(page).to have_no_css("[data-testid='llm-testimony-attachment-warning']")

    plant_reload_probe!

    provisioning.update!(
      extracted_testimony: "Testimony submitted at the hearing on this bill.",
      testimony_fetched_at: Time.current,
      testimony_attachments: [
        attachment_row(filename: "Read whole.pdf", id: "9101"),
        attachment_row(
          filename: "Sideways scan.pdf",
          id: "9102",
          extraction: "extraction_failed",
          error: "no text layer found in PDF"
        )
      ]
    )

    expect(page).to have_css("[data-testid='llm-testimony-attachment-warning']", wait: 20)
    expect(page).to have_text("Sideways scan.pdf")

    # Nobody pressed anything and nothing navigated: the mark planted before the
    # write is still on the document that is showing the new row.
    expect_no_full_page_load!
  end
end
