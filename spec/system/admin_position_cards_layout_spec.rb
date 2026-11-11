# frozen_string_literal: true

require "rails_helper"

# @lat: [[tab-strips-at-narrow-viewports#Why the layout backstops need a real browser]]
RSpec.describe "Admin position card layout",
  type: :system,
  js: true,
  phase67: true do
  let(:admin_phone) { "4105551239" }
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

  # Small letters, well inside the model's read window, so nothing is left out
  # and the coverage gate never enters this spec's picture. Every body is
  # generated to exactly the length its entry claims and "text" is those
  # bodies joined, so an offset can never point past the end.
  def letter_chars = 400

  # The figure 67-UI-SPEC.md's E7 and E8 long-text rows name.
  def long_text_chars = 40_000

  # A one-line clamp and a two-line clamp, with room for the rounding a
  # theme's own line-height introduces. A single unclamped 40,000-character
  # string is several hundred lines tall at this width, so nothing near these
  # numbers can pass by accident.
  def one_line_ceiling = 1.6

  def two_line_ceiling = 2.6

  def phrase_marker = "zqxjphrasemarker"

  def campaign_name_marker = "zqxjcampaignmarker"

  def padded(prefix, length) = "#{prefix} ".ljust(length, "long ")[0, length]

  def letter_body(sender)
    "From: #{sender}\nI ask the council to pass this bill.\n"
      .ljust(letter_chars, " ")[0, letter_chars]
  end

  # The 40,000-character quoted phrase E8's long-text row names. It arrives
  # through the cleaned artifact, which is testimony — a channel anyone can
  # write to — so this is the length the card really has to survive.
  def card_claimed_letter
    {
      "position" => 0, "character_offset" => 0, "characters" => letter_chars,
      "sender_address" => "dana@example.com", "sender_domain" => "example.com",
      "source_kind" => "person_speaking_for_org",
      "source_evidence" => {
        "phrase" => padded(phrase_marker, long_text_chars),
        "role" => "Executive Director",
        "sender" => "dana@example.com",
        "org_name" => padded(phrase_marker, long_text_chars)
      }
    }
  end

  def card_campaign_letter(position)
    {
      "position" => position, "character_offset" => position * letter_chars,
      "characters" => letter_chars,
      "sender_address" => "sender#{position}@everyactioncustom.com",
      "sender_domain" => "everyactioncustom.com",
      "source_kind" => "person_speaking_for_self", "source_evidence" => nil
    }
  end

  def card_cleaned_artifact
    letters = [card_claimed_letter] + (1..2).map { |position| card_campaign_letter(position) }
    text = letters.map { |letter| letter_body(letter["sender_address"]) }.join

    {
      "version" => 1,
      "text" => text,
      "counts" => {"raw_chars" => text.length, "cleaned_chars" => text.length},
      "letters" => letters,
      "campaign_drafts" => [
        {
          "id" => "campaigngroup0001",
          "letter_positions" => [1, 2],
          "campaign_origin" => true,
          "sender_count" => 324,
          "letter_count" => 324,
          "added_words" => "and here is why " * 20,
          "senders_added_words_left_out" => 0,
          "dominant_domain" => "everyactioncustom.com"
        }
      ]
    }
  end

  def seed_cards!
    artifact = card_cleaned_artifact
    # :completed is what makes BillCreatorLlmSummaryStatus render
    # LlmSummaryCompletedView, and with it LlmSummaryOrgPositions — the
    # component that renders campaign and claimed-affiliation cards at all.
    create(
      :bill_llm_provisioning,
      :completed,
      bill: bill,
      extracted_testimony: artifact["text"],
      cleaned_testimony: artifact,
      cleaned_testimony_at: Time.zone.now
    )
  end

  def positions_tab_path = "/admin/bill_creator/#{bill.id}/positions?sway_locale_id=#{bill.sway_locale_id}"

  def campaign_card_selector = "[data-testid='campaign-position-card-campaign-campaigngroup0001']"

  def claimed_card_selector = "[data-testid='claimed-affiliation-card-claimed-affiliation-0']"

  # Edit is the one control that puts E7's name field — the field a long
  # name is pasted into — on screen. It does not exist until the card is
  # being edited.
  def open_campaign_editor!
    click_testid("btn-edit-campaign-position")
    expect(page).to have_css("[data-testid='input-campaign-name']")
  end

  it "fits the campaign card and the claimed-affiliation card into a 320px viewport" do
    seed_cards!
    sign_in_as(@sway_admin_user)

    with_narrow_viewport do
      visit_narrow positions_tab_path

      expect(page).to have_css(campaign_card_selector, wait: 10)
      expect(page).to have_css(claimed_card_selector, wait: 10)
      # E8: all three evidence rows really rendered. A card shipping one row
      # would satisfy every width rule below by having less in it.
      expect(page).to have_css("[data-testid='claimed-affiliation-evidence'] dt", count: 3)

      # E7 names the evidence sub-line and the open name editor specifically,
      # so both have to be on screen before the width rule means anything.
      expect(page).to have_text("324 senders · 324 letters · sent through everyactioncustom.com")
      open_campaign_editor!

      # E7 / E8 overflow: one page, so one page-scroll rule covers both cards,
      # the evidence sub-line and the open name editor at once.
      expect_no_horizontal_page_scroll!("the summary tab with both cards and the campaign name editor open")

      # E8: no clipped row label. The three labels wrap onto more lines rather
      # than being cut off — a label an operator cannot read is a row they
      # cannot judge.
      expect(clipped_elements("[data-testid='claimed-affiliation-evidence'] dt")).to eq([])
    end
  end

  it "clamps a 40,000-character name and phrase in every shipped theme at 320px" do
    seed_cards!
    sign_in_as(@sway_admin_user)

    with_narrow_viewport do
      shipped_theme_ids.each do |theme_id|
        choose_theme!(theme_id)
        visit_narrow positions_tab_path

        expect(page).to have_css(campaign_card_selector, wait: 10)
        expect(rendered_theme_id).to eq(theme_id)

        # E7. A stored campaign name cannot be this long —
        # Campaign::MAX_NAME_CHARS stops at 500 — so the path that really puts
        # 40,000 characters of name on this card is an operator pasting one
        # in, which is what this does. Set in one go rather than typed: 40,000
        # keystrokes over the WebDriver wire takes minutes and measures the
        # driver, not the card.
        open_campaign_editor!
        paste_into("[data-testid='input-campaign-name']", padded(campaign_name_marker, long_text_chars))

        expect(page).to have_css("[data-testid='btn-campaign-name-disclosure']", text: "Show full name")

        name_line = text_block_metrics("[data-testid='campaign-name-line']")
        expect(name_line).not_to be_nil, "#{theme_id}: the campaign name line never rendered"
        expect(name_line["text_length"]).to eq(long_text_chars),
          "#{theme_id}: the card is not holding the whole name, so nothing here is about a long one"
        expect(name_line["lines"]).to be <= one_line_ceiling,
          "#{theme_id}: the campaign name rendered #{name_line["lines"].round(1)} lines tall, not one"
        # Clamped text stays selectable: copying a bad name is how an operator
        # reports it, and no utility in this phase may switch selection off.
        expect(name_line["selection_off"]).to be(false), "#{theme_id}: the campaign name cannot be selected"

        # E8. The phrase arrives from the testimony itself, so no operator
        # action is needed to put it on screen.
        expect(page).to have_css(
          "[data-testid='btn-claimed-affiliation-phrase-disclosure']", text: "Show the whole phrase"
        )

        # The first value in the evidence list is always the phrase — the
        # three rows render in a fixed order, phrase, role, sender.
        phrase = text_block_metrics("[data-testid='claimed-affiliation-evidence'] dd")
        expect(phrase).not_to be_nil, "#{theme_id}: the quoted phrase never rendered"
        expect(phrase["text_length"]).to eq(long_text_chars),
          "#{theme_id}: the card is not holding the whole phrase, so nothing here is about a long one"
        expect(phrase["lines"]).to be <= two_line_ceiling,
          "#{theme_id}: the quoted phrase rendered #{phrase["lines"].round(1)} lines tall, not two"
        expect(phrase["selection_off"]).to be(false), "#{theme_id}: the quoted phrase cannot be selected or copied"

        # The card's own title carries the rules' own org_name capture (the bare organization name,
        # no job title) as its starting guess, and clamps to one line for the same reason as the phrase.
        title = text_block_metrics("[data-testid='claimed-affiliation-name-line']")
        expect(title["lines"]).to be <= one_line_ceiling,
          "#{theme_id}: the claimed-affiliation title rendered #{title["lines"].round(1)} lines tall, not one"

        expect_no_horizontal_page_scroll!("the #{theme_id} theme, summary tab, with a 40,000-character name and phrase")
      end
    end
  end
end
