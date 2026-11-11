# frozen_string_literal: true

require "rails_helper"

# @lat: [[reader-control-browser-tests#Reader control browser tests]]
RSpec.describe "Theme picker control", type: :system, js: true do
  # @lat: [[reader-control-browser-tests#Reader control browser tests#Theme selection#The rendered theme picker changes and persists the theme]]
  it "changes the theme from the drawer and keeps it after navigation" do
    user = create(:user)
    sway_locale = create(:sway_locale, :congress)
    legislator = create(:legislator, district: create(:district, sway_locale: sway_locale))
    complete_registration_with_active_link(user, legislator: legislator)
    sign_in_as(user)

    with_narrow_viewport(width: 1400, height: 900) do
      visit_narrow "/bills?sway_locale_id=#{sway_locale.id}", width: 1400
      expect(page).to have_css("[aria-label='Theme']", wait: 20)

      initial_theme = rendered_theme_id
      theme_id, theme_label = if initial_theme == "ballot"
        ["cornerstore", "Corner Store"]
      else
        ["ballot", "Ballot"]
      end
      old_theme_cookie_value = page.driver.browser.manage.all_cookies
        .find { |cookie| cookie.fetch(:name) == "sway_theme_id" }
        &.fetch(:value)

      find("[aria-label='Theme']").click
      find("[role='option']", text: theme_label, exact: true, visible: :visible).click
      expect(page).to have_css("html[data-theme='#{theme_id}']", wait: 10)

      wait_until do
        theme_cookie_value = page.driver.browser.manage.all_cookies
          .find { |cookie| cookie.fetch(:name) == "sway_theme_id" }
          &.fetch(:value)
        theme_cookie_value.present? && theme_cookie_value != old_theme_cookie_value
      end

      visit_narrow "/legislators?sway_locale_id=#{sway_locale.id}", width: 1400
      expect(page).to have_css("h1", text: "Representatives", visible: :visible, wait: 20)
      expect(rendered_theme_id).to eq(theme_id)
    end
  end
end
