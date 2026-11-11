# frozen_string_literal: true

require "rails_helper"

# The acknowledgement
# gate proved in a real browser, not at the unit level alone. Two things a
# unit spec cannot show: that clicking Acknowledge updates the SAME page (no
# full reload) and that the real HTML `disabled` attribute — not a
# JavaScript-only check — is what actually stops the click.
RSpec.describe "Admin Testimony Coverage Acknowledgement",
  type: :system,
  js: true,
  phase67: true do
  let(:admin_phone) { "4105551236" }
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:bill) { create(:bill, sway_locale: sway_locale, legislator: legislator) }

  around do |example|
    original_admin_phones = User::ADMIN_PHONES.dup

    begin
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, [admin_phone])

      with_app_config(:llm, llm_max_positions_chunks: 1) do
        example.run
      end
    ensure
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, original_admin_phones)
    end
  end

  before do
    @sway_admin_user = create(:user, :registered, phone: admin_phone)
    create(:user_legislator, user: @sway_admin_user, legislator: legislator)
  end

  # @lat: [[testimony-coverage-report-invariants#Coverage invariants under windowing and multi-chunk partitioning]]
  def letter_sizes = Array.new(32, 5_000)

  def coverage_letter_body(sender, size)
    padded = "From: #{sender}\nThis organization asks the council to pass this bill.\n"
      .ljust(size, " ")
    padded[0, size] #: String
  end

  def cleaned_artifact_with_something_left_out
    senders = (0...32).map { |i| "person.#{i}@example.com" }
    bodies = senders.each_with_index.map { |sender, i| coverage_letter_body(sender, letter_sizes[i]) }
    text = bodies.join
    offsets = letter_sizes.each_with_object([0]) { |size, acc| acc << acc.last + size }

    {
      "version" => 1,
      "text" => text,
      "counts" => {"raw_chars" => text.length, "cleaned_chars" => text.length},
      "letters" => senders.each_with_index.map do |sender, position|
        {"position" => position, "character_offset" => offsets[position],
         "characters" => letter_sizes[position],
         "sender_address" => sender, "sender_domain" => "example.com",
         "source_kind" => "named_organization", "source_evidence" => nil}
      end,
      "campaign_drafts" => []
    }
  end

  it "blocks Approve until the operator acknowledges, then unblocks it with no page reload" do
    create(
      :bill_llm_provisioning,
      :with_drafts,
      bill: bill,
      cleaned_testimony: cleaned_artifact_with_something_left_out,
      cleaned_testimony_at: Time.zone.now
    )

    sign_in_as(@sway_admin_user)
    navigate_to_positions_tab(bill)

    expect(page).to have_css("[data-testid='btn-approve-org-position']", wait: 10)
    expect(page).to have_css(
      "#llm-testimony-coverage-notice",
      text: "Some testimony did not reach the model"
    )

    # The real `disabled` attribute — checked through Capybara's own element
    # API, not an aria-* convenience — because that attribute is what
    # actually stops the click (BillCreatorOrgPositionCardActions' own
    # documented reason for never using aria-disabled here).
    approve_button = find("[data-testid='btn-approve-org-position']")
    expect(approve_button.disabled?).to be(true)

    # The spoken reason points at the SAME id every card points at — the
    # coverage notice is stated once for the whole list, not once per card.
    expect(approve_button["aria-describedby"]).to include("llm-testimony-coverage-notice")

    # Reject and Edit are never gated by this reason: neither publishes
    # anything, and Reject is the operator's way out of a stale draft.
    expect(find("[data-testid='btn-reject-org-position']").disabled?).to be(false)
    expect(find("[data-testid='btn-edit-org-position']").disabled?).to be(false)

    plant_reload_probe!

    click_button "Acknowledge the missing testimony"

    # Waits for the SERVER's answer, not a client-only flip — the stamp only
    # renders once props.testimony_coverage.acknowledged comes back true from
    # the reload Inertia performs after the acknowledgement POST's redirect.
    expect(page).to have_css("[data-testid='testimony-acknowledged-stamp']", wait: 10)

    # The page that answered is the SAME page — a probe planted on window
    # before the click, still there after. A full document load would have
    # thrown it away.
    expect_no_full_page_load!

    approve_button = find("[data-testid='btn-approve-org-position']")
    expect(approve_button.disabled?).to be(false)
    expect(approve_button["aria-describedby"]).to be_nil

    expect(find("[data-testid='btn-reject-org-position']").disabled?).to be(false)
    expect(find("[data-testid='btn-edit-org-position']").disabled?).to be(false)

    expect(
      TestimonyCoverageAcknowledgement.where(bill: bill, acknowledged_by: @sway_admin_user).count
    ).to eq(1)
  end
end
