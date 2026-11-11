# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin locales summarization fields at phone widths", type: :system, js: true do
  phone_widths = [390, 320]
  touch_target_floor = 44

  let(:sway_locale) { create(:sway_locale, :baltimore) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:sway_admin_user) { create(:user, :sway_admin) }

  before do
    create(:user_legislator, user: sway_admin_user, legislator: legislator)
    create(
      :llm_bill_summarization_instruction,
      sway_locale: sway_locale,
      news_media_website_urls: [
        "https://www.thebanner.com/baltimore/",
        "https://www.wypr.org/",
        "https://www.baltimoresun.com/location/maryland/baltimore/"
      ],
      legislative_body_makeup: "A 15-member legislative body governing the City of Baltimore."
    )
    create(:sway_locale, :maryland)
  end

  def locale_summarization_button_box(label, aria_controls:)
    page.evaluate_script(<<~JS)
      (() => {
        const button = Array.from(document.querySelectorAll("button")).find(
          (candidate) => (candidate.textContent || "").trim() === #{label.to_json} &&
            candidate.getAttribute("aria-controls") === #{aria_controls.to_json}
        );
        if (!button) return null;
        const rect = button.getBoundingClientRect();
        const style = window.getComputedStyle(button);
        let inScroller = false;
        for (let node = button.parentElement; node && node !== document.documentElement; node = node.parentElement) {
          const overflowX = window.getComputedStyle(node).overflowX;
          if (overflowX === "auto" || overflowX === "scroll") { inScroller = true; break; }
        }
        return {
          height: rect.height,
          width: rect.width,
          right: rect.right,
          in_scroller: inScroller,
          hidden:
            style.visibility === "hidden" ||
            style.display === "none" ||
            rect.width === 0 ||
            rect.height === 0,
        };
      })()
    JS
  end

  def room_available = page.evaluate_script("document.documentElement.clientWidth")

  def expect_locale_summarization_touch_target!(label, context, floor, aria_controls:)
    box = locale_summarization_button_box(label, aria_controls: aria_controls)
    expect(box).not_to be_nil, "#{context}: no button labelled #{label.inspect} rendered"
    expect(box["hidden"]).to be(false), "#{context}: the #{label.inspect} button is not visible"
    expect(box["height"]).to be >= floor,
      "#{context}: the #{label.inspect} button laid out #{box["height"].round}px tall, under the #{floor}px floor"
    return if box["in_scroller"]

    expect(box["right"]).to be <= (room_available + NarrowViewportHelpers::OVERFLOW_TOLERANCE_PX),
      "#{context}: the #{label.inspect} button reaches #{box["right"].round}px, past the right edge"
  end

  # @lat: [[tab-strips-at-narrow-viewports#What the four standalone admin pages measure]]
  it "keeps the locales page with summarization expanded inside phone viewports without overflow and with >=44px touch targets" do
    sign_in_as(sway_admin_user)

    phone_widths.each do |width|
      with_narrow_viewport(width: width) do
        visit_narrow "/admin/locales", width: width
        expect(page).to have_text("Registered users per locale.", wait: 10)
        expect(page).to have_text("Baltimore")
        expect(page).to have_css('button[aria-controls$="-summarization"]', minimum: 2)
        panel_id = "locale-#{sway_locale.id}-summarization"

        # Check Summarization button before expanding
        expect_locale_summarization_touch_target!(
          "Summarization",
          "the locales page at #{width}px",
          touch_target_floor,
          aria_controls: panel_id
        )

        # Click Summarization to expand fields
        find("button[aria-controls='#{panel_id}']", text: "Summarization").click

        within("##{panel_id}") do
          expect(page).to have_text("Newsroom sources")
          expect(page).to have_text("Authoritative · Locale configuration")
          expect(page).to have_text("Legislative body makeup")
          expect(page).to have_text("Immutable · Prompt defense")
          expect(page).to have_text("A 15-member legislative body")
        end

        # Verify NO horizontal page scroll with summarization expanded
        expect_no_horizontal_page_scroll!("the locales page with summarization expanded at #{width}px")

        # Verify the preformatted text container does not push past viewport
        pre_right = page.evaluate_script(<<~JS)
          document.querySelector("##{panel_id} pre").getBoundingClientRect().right
        JS
        expect(pre_right).to be <= (room_available + NarrowViewportHelpers::OVERFLOW_TOLERANCE_PX),
          "pre element right edge #{pre_right} exceeded room available #{room_available}"

        # Collapse again and verify
        find("button[aria-controls='#{panel_id}']", text: "Summarization").click
        expect(page).to have_no_text("Newsroom sources")
        expect_no_horizontal_page_scroll!("the locales page after collapsing summarization at #{width}px")
      end
    end
  end
end
