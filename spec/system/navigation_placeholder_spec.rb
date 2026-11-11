# frozen_string_literal: true

require "rails_helper"

# @lat: [[navigation-placeholder-tracer#Real-browser proof (Task 2, 69-06): why the drawer example forces a wide viewport]]
RSpec.describe "Navigation placeholder", type: :system, js: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) do
    create(:legislator, district: district).tap do |l|
      create(:legislator_term, legislator: l, district: district)
    end
  end
  let(:user) do
    create(:user).tap do |u|
      complete_registration_with_active_link(u)
    end
  end
  let(:bill) { create(:bill, sway_locale: sway_locale, legislator: legislator) }

  after do
    go_online!
  end

  context "navigating from a drawer link" do
    # @lat: [[navigation-placeholder-tracer#Real-browser proof (Task 2, 69-06): why the drawer example forces a wide viewport]]
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride",
        width: 1400, height: 900, deviceScaleFactor: 1, mobile: false
      )
      legislator
      sign_in_as(user)
      visit "/legislators?sway_locale_id=#{sway_locale.id}"
      wait_until_loaded
      expect(page).to have_text("Representatives", wait: 10)
      expect(page).to have_link("Browse Organizations", visible: :visible, wait: 10)

      # @lat: [[navigation-placeholder-tracer#Real-browser proof (Task 2, 69-06): why the throttle is applied after the setup navigation]]
      go_slow_link!
    end

    after do
      # @lat: [[navigation-placeholder-tracer#Real-browser proof (Task 2, 69-06): why the drawer example forces a wide viewport]]
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    rescue Selenium::WebDriver::Error::WebDriverError, NoMethodError
      nil
    end

    # @lat: [[navigation-placeholder-tracer#Real-browser proof (Task 2, 69-06): why the drawer click dispatches through JavaScript]]
    def click_drawer_link(text)
      link = first(:link, text, visible: :visible, wait: 10)
      page.execute_script(
        "arguments[0].scrollIntoView({block: 'center', behavior: 'instant'}); arguments[0].click();",
        link.native
      )
    end

    it "shows the destination's placeholder before the destination's content appears" do
      click_drawer_link("Browse Organizations")

      expect(page).to have_css("[data-testid='page-body-placeholder']", wait: 5)
      expect(page).to have_no_css("[data-testid='page-body-outgoing'] h1", text: "Organizations")
    end

    # @lat: [[system-shape#What a reader sees during the round trip#Why the outgoing page is not painted under the placeholder]]
    it "paints none of the outgoing page while the placeholder is on screen" do
      click_drawer_link("Browse Organizations")

      expect(page).to have_css("[data-testid='page-body-placeholder']", wait: 5)

      # The two share one grid cell, so anything the outgoing region still paints reads
      # through the skeleton. Opacity is the only thing that says so; Capybara's own
      # visibility test ignores it. It has to retry rather than read once, because the
      # fade to zero takes --dur-1.
      read_opacity = lambda do
        page.evaluate_script(<<~JS).to_f
          getComputedStyle(document.querySelector("[data-testid='page-body-outgoing']")).opacity
        JS
      end

      deadline = Time.current + 5
      opacity = read_opacity.call
      while opacity.positive? && Time.current < deadline
        sleep 0.1
        opacity = read_opacity.call
      end

      expect(opacity).to eq(0.0)
    end

    it "clears the placeholder once the destination has loaded" do
      click_drawer_link("Browse Organizations")

      expect(page).to have_css("h1", text: "Organizations", wait: 20)
      expect(page).to have_no_css("[data-testid='page-body-placeholder']")
      expect(page).to have_no_css("[data-testid='page-body-slot'][aria-busy='true']")
    end

    it "keeps the outgoing content region inert while the placeholder is on screen, and not once it clears" do
      click_drawer_link("Browse Organizations")

      # @lat: [[navigation-placeholder-tracer#Real-browser proof (Task 2, 69-06): why the inert assertion reads one compound selector, not two lookups]]
      expect(page).to have_css("[data-testid='page-body-outgoing'][inert]", wait: 5)

      expect(page).to have_css("h1", text: "Organizations", wait: 20)
      expect(page).to have_no_css("[data-testid='page-body-outgoing'][inert]")
    end

    it "keeps a drawer link visible and usable while the placeholder is on screen" do
      click_drawer_link("Browse Organizations")

      expect(page).to have_css("[data-testid='page-body-outgoing'][inert]", wait: 5)
      expect(page).to have_link("Representatives", href: "/legislators", visible: :visible)
    end

    # @lat: [[system-shape#What a reader sees during the round trip#Why focus moves to the slot's status region]]
    it "keeps focus inside the document when the activated link is inside the inert region" do
      expect(page).to have_link("Start voting", visible: :visible, wait: 10)
      page.execute_script(<<~JS)
        var link = Array.from(document.querySelectorAll("a")).find(function (el) {
          return el.textContent && el.textContent.trim().includes("Start voting");
        });
        link.scrollIntoView({block: "center", behavior: "instant"});
        link.focus();
        link.click();
      JS

      expect(page).to have_css("[data-testid='page-body-outgoing'][inert]", wait: 5)

      # React writes inert in the commit phase and moves focus in a passive effect flushed
      # afterwards, so this has to retry rather than read activeElement once. visible: :all
      # because the region is sr-only.
      expect(page).to have_css("[data-testid='page-body-slot'] output:focus", visible: :all, wait: 5)
    end

    # @lat: [[system-shape#What a reader sees during the round trip#Why focus moves to the slot's status region]]
    it "hands focus back to the page body once the destination has loaded" do
      expect(page).to have_link("Start voting", visible: :visible, wait: 10)
      page.execute_script(<<~JS)
        var link = Array.from(document.querySelectorAll("a")).find(function (el) {
          return el.textContent && el.textContent.trim().includes("Start voting");
        });
        link.scrollIntoView({block: "center", behavior: "instant"});
        link.focus();
        link.click();
      JS

      expect(page).to have_css("[data-testid='page-body-outgoing'][inert]", wait: 5)
      expect(page).to have_no_css("[data-testid='page-body-outgoing'][inert]", wait: 20)

      # The rescue must not leave the reader parked on the empty announcement region. The
      # attribute is removed in the commit phase and focus handed back in a passive effect
      # flushed afterwards, so this has to retry rather than read activeElement once.
      expect(page).to have_css("[data-testid='page-body-outgoing']:focus", visible: :all, wait: 20)
      expect(page).to have_no_css("[data-testid='page-body-slot'] output:focus", visible: :all)
    end
  end

  context "a page whose score sync polls" do
    # @lat: [[navigation-placeholder-tracer#Real-browser proof (Task 2, 69-06): why the poll example asserts a poll happened]]
    it "never draws a placeholder or dims the body across a full poll interval" do
      bill

      visit "/bills/#{bill.id}"
      expect(page).to have_text(bill.title, wait: 20)

      # Only a partial reload counts: a bare inertia:finish is also fired by a
      # deferred-prop resolution and by any ActionCable-triggered router.reload.
      page.execute_script(<<~JS)
        window.__swayPollCount = 0;
        document.addEventListener("inertia:finish", function (e) {
          var only = (e.detail && e.detail.visit && e.detail.visit.only) || [];
          if (only.length > 0) { window.__swayPollCount += 1; }
        });
      JS

      go_slow_link!

      # Both conditions have to hold before the loop may exit: a full poll interval
      # of watching, AND at least one poll completed inside it. Either alone passes
      # for the wrong reason.
      poll_interval_seconds = 15 # Bill.tsx's usePoll(15000).
      started = Time.zone.now
      deadline = started + 40
      placeholder_seen = false
      dim_seen = false
      polls_finished = 0

      while Time.zone.now < deadline && (polls_finished.zero? || Time.zone.now - started < poll_interval_seconds)
        placeholder_seen ||= page.has_css?("[data-testid='page-body-placeholder']", wait: 0)
        dim_seen ||= page.has_css?("[data-testid='page-body-slot'][aria-busy='true']", wait: 0)
        polls_finished = page.evaluate_script("window.__swayPollCount") || 0
        sleep 0.5
      end

      expect(Time.zone.now - started).to be >= poll_interval_seconds
      expect(polls_finished).to be_positive
      expect(placeholder_seen).to eq(false)
      expect(dim_seen).to eq(false)
    end
  end
end
