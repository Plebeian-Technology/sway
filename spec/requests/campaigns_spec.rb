# frozen_string_literal: true

require "rails_helper"

# The endpoint behind Surface 4's "Approve as this
# campaign" button.

RSpec.describe "Campaigns admin gate", type: :request do
  include_examples "requires sway admin",
    verb: :post,
    path: "/bills/1/campaigns"
end

RSpec.describe "Campaign draft rejection admin gate", type: :request do
  include_examples "requires sway admin",
    verb: :post,
    path: "/bills/1/campaigns/reject_draft",
    params: {content_hash: "grp1"}
end

RSpec.describe "Campaign draft restore admin gate", type: :request do
  include_examples "requires sway admin",
    verb: :post,
    path: "/bills/1/campaigns/restore_draft",
    params: {content_hash: "grp1"}
end

RSpec.describe "Campaign draft mark individual admin gate", type: :request do
  include_examples "requires sway admin",
    verb: :post,
    path: "/bills/1/campaigns/mark_individual_draft",
    params: {content_hash: "grp1"}
end

RSpec.describe "POST /bills/:bill_id/campaigns", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:admin) { create(:user, :sway_admin) }

  let(:bill) do
    legislator = sway_locale.legislators.first
    create(:bill, sway_locale: sway_locale, legislator: legislator)
  end

  before do
    session_hash[:user_id] = admin.id
  end

  def campaign_group(id:, sender_count: 3, letter_count: 3)
    {
      "id" => id, "letter_positions" => [], "shared_text" => "shared template line",
      "sender_count" => sender_count, "letter_count" => letter_count,
      "added_words" => "", "senders_added_words_left_out" => 0
    }
  end

  def campaign_artifact(raw_chars:, cleaned_chars:, groups: [], letters: [])
    {
      "version" => 1, "text" => "C" * cleaned_chars,
      "counts" => {"raw_chars" => raw_chars, "cleaned_chars" => cleaned_chars},
      "letters" => letters, "campaign_drafts" => groups
    }
  end

  describe "a successful approval" do
    let!(:provisioning) do
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "R" * 900,
        cleaned_testimony: campaign_artifact(
          raw_chars: 900, cleaned_chars: 900, groups: [campaign_group(id: "grp1")]
        ),
        cleaned_testimony_at: 1.hour.ago)
    end

    # @lat: [[campaign-approval#An approved campaign is sent back to the page that approved it]]
    it "ships the approved campaign back to the creator page, keyed to the draft it came from" do
      post bill_campaigns_path(bill),
        params: {name: "Complete Streets Letter", support: "support", summary: "Backs it", content_hash: "grp1"}

      get summary_bill_creator_path(bill)

      campaigns = inertia.props[:campaigns]
      expect(campaigns.length).to eq(1)
      expect(campaigns.first).to include(
        name: "Complete Streets Letter", support: "FOR", source_campaign_draft_hash: "grp1"
      )
    end

    it "ships an empty campaigns prop on a bill nobody has approved a campaign on" do
      get summary_bill_creator_path(bill)

      expect(inertia.props[:campaigns]).to eq([])
    end

    it "redirects to the positions tab and stores a campaign on the bill" do
      post bill_campaigns_path(bill),
        params: {name: "Complete Streets Letter", support: "support", summary: "Backs it", content_hash: "grp1"}

      expect(response).to redirect_to(positions_bill_creator_path(bill))
      campaign = Campaign.find_by(name: "Complete Streets Letter", bill: bill)
      expect(campaign).not_to be_nil
      expect(Organization.count).to eq(0)
    end

    it "reports back a success notice, not an error" do
      post bill_campaigns_path(bill),
        params: {name: "Complete Streets Letter", support: "support", summary: "Backs it", content_hash: "grp1"}
      follow_redirect!

      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props[:errors]).to be_blank
    end
  end

  describe "every refusal reaches the operator by name, under the campaign_position key" do
    let!(:provisioning) do
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "R" * 900,
        cleaned_testimony: campaign_artifact(
          raw_chars: 900, cleaned_chars: 900, groups: [campaign_group(id: "grp1")]
        ),
        cleaned_testimony_at: 1.hour.ago)
    end

    it "refuses with a message when the summary is blank" do
      post bill_campaigns_path(bill),
        params: {name: "A Campaign", support: "support", summary: "  ", content_hash: "grp1"}
      follow_redirect!

      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props[:errors][:campaign_position]).to match(/summary/i)
      expect(Campaign.count).to eq(0)
    end

    it "refuses with a message for an invalid stance" do
      post bill_campaigns_path(bill),
        params: {name: "A Campaign", support: "sideways", summary: "Backs it", content_hash: "grp1"}
      follow_redirect!

      expect(inertia.props[:errors][:campaign_position]).to match(/stance/i)
    end

    it "refuses with a message when the draft no longer matches (content_hash mismatch)" do
      post bill_campaigns_path(bill),
        params: {name: "A Campaign", support: "support", summary: "Backs it", content_hash: "stale-hash"}
      follow_redirect!

      expect(inertia.props[:errors][:campaign_position]).to match(/changed/i)
      expect(Campaign.count).to eq(0)
    end

    it "refuses with a message while a clean-testimony run is in progress" do
      provisioning.update!(generation_status: "pending")

      post bill_campaigns_path(bill),
        params: {name: "A Campaign", support: "support", summary: "Backs it", content_hash: "grp1"}
      follow_redirect!

      expect(inertia.props[:errors][:campaign_position]).to match(/progress/i)
    end

    it "refuses with a message when testimony coverage was not acknowledged" do
      with_app_config(:llm, llm_max_positions_chunks: 1) do
        letters = (0...32).map do |position|
          {"position" => position, "character_offset" => position * 5_000, "characters" => 5_000,
           "sender_address" => nil, "sender_domain" => nil,
           "source_kind" => "named_organization", "source_evidence" => nil}
        end
        provisioning.update!(
          extracted_testimony: "R" * 165_000,
          cleaned_testimony: campaign_artifact(
            raw_chars: 165_000, cleaned_chars: 160_000,
            groups: [campaign_group(id: "grp1")],
            letters: letters
          ),
          cleaned_testimony_at: 1.hour.ago
        )

        post bill_campaigns_path(bill),
          params: {name: "A Campaign", support: "support", summary: "Backs it", content_hash: "grp1"}
        follow_redirect!

        expect(inertia.props[:errors][:campaign_position]).to match(/acknowledge/i)
        expect(Campaign.count).to eq(0)
      end
    end

    # CR-03: the card always names a draft, so a request without one is a
    # stale or hand-written client, and every guard on this endpoint used to
    # skip itself when identity was absent — including the coverage gate this
    # phase exists to enforce.
    it "refuses a request that names no draft at all, and writes nothing" do
      post bill_campaigns_path(bill),
        params: {name: "A Campaign", support: "support", summary: "Backs it"}
      follow_redirect!

      expect(inertia.props[:errors][:campaign_position]).to eq(
        "A campaign was named with no draft identity to check it against"
      )
      expect(Campaign.count).to eq(0)
    end

    # W6: an :index the endpoint no longer reads must not
    # change the outcome — a stale client still sending one approves normally
    # rather than being refused for naming a position that has since moved.
    it "ignores a leftover index from an older client" do
      post bill_campaigns_path(bill),
        params: {name: "A Campaign", support: "support", summary: "Backs it",
                 index: "41", content_hash: "grp1"}
      follow_redirect!

      expect(Campaign.sole.name).to eq("A Campaign")
    end

    # @lat: [[campaign-approval#Approving over a name already taken is reported, not refused]]
    it "says so in the flash when an approval replaced a decision made from a different draft" do
      provisioning.update!(cleaned_testimony: campaign_artifact(
        raw_chars: 900, cleaned_chars: 900,
        groups: [campaign_group(id: "grp1"), campaign_group(id: "grp2")]
      ))
      post bill_campaigns_path(bill),
        params: {name: "A Campaign", support: "support", summary: "Backs it", content_hash: "grp1"}

      post bill_campaigns_path(bill),
        params: {name: "A Campaign", support: "oppose", summary: "Against it", content_hash: "grp2"}
      follow_redirect!

      expect(flash[:notice]).to match(/replacing an earlier decision/i)
      expect(Campaign.sole.support).to eq("AGAINST")
    end
  end
end

# Reject used to be a client-only dismiss. The decision is now
# stored on the bill's provisioning row, keyed on the draft's content hash so
# it survives a re-run of the clean-testimony stage.
RSpec.describe "POST /bills/:bill_id/campaigns/reject_draft", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:admin) { create(:user, :sway_admin) }

  let(:bill) do
    legislator = sway_locale.legislators.first
    create(:bill, sway_locale: sway_locale, legislator: legislator)
  end

  def campaign_group(id:, sender_count: 3, letter_count: 3)
    {
      "id" => id, "letter_positions" => [], "shared_text" => "shared template line",
      "sender_count" => sender_count, "letter_count" => letter_count,
      "added_words" => "", "senders_added_words_left_out" => 0
    }
  end

  def campaign_artifact(raw_chars:, cleaned_chars:, groups: [], letters: [])
    {
      "version" => 1, "text" => "C" * cleaned_chars,
      "counts" => {"raw_chars" => raw_chars, "cleaned_chars" => cleaned_chars},
      "letters" => letters, "campaign_drafts" => groups
    }
  end

  let!(:provisioning) do
    create(:bill_llm_provisioning, bill: bill,
      extracted_testimony: "R" * 900,
      cleaned_testimony: campaign_artifact(
        raw_chars: 900, cleaned_chars: 900, groups: [campaign_group(id: "grp1"), campaign_group(id: "grp2")]
      ),
      cleaned_testimony_at: 1.hour.ago)
  end

  before do
    session_hash[:user_id] = admin.id
  end

  it "stores the rejection against the bill, keyed on the draft's content hash" do
    post reject_draft_bill_campaigns_path(bill), params: {content_hash: "grp1"}

    expect(provisioning.reload.rejected_campaign_draft_hash_list).to eq(["grp1"])
  end

  it "keeps the rejection when the clean-testimony artifact is rewritten and the drafts reorder" do
    post reject_draft_bill_campaigns_path(bill), params: {content_hash: "grp1"}

    provisioning.reload.update!(cleaned_testimony: campaign_artifact(
      raw_chars: 900, cleaned_chars: 900,
      groups: [campaign_group(id: "grp2"), campaign_group(id: "grp1")]
    ))

    expect(provisioning.reload.campaign_draft_rejected?("grp1")).to be(true)
    expect(provisioning.campaign_draft_rejected?("grp2")).to be(false)
  end

  it "is idempotent" do
    2.times { post reject_draft_bill_campaigns_path(bill), params: {content_hash: "grp1"} }

    expect(provisioning.reload.rejected_campaign_draft_hash_list).to eq(["grp1"])
  end

  it "refuses a request that names no draft" do
    post reject_draft_bill_campaigns_path(bill), params: {content_hash: ""}
    follow_redirect!

    expect(inertia).to render_component(Pages::BILL_CREATOR)
    expect(inertia.props[:errors][:campaign_position]).to eq(
      "A campaign draft was named with no identity to check it against"
    )
    expect(provisioning.reload.rejected_campaign_draft_hash_list).to eq([])
  end

  it "restores a rejected draft" do
    post reject_draft_bill_campaigns_path(bill), params: {content_hash: "grp1"}
    post restore_draft_bill_campaigns_path(bill), params: {content_hash: "grp1"}

    expect(provisioning.reload.rejected_campaign_draft_hash_list).to eq([])
  end

  it "ships the stored decision back to the card as a prop" do
    post reject_draft_bill_campaigns_path(bill), params: {content_hash: "grp1"}

    get summary_bill_creator_path(bill)

    expect(inertia).to render_component(Pages::BILL_CREATOR)
    drafts = inertia.props[:testimony_campaign_drafts]
    expect(drafts.find { |d| d[:content_hash] == "grp1" }[:rejected]).to be(true)
    expect(drafts.find { |d| d[:content_hash] == "grp2" }[:rejected]).to be(false)
  end
end

RSpec.describe "POST /bills/:bill_id/campaigns/mark_individual_draft", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:admin) { create(:user, :sway_admin) }

  let(:bill) do
    legislator = sway_locale.legislators.first
    create(:bill, sway_locale: sway_locale, legislator: legislator)
  end

  def campaign_group(id:, sender_count: 3, letter_count: 3)
    {
      "id" => id, "letter_positions" => [], "shared_text" => "shared template line",
      "sender_count" => sender_count, "letter_count" => letter_count,
      "added_words" => "", "senders_added_words_left_out" => 0
    }
  end

  def campaign_artifact(raw_chars:, cleaned_chars:, groups: [], letters: [])
    {
      "version" => 1, "text" => "C" * cleaned_chars,
      "counts" => {"raw_chars" => raw_chars, "cleaned_chars" => cleaned_chars},
      "letters" => letters, "campaign_drafts" => groups
    }
  end

  let!(:provisioning) do
    create(:bill_llm_provisioning, bill: bill,
      extracted_testimony: "R" * 900,
      cleaned_testimony: campaign_artifact(
        raw_chars: 900, cleaned_chars: 900, groups: [campaign_group(id: "grp1"), campaign_group(id: "grp2")]
      ),
      cleaned_testimony_at: 1.hour.ago)
  end

  before do
    session_hash[:user_id] = admin.id
  end

  it "stores the individual marking against the bill, keyed on the draft's content hash" do
    post mark_individual_draft_bill_campaigns_path(bill), params: {content_hash: "grp1"}

    expect(provisioning.reload.individual_campaign_draft_hash_list).to eq(["grp1"])
  end

  it "keeps the individual marking when the clean-testimony artifact is rewritten and the drafts reorder" do
    post mark_individual_draft_bill_campaigns_path(bill), params: {content_hash: "grp1"}

    provisioning.reload.update!(cleaned_testimony: campaign_artifact(
      raw_chars: 900, cleaned_chars: 900,
      groups: [campaign_group(id: "grp2"), campaign_group(id: "grp1")]
    ))

    expect(provisioning.reload.campaign_draft_individual?("grp1")).to be(true)
    expect(provisioning.campaign_draft_individual?("grp2")).to be(false)
  end

  it "is idempotent" do
    2.times { post mark_individual_draft_bill_campaigns_path(bill), params: {content_hash: "grp1"} }

    expect(provisioning.reload.individual_campaign_draft_hash_list).to eq(["grp1"])
  end

  it "is mutually exclusive with rejection" do
    post reject_draft_bill_campaigns_path(bill), params: {content_hash: "grp1"}
    expect(provisioning.reload.campaign_draft_rejected?("grp1")).to be(true)
    expect(provisioning.campaign_draft_individual?("grp1")).to be(false)

    post mark_individual_draft_bill_campaigns_path(bill), params: {content_hash: "grp1"}
    expect(provisioning.reload.campaign_draft_rejected?("grp1")).to be(false)
    expect(provisioning.campaign_draft_individual?("grp1")).to be(true)

    post reject_draft_bill_campaigns_path(bill), params: {content_hash: "grp1"}
    expect(provisioning.reload.campaign_draft_rejected?("grp1")).to be(true)
    expect(provisioning.campaign_draft_individual?("grp1")).to be(false)
  end

  it "refuses a request that names no draft" do
    post mark_individual_draft_bill_campaigns_path(bill), params: {content_hash: "   "}
    follow_redirect!

    expect(inertia).to render_component(Pages::BILL_CREATOR)
    expect(inertia.props[:errors][:campaign_position]).to eq(
      "A campaign draft was named with no identity to check it against"
    )
    expect(provisioning.reload.individual_campaign_draft_hash_list).to eq([])
  end

  it "clears individual_campaign_draft_hashes when the draft is subsequently approved as a campaign" do
    post mark_individual_draft_bill_campaigns_path(bill), params: {content_hash: "grp1"}
    expect(provisioning.reload.campaign_draft_individual?("grp1")).to be(true)

    post bill_campaigns_path(bill), params: {
      name: "Coalition Campaign",
      support: "support",
      summary: "We support this bill.",
      content_hash: "grp1"
    }

    expect(provisioning.reload.campaign_draft_individual?("grp1")).to be(false)
  end

  it "restores a marked-individual draft" do
    post mark_individual_draft_bill_campaigns_path(bill), params: {content_hash: "grp1"}
    post restore_draft_bill_campaigns_path(bill), params: {content_hash: "grp1"}

    expect(provisioning.reload.individual_campaign_draft_hash_list).to eq([])
  end

  it "ships the stored decision back to the card as a prop" do
    post mark_individual_draft_bill_campaigns_path(bill), params: {content_hash: "grp1"}

    get summary_bill_creator_path(bill)

    expect(inertia).to render_component(Pages::BILL_CREATOR)
    drafts = inertia.props[:testimony_campaign_drafts]
    expect(drafts.find { |d| d[:content_hash] == "grp1" }[:marked_individual]).to be(true)
    expect(drafts.find { |d| d[:content_hash] == "grp2" }[:marked_individual]).to be(false)
  end
end

# The SECOND approval — which organization is behind an approved
# campaign. Sits beside the position approval and never changes it.
RSpec.describe "POST /bills/:bill_id/campaigns/:id/link_organization", type: :request do
  include_examples "requires sway admin",
    verb: :post,
    path: "/bills/1/campaigns/1/link_organization",
    params: {decision: "none"}
end

RSpec.describe "POST /bills/:bill_id/campaigns/:id/link_organization behaviour", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:admin) { create(:user, :sway_admin) }

  let(:bill) do
    legislator = sway_locale.legislators.first
    create(:bill, sway_locale: sway_locale, legislator: legislator)
  end

  let(:campaign) { create(:campaign, bill: bill) }
  let(:organization) { create(:organization, sway_locale: sway_locale) }

  before { session_hash[:user_id] = admin.id }

  it "records the organization behind the campaign" do
    post link_organization_bill_campaign_path(bill, campaign),
      params: {decision: "linked", organization_id: organization.id}

    expect(campaign.reload.organization_id).to eq(organization.id)
    expect(campaign.organization_link_decision).to eq(Campaign::LINKED)
  end

  it "creates a new organization in the bill's locale and links it when organization_name is provided" do
    other_locale = create(:sway_locale, :maryland)
    cookies[:sway_locale_id] = other_locale.id

    expect {
      post link_organization_bill_campaign_path(bill, campaign),
        params: {decision: "linked", organization_name: "Baltimore Bike Coalition"}
    }.to change(Organization, :count).by(1)

    created = Organization.find_by!(name: "Baltimore Bike Coalition", sway_locale: sway_locale)
    expect(campaign.reload.organization_id).to eq(created.id)
    expect(campaign.organization_link_decision).to eq(Campaign::LINKED)

    follow_redirect!
    expect(inertia.props[:organizations].pluck(:id)).to include(created.id)
  end

  it "refuses an overlong organization_name" do
    post link_organization_bill_campaign_path(bill, campaign),
      params: {decision: "linked", organization_name: "A" * (Campaign::MAX_NAME_CHARS + 1)}
    follow_redirect!

    expect(inertia).to render_component(Pages::BILL_CREATOR)
    expect(inertia.props[:errors][:campaign_organization]).to eq(
      "Organization name must be #{Campaign::MAX_NAME_CHARS} characters or fewer"
    )
    expect(campaign.reload.organization_link_decision).to be_nil
  end

  it "records that there is no organization behind the campaign" do
    post link_organization_bill_campaign_path(bill, campaign), params: {decision: "none"}

    expect(campaign.reload.organization_link_decision).to eq(Campaign::NO_ORGANIZATION)
    expect(campaign.organization_id).to be_nil
  end

  it "records that the organization is not determinable yet" do
    post link_organization_bill_campaign_path(bill, campaign), params: {decision: "undetermined"}

    expect(campaign.reload.organization_link_decision).to eq(Campaign::UNDETERMINED)
  end

  it "refuses an organization from a different locale than the bill" do
    stranger = create(:organization, sway_locale: create(:sway_locale, :maryland))

    post link_organization_bill_campaign_path(bill, campaign),
      params: {decision: "linked", organization_id: stranger.id}

    expect(campaign.reload.organization_link_decision).to be_nil
    expect(flash[:errors] || response).to be_truthy
  end

  it "refuses a campaign that no longer exists" do
    post link_organization_bill_campaign_path(bill, 0), params: {decision: "none"}

    expect(response).to have_http_status(:found)
  end

  # The decision has to come back as a prop, or the card cannot show it and the
  # operator cannot tell an answered question from an unanswered one.
  it "ships the decision back to the card as a prop" do
    post link_organization_bill_campaign_path(bill, campaign),
      params: {decision: "linked", organization_id: organization.id}
    follow_redirect!

    expect(inertia).to render_component(Pages::BILL_CREATOR)
    shipped = inertia.props[:campaigns].find { |c| c[:id] == campaign.id }
    expect(shipped[:organization_link_decision]).to eq(Campaign::LINKED)
    expect(shipped[:organization_id]).to eq(organization.id)
    expect(shipped[:organization_name]).to eq(organization.name)
  end
end
