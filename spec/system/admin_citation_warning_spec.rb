# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#The citation warning does not block the operator's writes]]
RSpec.describe "Admin citation warning", type: :system, js: true do
  # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#The citation warning does not block the operator's writes]]
  def bad_citation_keys = ["§ 14-402(c)", "§ 99-999"]

  let(:admin_phone) { "4105551243" }
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:bill) { create(:bill, sway_locale: sway_locale, legislator: legislator) }
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

  # @lat: [[organization-position-removal#Taking an organization's position off a bill#A draft with no testimony behind it is not approvable]]
  def provision_with_bad_citations
    create(
      :bill_llm_provisioning,
      :with_diff_content,
      :completed,
      :with_drafts,
      bill: bill,
      citations_valid: false,
      invalid_citations: bad_citation_keys
    )
  end

  it "names every section key the bill does not have" do
    provision_with_bad_citations

    sign_in_as(sway_admin_user)
    navigate_to_llm_accordion(bill)

    expect(page).to have_css("[data-testid='llm-citation-warning']", wait: 10)
    within("[data-testid='llm-citation-warning']") do
      # Plural, because there are two. The singular title on a two-key list
      # would be the first sign the list is being cut short somewhere.
      expect(page).to have_text("Unverified citations")
      bad_citation_keys.each { |key| expect(page).to have_text(key) }
      expect(page).to have_text("does not block saving or approving")
    end
  end

  # The claim the copy makes, tested by making the write.
  it "still lets the summary be saved while the warning is up" do
    provision_with_bad_citations

    sign_in_as(sway_admin_user)
    navigate_to_llm_accordion(bill)

    expect(page).to have_css("[data-testid='llm-citation-warning']", wait: 10)

    textarea = find("[data-testid='textarea-llm-summary']")
    textarea.set("")
    textarea.set("Published even though two citations could not be verified.")

    click_testid("btn-save-summary")

    expect(page).to have_text("Summary saved.", wait: 10)
    expect(bill.reload.summary).to eq(
      "Published even though two citations could not be verified."
    )

    # The warning is about the summary's citations, so a save must not clear it
    # — the citations were not re-checked, and a warning that vanishes on save
    # would tell the operator the problem went away.
    expect(page).to have_css("[data-testid='llm-citation-warning']")
  end

  # The other write, and the more expensive one: Approve publishes a public
  # OrganizationBillPosition.
  it "still lets a draft position be approved while the warning is up" do
    provision_with_bad_citations

    sign_in_as(sway_admin_user)
    navigate_to_llm_accordion(bill)

    expect(page).to have_css("[data-testid='llm-citation-warning']", wait: 10)

    navigate_to_positions_tab(bill)
    expect(page).to have_css("[data-testid='org-position-card-test-org-0']")

    within("[data-testid='org-position-card-test-org-0']") do
      # Not merely enabled: the point of the click is that the refusal could
      # also come from the server, and only the record settles that.
      expect(page).to have_no_css("[data-testid='btn-approve-org-position'][disabled]")
      click_testid("btn-approve-org-position")
    end

    # @lat: [[capybara-wait-semantics#Waiting on the side effect instead]]
    expect(page).to have_no_css("[data-testid='org-position-card-test-org-0']", wait: 10)

    expect(OrganizationBillPosition.where(bill: bill).count).to eq(1)
    expect(Organization.where(sway_locale: sway_locale).first&.name).to eq("Test Org")
  end
end
