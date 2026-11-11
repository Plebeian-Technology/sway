# frozen_string_literal: true

require "rails_helper"

# @lat: [[tab-strips-at-narrow-viewports#What the four standalone admin pages measure]]
RSpec.describe "Standalone admin pages at phone widths", type: :system, js: true do
  phone_widths = [390, 320]

  touch_target_floor = 44

  let(:sway_locale) { create(:sway_locale, :baltimore) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:sway_admin_user) { create(:user, :sway_admin) }

  before { create(:user_legislator, user: sway_admin_user, legislator: legislator) }

  def button_box(label)
    page.evaluate_script(<<~JS)
      (() => {
        const button = Array.from(document.querySelectorAll("button")).find(
          (candidate) => (candidate.textContent || "").trim() === #{label.to_json}
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

  def expect_touch_target!(label, context, floor)
    box = button_box(label)
    expect(box).not_to be_nil, "#{context}: no button labelled #{label.inspect} rendered"
    expect(box["hidden"]).to be(false), "#{context}: the #{label.inspect} button is not visible"
    expect(box["height"]).to be >= floor,
      "#{context}: the #{label.inspect} button laid out #{box["height"].round}px tall, under the #{floor}px floor"
    # @lat: [[tab-strips-at-narrow-viewports#What the four standalone admin pages measure]]
    return if box["in_scroller"]

    expect(box["right"]).to be <= (room_available + NarrowViewportHelpers::OVERFLOW_TOLERANCE_PX),
      "#{context}: the #{label.inspect} button reaches #{box["right"].round}px, past the right edge"
  end

  def table_container_box
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector("[data-slot='table-container']");
        if (!el) return null;
        return {
          overflow_x: window.getComputedStyle(el).overflowX,
          right: el.getBoundingClientRect().right,
          room: document.documentElement.clientWidth,
        };
      })()
    JS
  end

  def expect_table_scrolls_in_its_own_container!(context)
    box = table_container_box
    expect(box).not_to be_nil, "#{context}: no table rendered, so nothing was measured"
    expect(box["overflow_x"]).to eq("auto"),
      "#{context}: the table container's overflow-x is #{box["overflow_x"].inspect}, so a wide table moves the page"
    expect(box["right"]).to be <= (box["room"] + NarrowViewportHelpers::OVERFLOW_TOLERANCE_PX),
      "#{context}: the table container itself reaches #{box["right"].round}px in #{box["room"]}px of room"
  end

  it "keeps the admin hub inside a phone-width viewport" do
    sign_in_as(sway_admin_user)

    phone_widths.each do |width|
      with_narrow_viewport(width: width) do
        visit_narrow "/admin", width: width
        expect(page).to have_text("Tools for managing Sway content, settings, and operator state.", wait: 10)
        expect(page).to have_text("Pipeline Run History")

        expect_no_horizontal_page_scroll!("the admin hub at #{width}px")
      end
    end
  end

  it "keeps the categories page inside a phone-width viewport" do
    bill = create(:bill, sway_locale: sway_locale)
    active = create(:category, name: "Public Safety and Emergency Preparedness")
    create(:bill_category, bill: bill, category: active)
    create(:category, name: "Transportation and Infrastructure", active: false)

    sign_in_as(sway_admin_user)

    phone_widths.each do |width|
      with_narrow_viewport(width: width) do
        visit_narrow "/admin/categories", width: width
        expect(page).to have_text("Category Taxonomy", wait: 10)
        expect(page).to have_text("Public Safety and Emergency Preparedness")

        expect_no_horizontal_page_scroll!("the categories page at #{width}px")
        expect_table_scrolls_in_its_own_container!("the categories page at #{width}px")
        expect_touch_target!("Add category", "the categories page at #{width}px", touch_target_floor)
        expect_touch_target!("Rename", "the categories page at #{width}px", touch_target_floor)
      end
    end
  end

  it "keeps the locales page inside a phone-width viewport" do
    create(:sway_locale, :maryland)
    create(:sway_locale, :congress)

    sign_in_as(sway_admin_user)

    phone_widths.each do |width|
      with_narrow_viewport(width: width) do
        visit_narrow "/admin/locales", width: width
        expect(page).to have_text("Registered users per locale.", wait: 10)
        expect(page).to have_text("U.S. Congress")

        expect_no_horizontal_page_scroll!("the locales page at #{width}px")
        expect_touch_target!("Add sample address", "the locales page at #{width}px", touch_target_floor)
      end
    end
  end

  it "keeps the LLM settings page inside a phone-width viewport" do
    sign_in_as(sway_admin_user)

    phone_widths.each do |width|
      with_narrow_viewport(width: width) do
        visit_narrow "/admin/llm_settings", width: width
        expect(page).to have_text("Model Selection", wait: 10)
        expect(page).to have_css("#summarization-model")
        expect(page).to have_css("#classification-model")

        expect_no_horizontal_page_scroll!("the LLM settings page at #{width}px")
        expect_touch_target!("Save settings", "the LLM settings page at #{width}px", touch_target_floor)
      end
    end
  end
end
