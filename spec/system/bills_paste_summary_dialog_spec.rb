# frozen_string_literal: true

require "rails_helper"

# @lat: [[paste-summary-dialog#The dialog validates a pasted draft before publishing]]
RSpec.describe "Bills Paste Summary Dialog",
  type: :system,
  js: true,
  phase16: true do
  let(:admin_phone) { "4105551235" }
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:bill) { create(:bill, sway_locale: sway_locale, legislator: legislator) }

  # @lat: [[paste-summary-dialog#A published summary remains separate from the pasted draft]]
  let(:published_summary) { "The public summary an admin wrote by hand." }

  # @lat: [[paste-summary-dialog#Validation waits for the server response]]
  def paste_summary_json_and_validate(json)
    find("[data-testid='input-paste-summary-json']").set(json)
    expect(page).to have_css("[data-testid='btn-validate-paste-summary']:not([disabled])")
    click_testid("btn-validate-paste-summary")
  end

  around do |example|
    original_admin_phones = User::ADMIN_PHONES.dup

    begin
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, [admin_phone])

      example.run
    ensure
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, original_admin_phones)
    end
  end

  before do
    @sway_admin_user = create(:user, :registered, phone: admin_phone)
    create(:user_legislator, user: @sway_admin_user, legislator: legislator)
    # @lat: [[paste-summary-dialog#The setup has existing drafts and supplemental testimony]]
    create(:bill_llm_provisioning, :with_diff_content, :completed, :with_drafts, bill: bill)
    bill.update!(summary: published_summary)
  end

  # @lat: [[paste-summary-dialog#Fixture names form stable card selectors]]
  let(:valid_payload) do
    {
      summary_markdown: "Operator-pasted brief one-line summary.",
      full_breakdown_markdown: "## Section 1\nPasted breakdown details.",
      draft_org_positions: [
        {org_name: "Pasted Coalition", stance: "support", summary: "We support this bill"}
      ]
    }
  end

  it "happy path: valid JSON closes dialog + summary text refreshes" do
    sign_in_as(@sway_admin_user)
    navigate_to_llm_accordion(bill)

    click_testid("btn-paste-summary-completed")
    expect(page).to have_css("[data-testid='paste-summary-dialog']")

    paste_summary_json_and_validate(JSON.generate(valid_payload))

    # The dialog closes: its element is either removed or hidden.
    expect(page).to have_no_css("[data-testid='paste-summary-dialog']", wait: 10)

    # The pasted text is on screen, with nobody reloading the page. It is a
    # draft, so it shows beside the box rather than in it, one button from
    # publication.
    expect(page).to have_css(
      "[data-testid='llm-draft-body']",
      text: "Operator-pasted brief one-line summary.",
      wait: 10
    )
    expect(page).to have_css("[data-testid='btn-use-llm-draft']")

    # And it is offered as the OPERATOR'S OWN TEXT. The notice said "The model
    # wrote a different summary" over it, and called it "the draft from the last
    # run" — a model that never saw the text and a run that never happened, at
    # the one moment this dialog exists to serve. (IT24-01)
    expect(page).to have_css(
      "[data-testid='llm-draft-notice']",
      text: "This is the text you pasted."
    )
    expect(page).to have_no_text("The model wrote a different summary")

    # The published summary is untouched. A paste writes the draft column and
    # nothing else, so nobody's hand-written public text is replaced by a paste
    # they have not read back. (C21-02)
    expect(find("[data-testid='textarea-llm-summary']").value).to eq(published_summary)
    expect(bill.reload.summary).to eq(published_summary)

    # @lat: [[paste-summary-dialog#Publishing replaces the previous positions set]]
    navigate_to_positions_tab(bill)
    expect(page).to have_css("[data-testid='org-position-card-pasted-coalition-0']", wait: 10)
    expect(page).to have_no_css("[data-testid='org-position-card-test-org-0']")
    # The bill has testimony, so there is no "positions dropped" notice. This
    # example really is showing the acceptance path.
    expect(page).to have_no_css("[data-testid='llm-no-testimony']")
  end

  # The drop path, now exercised ON PURPOSE instead of by accident. This is what
  # the happy path above was really doing, so fixing that example without adding
  # this one would have traded a mislabelled test for no test at all.
  it "REAS-01: pasted positions are dropped on a bill with no testimony, and the operator is told why" do
    bill.bill_llm_provisioning.update!(extracted_testimony: nil, supplemental_testimony: nil)

    sign_in_as(@sway_admin_user)
    navigate_to_llm_accordion(bill)

    click_testid("btn-paste-summary-completed")
    expect(page).to have_css("[data-testid='paste-summary-dialog']")

    paste_summary_json_and_validate(JSON.generate(valid_payload))

    # The summary text itself is accepted. The paste is not thrown out whole,
    # so the operator's good work survives — as a draft beside the box, which is
    # where every paste lands.
    expect(page).to have_css(
      "[data-testid='llm-draft-body']",
      text: "Operator-pasted brief one-line summary.",
      wait: 10
    )

    # The position is not accepted: no card, and a notice says why.
    navigate_to_positions_tab(bill)
    expect(page).to have_no_css("[data-testid='org-position-card-pasted-coalition-0']")
    expect(page).to have_css("[data-testid='llm-no-testimony']", wait: 10)
  end

  it "reject path: malformed JSON keeps dialog open + renders error list + summary unchanged" do
    # Save a draft first so we can check it stays put after the paste is
    # rejected. The published summary is already set in the before block, and
    # both columns are checked below: a rejected paste moves neither.
    bill.bill_llm_provisioning.update!(
      llm_summary: "Original summary that must remain.",
      llm_generated_at: 1.hour.ago
    )

    sign_in_as(@sway_admin_user)
    navigate_to_llm_accordion(bill)

    click_testid("btn-paste-summary-completed")
    expect(page).to have_css("[data-testid='paste-summary-dialog']")

    # @lat: [[paste-summary-dialog#The rejected payload leaves the published summary unchanged]]
    paste_summary_json_and_validate('{"draft_org_positions": []}')

    expect(page).to have_css("[data-testid='paste-summary-errors']", wait: 10)
    # And it stayed open through that round-trip, so the operator can correct
    # the payload in place.
    expect(page).to have_css("[data-testid='paste-summary-dialog']")
    # Neither column moved. The published summary is still in the box, and the
    # earlier draft is still the one offered beside it.
    expect(find("[data-testid='textarea-llm-summary']").value).to eq(published_summary)
    expect(page).to have_css(
      "[data-testid='llm-draft-body']",
      text: "Original summary that must remain."
    )
    expect(bill.reload.summary).to eq(published_summary)
    expect(bill.bill_llm_provisioning.reload.llm_summary).to eq(
      "Original summary that must remain."
    )
  end
end
