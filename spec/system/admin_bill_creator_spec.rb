# frozen_string_literal: true

require "rails_helper"
require "uri"
require "support/bill_schedule_browser_helpers"

RSpec.describe "Admin Bill Creator", type: :system, js: true, phase16: true do
  # @type self: AdminBillCreatorSpecContext
  include BillScheduleBrowserHelpers

  let(:admin_phone) { "4105550001" }
  let(:sway_locale) do
    SwayLocale.find_by(
      city: "baltimore",
      state: "MD",
      country: "United States"
    ) ||
      create(
        :sway_locale,
        city: "baltimore",
        state: "MD",
        country: "United States"
      )
  end

  let(:district) { create(:district, sway_locale: sway_locale) }

  let(:legislator) { create(:legislator, district: district) }

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
    @sway_admin_user = create(:user, phone: admin_phone)
    address =
      create(
        :address,
        city: "baltimore",
        region_code: "MD",
        country: "United States"
      )
    create(:user_address, user: @sway_admin_user, address: address)
    create(:user_legislator, user: @sway_admin_user, legislator: legislator)

    sign_in_as(@sway_admin_user)
    clear_browser_storage
  end

  it "shows the bill creator form at /admin/bill_creator/new" do
    visit "/admin/bill_creator/new?event_key=bill"
    wait_until_loaded

    expect(page).to have_button("Save Bill")
  end

  it "blocks submit when required dropdowns are empty (WR-01 regression guard)" do
    visit "/admin/bill_creator/new?event_key=bill"
    wait_until_loaded

    expect(page).to have_button("Save Bill")

    # Fill in only the title; leave the required dropdowns (status, chamber,
    # legislator) empty. The old `category` dropdown was removed from this form.
    fill_in "title", with: "Incomplete bill"

    save_button =
      first("button[type='submit']", text: "Save Bill")
    page.execute_script(<<~JS, save_button)
      var btn = arguments[0];
      var form = btn.closest("form");
      if (form && typeof form.requestSubmit === "function") {
        form.requestSubmit(btn);
      } else {
        btn.click();
      }
    JS

    # @lat: [[bill-creator-form-state#Browser saves exercise the controlled form and server response]]
    expect(page).to have_text("Please select the bill sponsor before saving.")
    expect(page).to have_current_path(%r{/admin/bill_creator/new})
    expect(Bill.where(title: "Incomplete bill")).not_to exist
  end

  it "updates an existing bill title" do
    existing =
      create(
        :bill,
        sway_locale: sway_locale,
        legislator: legislator,
        external_id: "EXISTING-01",
        title: "Original title",
        category: "education",
        status: "committee",
        chamber: "council",
        link: "https://example.com/EXISTING-01",
        summary: "Original summary text used by the regression spec."
      )

    visit "/admin/bill_creator/#{existing.id}/edit?event_key=bill"
    wait_until_loaded

    # @lat: [[bill-creator-form-state#Browser saves exercise the controlled form and server response]]
    title_input = find_field("title")
    title_input.click
    page.execute_script(<<~JS, title_input.native)
      var el = arguments[0];
      el.focus();
      el.setSelectionRange(0, el.value.length);
    JS
    title_input.send_keys(:backspace, "Updated title")

    save_button =
      first("button[type='submit']", text: "Save Bill")
    page.execute_script(<<~JS, save_button)
      var btn = arguments[0];
      var form = btn.closest("form");
      form.requestSubmit(btn);
    JS

    # @lat: [[capybara-wait-semantics#Waiting on the side effect instead]]
    expect(page).to have_current_path(%r{/creator\?event_key=legislator_votes}, wait: 10)
    expect(page).to have_text("Bill Updated")

    expect(existing.reload.title).to eq("Updated title")
  end

  # @lat: [[bill-creator-form-state#Browser saves exercise the controlled form and server response]]
  it "creates a bill through the Details form" do
    maryland_locale =
      SwayLocale.find_by(city: "maryland", state: "MD", country: "United States") ||
      create(:sway_locale, :maryland)
    sponsor_district = create(:district, sway_locale: maryland_locale)
    sponsor =
      create(
        :legislator,
        district: sponsor_district,
        first_name: "Browser",
        last_name: "Creator"
      )
    create(:legislator_term, legislator: sponsor, district: sponsor_district)

    title = "Browser-created Bill Creator example"
    external_id = "BROWSER-CREATE-01"
    visit "/admin/bill_creator/new?event_key=bill&sway_locale_id=#{maryland_locale.id}"
    expect(page).to have_button("Save Bill", wait: 10)

    {
      "external_id" => external_id,
      "title" => title,
      "link" => "https://example.com/#{external_id}",
      "summary" => "A complete bill created through the Bill Creator form."
    }.each do |field_name, value|
      input = find_field(field_name)
      input.click
      input.send_keys(value)
    end
    introduced_date = Date.current
    paste_into("#introduced_date_time_utc", introduced_date.iso8601)
    introduced_date_input = find_field("introduced_date_time_utc")
    expect(introduced_date_input.value).to eq(introduced_date.iso8601)
    expect(introduced_date_input.evaluate_script("this.checkValidity()")).to be(true)

    sponsor_label =
      "#{sponsor.last_name.titleize}, #{sponsor.first_name.titleize} " \
      "(#{sponsor_district.region_code} - #{sponsor_district.number})"
    find_by_id("legislator_id").click
    find("[role='option']", text: sponsor_label).click
    find_by_id("chamber").click
    find("[role='option']", text: "house").click
    find_by_id("status").click
    find("[role='option']", text: "Passed").click

    click_button "Save Bill"
    expect(page).to have_current_path(%r{/admin/bill_creator/\d+/creator\?event_key=legislator_votes}, wait: 20)
    expect(page).to have_text("Bill Created", wait: 20)

    created = Bill.find_by!(external_id: external_id, sway_locale: maryland_locale)
    expect(created.title).to eq(title)
    expect(created.link).to eq("https://example.com/#{external_id}")
    expect(created.summary).to eq("A complete bill created through the Bill Creator form.")
    expect(created.legislator).to eq(sponsor)
    expect(created.chamber).to eq("house")
    expect(created.status).to eq("passed")
    expect(created.introduced_date_time_utc.to_date).to eq(introduced_date)
  end

  # @lat: [[bill-creator-shell#How the frame adapts to phone browser viewports]]
  it "adapts the Bill Creator frame for phone browsers (390px and 320px) without horizontal scroll or clipped labels" do
    [390, 320].each do |width|
      with_narrow_viewport(width: width) do
        visit_narrow "/admin/bill_creator/new?event_key=bill&sway_locale_id=#{sway_locale.id}", width: width
        expect(page).to have_button("Save Bill")
        expect_no_horizontal_page_scroll!("Bill Creator frame at #{width}px")

        accordion_trigger = first("[data-slot='accordion-trigger']")
        expect(accordion_trigger.evaluate_script("this.getBoundingClientRect().height")).to be >= 44

        expect(clipped_elements("[data-slot='label']") || []).to be_empty
      end
    end
  end

  # @lat: [[bill-schedule-calendar-dates#How scheduling adapts to phone browser viewports]]
  it "adapts the Bill Creator scheduling tab for phone browsers (390px and 320px) with Agenda view and no horizontal scroll" do
    scheduled_bill =
      create(
        :bill,
        sway_locale: sway_locale,
        legislator: legislator,
        external_id: "SCHED-01",
        title: "Scheduled phone test bill",
        category: "education",
        status: "committee",
        chamber: "council",
        link: "https://example.com/SCHED-01",
        summary: "Summary for schedule mobile test.",
        scheduled_release_date_utc: 3.days.from_now.to_date
      )

    [390, 320].each do |width|
      with_narrow_viewport(width: width) do
        visit_narrow "/admin/bill_creator/#{scheduled_bill.id}/schedule", width: width
        expect(page).to have_text("Selected bill", wait: 10)
        expect_no_horizontal_page_scroll!("Bill Creator schedule tab Month view at #{width}px")

        find("[data-testid='view-mode-agenda']").click
        expect(page).to have_css("[data-testid='agenda-view-list']", wait: 5)
        expect_no_horizontal_page_scroll!("Bill Creator schedule tab Agenda view at #{width}px")
      end
    end
  end

  describe "phone browser scheduling, legislator vote touch targets, and pipeline runs" do
    let!(:unscheduled_bill) do
      create(
        :bill,
        sway_locale: sway_locale,
        legislator: legislator,
        external_id: "SCHED-ADV-01",
        title: "Adversarial Scheduling Test Bill",
        category: "education",
        status: "committee",
        chamber: "council",
        link: "https://example.com/SCHED-ADV-01",
        summary: "Summary for schedule adversarial testing.",
        scheduled_release_date_utc: nil
      )
    end

    # @lat: [[query-parameter-navigation-carry#Query parameter navigation carry#Centralized interception mechanism#Server redirect carry follows real form writes]]
    # @lat: [[bill-schedule-calendar-dates#Scheduler navigation, today control, and pagination]]
    # @lat: [[capybara-wait-semantics#Waiting on the side effect instead]]
    it "verifies Month vs Agenda view toggle, scheduling, unscheduling, and sidebar reachability at 390px and 320px" do
      create(:legislator_term, legislator: legislator, district: district)
      [390, 320].each do |width|
        with_narrow_viewport(width: width) do
          visit_narrow "/admin/bill_creator/#{unscheduled_bill.id}/schedule", width: width
          expect(page).to have_text("Selected bill", wait: 10)
          expect_no_horizontal_page_scroll!("Schedule tab Month view at #{width}px")

          find("[data-testid='view-mode-agenda']").click
          expect(page).to have_css("[data-testid='agenda-view-list']", wait: 5)
          expect_no_horizontal_page_scroll!("Schedule tab Agenda view at #{width}px")

          target_agenda_btn = first("[data-testid^='btn-select-agenda-date-']:not([disabled])", text: "Select date", minimum: 1)
          expect(target_agenda_btn.evaluate_script("this.getBoundingClientRect().height")).to be >= 44
          target_date_str = select_first_available_agenda_date(page)

          find("[data-testid='view-mode-month']").click
          expect(page).to have_no_css("[data-testid='agenda-view-list']")

          schedule_btn = find("[data-testid='btn-schedule-bill']")
          expect(schedule_btn).not_to be_disabled
          expect(schedule_btn.evaluate_script("this.getBoundingClientRect().height")).to be >= 44

          schedule_btn.click
          expect(page).to have_text("Added bill - #{unscheduled_bill.title} - to schedule.", wait: 10)
          expect(unscheduled_bill.reload.scheduled_release_date_utc.to_s).to eq(target_date_str)
          expect(page).to have_button("Remove from schedule", wait: 10)

          remove_btn = find("[data-testid='btn-remove-bill-schedule']")
          expect(remove_btn.evaluate_script("this.getBoundingClientRect().height")).to be >= 44
          remove_btn.click

          expect(page).to have_button("Schedule bill", disabled: false, wait: 10)
          schedule_uri = URI.parse(page.current_url)
          expect(schedule_uri.path).to eq("/admin/bill_creator/#{unscheduled_bill.id}/schedule")
          expect(URI.decode_www_form(schedule_uri.query.to_s).to_h).to include("date" => target_date_str)
          expect(page).to have_text("Bill - #{unscheduled_bill.title} - removed from schedule.", wait: 10)
          expect(unscheduled_bill.reload.scheduled_release_date_utc).to be_nil

          page.execute_script("window.scrollTo(0, document.body.scrollHeight)")
          expect(page).to have_text("Upcoming scheduled")
          expect(page).to have_text("Unscheduled")
          expect_no_horizontal_page_scroll!("Schedule tab after scrolling to sidebar at #{width}px")
        end
      end
    end

    it "verifies legislator vote radio touch targets (>= 44px) and pipeline runs index on phone viewports" do
      create(:legislator_term, legislator: legislator, district: district)
      [390, 320].each do |width|
        with_narrow_viewport(width: width) do
          visit_narrow "/admin/bill_creator/#{unscheduled_bill.id}/creator?event_key=legislator_votes", width: width
          expect(page).to have_text("Save Legislator Votes", wait: 10)
          expect_no_horizontal_page_scroll!("Legislator votes at #{width}px")

          first_radio_label = first("label[for^='legislator-vote-']")
          expect(first_radio_label.evaluate_script("this.getBoundingClientRect().height")).to be >= 44
          expect(first_radio_label.evaluate_script("this.getBoundingClientRect().width")).to be >= 44
          first_radio_label.click

          save_btn = find_button("Save Legislator Votes")
          expect(save_btn.evaluate_script("this.getBoundingClientRect().height")).to be >= 44

          visit_narrow "/pipeline_runs", width: width
          expect(page).to have_text("Pipeline Run History", wait: 10)
          expect_no_horizontal_page_scroll!("Pipeline runs index at #{width}px")
        end
      end
    end
  end
end
