# frozen_string_literal: true

require "rails_helper"

# A real browser click on "Approve as this campaign", proving it stores a Campaign and
# creates NO Organization row. The request specs prove the same below the
# browser.
RSpec.describe "Admin Campaign Position Approval",
  type: :system,
  js: true,
  phase67: true do
  let(:admin_phone) { "4105551237" }
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:bill) { create(:bill, sway_locale: sway_locale, legislator: legislator) }

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
  end

  # A small bundle, well under the model's read window, with one campaign
  # group already collapsed by Testimony::CampaignMarker's own shape — built
  # by hand here rather than run through the real service, since this spec's
  # job is the browser click and the server write, not re-proving grouping
  # (already proved at the unit level in Plan 04).
  #
  # Every letter's body is generated to exactly the length its entry claims,
  # and "text" is those bodies joined, so an offset can never point past the
  # end. A short placeholder under letters claiming 400 characters made the
  # second letter slice out empty, which reads as "this letter never reached
  # the model": the coverage gate then disabled Approve and the browser
  # clicked a dead button.
  def campaign_letter_chars = 200

  def campaign_letter_body(sender)
    padded = "From: #{sender}\nWe ask you to support this bill.\n"
      .ljust(campaign_letter_chars)
    padded[0, campaign_letter_chars] #: String
  end

  def cleaned_artifact_with_one_campaign
    senders = ["sender.a@everyactioncustom.com", "sender.b@everyactioncustom.com"]
    bodies = senders.map { |sender| campaign_letter_body(sender) }
    text = bodies.join

    {
      "version" => 1,
      "text" => text,
      "counts" => {"raw_chars" => text.length, "cleaned_chars" => text.length},
      "letters" => senders.each_with_index.map do |sender, position|
        {"position" => position, "character_offset" => position * campaign_letter_chars,
         "characters" => campaign_letter_chars,
         "sender_address" => sender, "sender_domain" => "everyactioncustom.com",
         "source_kind" => "person_speaking_for_self", "source_evidence" => nil}
      end,
      "campaign_drafts" => [
        {
          "id" => "campaigngroup0001",
          "letter_positions" => [0, 1],
          "campaign_origin" => true,
          "sender_count" => 2,
          "letter_count" => 2,
          "added_words" => "",
          "senders_added_words_left_out" => 0,
          "dominant_domain" => "everyactioncustom.com"
        }
      ]
    }
  end

  it "creates a campaign on the bill and creates no Organization row" do
    # :completed (a published summary/status) is what makes
    # BillCreatorLlmSummaryStatus render LlmSummaryCompletedView — and with
    # it, LlmSummaryOrgPositions, the component that renders campaign cards
    # at all. Without it, an un-generated row shows only the Generate button.
    create(
      :bill_llm_provisioning,
      :with_testimony,
      :completed,
      bill: bill,
      cleaned_testimony: cleaned_artifact_with_one_campaign,
      cleaned_testimony_at: Time.zone.now
    )

    sign_in_as(@sway_admin_user)
    navigate_to_positions_tab(bill)

    expect(page).to have_css("[data-testid='campaign-stamp']", text: "CAMPAIGN", wait: 10)
    # An unnamed campaign is a COMPLETE record, not a placeholder —
    # never "(unnamed)", never blank.
    expect(page).to have_text("2 people sent this letter")

    organization_count_before = Organization.count
    org_bill_position_count_before = OrganizationBillPosition.count
    campaign_count_before = Campaign.count

    # ApproveCampaignPositionService refuses a blank summary
    # (:summary_required) — Edit first, exactly the way an operator would.
    click_testid("btn-edit-campaign-position")
    find("[data-testid='textarea-campaign-summary']").set(
      "324 people wrote in through this campaign asking the council to pass this bill."
    )
    click_testid("btn-approve-campaign-position")

    # Wait on the side effect itself, not on a UI change — the card never
    # marks itself approved,
    # so a page-content wait here would just be a slower way of proving
    # nothing.
    wait_until { Campaign.count == campaign_count_before + 1 }

    # THE assertion: the campaign approval that just succeeded created no
    # Organization row and no OrganizationBillPosition row of any kind.
    expect(Organization.count).to eq(organization_count_before)
    expect(OrganizationBillPosition.count).to eq(org_bill_position_count_before)

    campaign = Campaign.last
    expect(campaign.bill).to eq(bill)
    expect(campaign.summary).to include("324 people wrote in")
    expect(campaign.sender_count).to eq(2)
    expect(campaign.letter_count).to eq(2)
    expect(campaign.name).to be_nil
  end
end
