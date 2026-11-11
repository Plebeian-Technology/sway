# frozen_string_literal: true

require "rails_helper"

# @lat: [[tab-strips-at-narrow-viewports#Tab strips at a narrow viewport#What the four pages measure]]
RSpec.describe "Reader tab strips at a narrow viewport", type: :system, js: true do
  let(:phone) { "4105551244" }
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:organization) { create(:organization, sway_locale: sway_locale) }

  before do
    @signed_in_user = create(:user, :registered, phone: phone, registration_status: "completed")
    term = create(:legislator_term, legislator: legislator, district: district)
    user_legislator = create(:user_legislator, user: @signed_in_user, legislator: legislator, active: true)
    create(
      :user_legislator_term_score,
      user_legislator: user_legislator,
      legislator_term: term,
      count_agreed: 3,
      count_disagreed: 1,
      count_no_legislator_vote: 0,
      count_legislator_abstained: 0
    )
    @membership = create(
      :user_organization_membership,
      user: @signed_in_user,
      organization: organization,
      role: :admin,
      status: :active
    )
  end

  # The rightmost edge the tab strip reaches, in CSS pixels.
  def tab_strip_right_edge
    page.evaluate_script(<<~JS)
      (() => {
        const list = document.querySelector("[data-slot='tabs-list']");
        if (!list) return -1;
        const edges = Array.from(list.querySelectorAll("[data-slot='tabs-trigger']"))
          .map((trigger) => trigger.getBoundingClientRect().right);
        return Math.ceil(Math.max(list.getBoundingClientRect().right, ...edges));
      })()
    JS
  end

  def viewport_width = page.evaluate_script("window.innerWidth")

  def expect_tab_strip_inside_viewport!(context)
    edge = tab_strip_right_edge
    expect(edge).to be_positive, "#{context}: no tab strip was rendered"
    expect(edge).to be <= (viewport_width + 1),
      "#{context}: the tab strip reaches #{edge}px in a #{viewport_width}px viewport"
  end

  def expect_controls_inside_parent!(context)
    overflows = page.evaluate_script(<<~JS)
      (() => {
        const select = document.querySelector("#v2-locale");
        const startVoting = document.querySelector("a[href='/bill_of_the_month']");
        const out = [];
        for (const [label, el] of [["locale select", select], ["Start voting link", startVoting]]) {
          if (!el || !el.parentElement) {
            out.push(`${label} missing`);
            continue;
          }
          const rect = el.getBoundingClientRect();
          const parentRect = el.parentElement.getBoundingClientRect();
          if (rect.right > parentRect.right + 1 || rect.left < parentRect.left - 1) {
            out.push(`${label} (${Math.round(rect.left)}..${Math.round(rect.right)}) overflows parent (${Math.round(parentRect.left)}..${Math.round(parentRect.right)})`);
          }
        }
        return out;
      })()
    JS
    expect(overflows).to be_empty, "#{context}: #{overflows.join("; ")}"
  end

  it "keeps the representatives list from scrolling sideways at 320px across every theme" do
    create(:sway_locale, :baltimore)
    sign_in_as(@signed_in_user)

    with_narrow_viewport do
      shipped_theme_ids.each do |theme_id|
        visit_narrow "/legislators?sway_locale_id=#{sway_locale.id}"
        choose_theme!(theme_id)
        visit_narrow "/legislators?sway_locale_id=#{sway_locale.id}"
        expect(rendered_theme_id).to eq(theme_id)
        expect(page).to have_text(legislator.full_name, wait: 10)
        expect(page).to have_css("[id$='-trigger-history']")

        expect_controls_inside_parent!("the representatives list (#{theme_id})")
        expect_tab_strip_inside_viewport!("the representatives list (#{theme_id})")
        expect_no_horizontal_page_scroll!("the representatives list (#{theme_id}) with its three tabs")
      end
    end
  end

  it "keeps a representative's own page from scrolling sideways at 320px" do
    sign_in_as(@signed_in_user)

    with_narrow_viewport do
      visit_narrow "/legislators/#{legislator.id}"
      expect(page).to have_text(legislator.full_name, wait: 10)
      expect(page).to have_css("[id$='-trigger-history']")

      expect_tab_strip_inside_viewport!("a representative's page")
      expect_no_horizontal_page_scroll!("a representative's page with its three tabs")
    end
  end

  # @lat: [[tab-strips-at-narrow-viewports#What the four pages measure]]
  it "keeps the notifications page from scrolling sideways at 320px" do
    sign_in_as(@signed_in_user)

    with_narrow_viewport do
      visit_narrow "/notifications"
      expect(page).to have_css("[id$='-trigger-organizations']", wait: 10)

      expect_tab_strip_inside_viewport!("the notifications page")
      expect_no_horizontal_page_scroll!("the notifications page with its three tabs")
    end
  end

  it "keeps an organization membership from scrolling sideways at 320px" do
    sign_in_as(@signed_in_user)

    with_narrow_viewport do
      visit_narrow organization_membership_path(organization_id: organization.id, id: @membership.id)
      expect(page).to have_text(organization.name, wait: 10)
      expect(page).to have_css("[id$='-trigger-members']")

      expect_tab_strip_inside_viewport!("an organization membership")
      expect_no_horizontal_page_scroll!("an organization membership with its three tabs")
    end
  end
end
