# frozen_string_literal: true

require "rails_helper"

# @lat: [[tab-strips-at-narrow-viewports#Why the layout backstops need a real browser]]
RSpec.describe "Admin Testimony Report layout",
  type: :system,
  js: true,
  phase67: true do
  let(:admin_phone) { "4105551238" }
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  # Fixed rather than the factory's sequenced external_id: the run-pipeline
  # button's label includes it, so a generated length made this file's 320px
  # overflow verdict depend on how many bills earlier examples had created.
  let(:bill) { create(:bill, external_id: "wv9qo", sway_locale: sway_locale, legislator: legislator) }

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

  # Every letter body is generated to exactly the length its entry claims and
  # "text" is those bodies joined, so an offset can never point past the end.
  # A fixture claiming more characters than it holds reports its own letters
  # as never reaching the model, which manufactures a coverage gap and proves
  # nothing about layout.
  def letter_chars = 400

  # The figure 67-UI-SPEC.md's E2 long-text row names.
  def long_phrase_chars = 40_000

  # 22 domains is E9's own figure — bill 62's real distinct sender count.
  def domain_count = 22

  # SendingServicesPanel's own PAGE_SIZE: what one page of the 22 shows.
  def sending_services_page_size = 5

  # Markers that could not appear in the report by accident, carried inside
  # each long string so an absence assertion is about THAT string rather than
  # about the report happening to be short.
  def phrase_marker = "zqxjphrasemarker"

  # Near the 253-character ceiling the naming system itself puts on a domain,
  # in labels no longer than DNS allows. The panel wraps a domain rather than
  # clamping it (E9 long-text), so this is the widest single cell the table
  # has to hold inside 320px.
  def longest_domain = "#{(["a" * 60] * 3).join(".")}.example.com"

  def padded(prefix, length) = "#{prefix} ".ljust(length, "long ")[0, length]

  def letter_body(sender)
    "From: #{sender}\nI ask the council to pass this bill.\n"
      .ljust(letter_chars, " ")[0, letter_chars]
  end

  # One letter read as a person speaking for an organization, carrying the
  # 40,000-character phrase. That phrase is the only attacker-supplied string
  # of any length the pipeline tab is served, so it is what E2's long-text
  # row has to be measured against here.
  def report_claimed_letter(position)
    {
      "position" => position, "character_offset" => position * letter_chars,
      "characters" => letter_chars,
      "sender_address" => "dana@example.com", "sender_domain" => "example.com",
      "source_kind" => "person_speaking_for_org",
      "source_evidence" => {
        "phrase" => padded(phrase_marker, long_phrase_chars),
        "role" => "Executive Director",
        "sender" => "dana@example.com"
      }
    }
  end

  def individual_letter(position)
    {
      "position" => position, "character_offset" => position * letter_chars,
      "characters" => letter_chars,
      "sender_address" => "resident#{position}@example.com", "sender_domain" => "example.com",
      "source_kind" => "person_speaking_for_self", "source_evidence" => nil
    }
  end

  def report_campaign_group(index)
    {
      "id" => "campaigngroup#{index.to_s.rjust(4, "0")}",
      "letter_positions" => [index],
      "campaign_origin" => true,
      "sender_count" => 100 + index,
      "letter_count" => 100 + index,
      "added_words" => "and here is why " * 20,
      "senders_added_words_left_out" => index,
      "dominant_domain" => "everyactioncustom.com"
    }
  end

  def report_cleaned_artifact
    letters = [report_claimed_letter(0)] + (1..5).map { |position| individual_letter(position) }
    text = letters.map { |letter| letter_body(letter["sender_address"]) }.join

    {
      "version" => 1,
      "text" => text,
      "counts" => {"raw_chars" => text.length, "cleaned_chars" => text.length},
      "letters" => letters,
      # Three rows: under TestimonyCampaignTable's own collapse threshold, so
      # the table is on screen rather than folded away behind a disclosure.
      "campaign_drafts" => (1..3).map { |index| report_campaign_group(index) }
    }
  end

  def seed_report!
    artifact = report_cleaned_artifact
    create(
      :bill_llm_provisioning,
      bill: bill,
      extracted_testimony: artifact["text"],
      cleaned_testimony: artifact,
      cleaned_testimony_at: Time.zone.now
    )

    # @lat: [[campaign-approval#An approved campaign is sent back to the page that approved it]]

    Array.new(domain_count) do |index|
      confirmed = index < 3
      domain = index.zero? ? longest_domain : "sending-service-#{index.to_s.rjust(2, "0")}.example.com"
      record = create(
        :sending_service_domain,
        domain: domain,
        label: confirmed ? SendingServiceDomain::CONFIRMED : SendingServiceDomain::NO_LABEL
      )
      create(
        :sending_service_domain_bill,
        sending_service_domain: record, bill: bill,
        sender_count: 10 + index, letter_count: 10 + index,
        machine_sent_letter_count: confirmed ? 10 + index : 0
      )
    end
  end

  def pipeline_tab_path = "/admin/bill_creator/#{bill.id}/pipeline?sway_locale_id=#{bill.sway_locale_id}"

  # Both collapsible panels on this tab remember open/closed in localStorage,
  # which the browser carries between examples. Clearing it here is what makes
  # "22 rows are on screen" a fact about this example rather than about
  # whatever the last spec to touch that key left behind.
  def sign_in_and_clear_panel_state!
    sign_in_as(@sway_admin_user)
    page.execute_script("window.localStorage.clear();")
  end

  it "fits the report, the campaign table and the sending-services panel into a 320px viewport" do
    seed_report!
    sign_in_and_clear_panel_state!

    with_narrow_viewport do
      visit_narrow pipeline_tab_path

      expect(page).to have_css("[data-testid='testimony-report']", wait: 10)
      expect(page).to have_css("[data-testid='sending-services-panel']", wait: 10)
      # A full page of rows really rendered — a panel shipping an empty table
      # would satisfy every width rule below by having nothing in it. The
      # panel pages the 22 seeded domains, and the longest is on page one.
      expect(page).to have_css("[data-testid^='sending-service-row-']", count: sending_services_page_size)
      expect(page).to have_css("[data-testid='testimony-report'] tbody tr", count: 3)

      # E2 / E4 / E9 overflow: one page, so one page-scroll rule covers all
      # three surfaces at once.
      expect_no_horizontal_page_scroll!("the pipeline tab with the report, the campaign table and a page of domains")

      # E4: no clipped cell. A cell in a table that scrolls sideways inside
      # its own container is not clipped — the cell grows and the container
      # scrolls — so a hit here is text an operator can never reach.
      expect(clipped_cells("[data-testid='testimony-report']")).to eq([])
      # E9: the same rule, including the near-253-character domain in row one.
      expect(clipped_cells("[data-testid='sending-services-panel']")).to eq([])

      # Each table carries its own sideways scroll, which is the reason the
      # page body never has to.
      expect(page).to have_css("[data-testid='testimony-report'] [data-slot='table-container'].overflow-x-auto")
      expect(page).to have_css("[data-testid='sending-services-panel'] [data-slot='table-container'].overflow-x-auto")
    end
  end

  it "keeps every testimony string out of the report, in every shipped theme at 320px" do
    seed_report!
    sign_in_and_clear_panel_state!

    with_narrow_viewport do
      shipped_theme_ids.each do |theme_id|
        choose_theme!(theme_id)
        visit_narrow pipeline_tab_path

        expect(page).to have_css("[data-testid='testimony-report']", wait: 10)
        expect(rendered_theme_id).to eq(theme_id)

        # @lat: [[testing-the-toolchain#An assertion that cannot fail proves nothing]]
        carried = served_page_carries(pipeline_tab_path, phrase_marker)
        expect(carried["html_length"]).to be > 40_000,
          "#{theme_id}: the page came back #{carried["html_length"]} characters long — #{carried.inspect}"
        expect(carried[phrase_marker]).to be(true),
          "#{theme_id}: the 40,000-character phrase never reached the page"

        # E2 long-text. The report renders counts only — no campaign name, no
        # quoted phrase, no sender address — so the strongest true statement
        # is not that it clamps them but that it never prints them at all.
        # Read from the report's own subtree: Capybara's page text on an
        # Inertia page includes the whole prop payload, so an unscoped
        # absence assertion could never pass here.
        report_text = rendered_text_within("[data-testid='testimony-report']")
        expect(report_text).not_to be_nil, "#{theme_id}: the report never rendered"
        expect(report_text).not_to include(phrase_marker), "#{theme_id}: a quoted phrase reached the report"

        expect_no_horizontal_page_scroll!("the #{theme_id} theme, pipeline tab")
      end
    end
  end
end
