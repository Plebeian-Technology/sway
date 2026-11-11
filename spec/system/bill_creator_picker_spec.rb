# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Bill Creator picker interesting scoring", type: :system, js: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:sway_admin_user) { create(:user, :sway_admin) }

  before { create(:user_legislator, user: sway_admin_user, legislator: legislator) }

  # The picker's test id sits on the button that OPENS the dropdown. The rows
  # themselves render in a separate popup marked [role='listbox'].
  def expect_listbox_order(earlier_title, later_title)
    wait_until do
      text = find("[role='listbox']").text
      earlier = text.index(earlier_title)
      later = text.index(later_title)
      earlier && later && earlier < later
    end
  end

  # @lat: [[bill-creator-shell#The Bill Creator shell#Why the picker sort stays in the address]]
  it "reorders rows via Most Interesting and renders per-signal badges (R6/R7)" do
    # @lat: [[testing-the-toolchain#A fixture leaning on a shared counter writes its values out]]
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      external_id: "aaa-alpha-boring",
      title: "Alpha Boring Act",
      introduced_date_time_utc: 2.days.ago,
      scheduled_release_date_utc: 5.days.ago
    )
    interesting = create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      external_id: "zzz-zoning-interest",
      title: "Zoning Interest Act",
      introduced_date_time_utc: 4.days.ago,
      scheduled_release_date_utc: 3.days.ago,
      house_vote_date_time_utc: 5.days.ago
    )
    # The factory's score has org_split_score above zero, which earns the
    # "Split" badge. The recent house vote above lands inside the 30-day
    # window either side of today, which earns "Live".
    create(:bill_interesting_score, bill: interesting)
    pinned_run = create(
      :legislation_pipeline_run,
      bill: interesting,
      sway_locale: sway_locale,
      status: "succeeded",
      created_at: 2.hours.ago,
      completed_at: 1.hour.ago
    )

    sign_in_as(sway_admin_user)
    visit "/admin/bill_creator/new?event_key=bill&sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    # @lat: [[bill-interesting-score#Why picker sort controls grow on phones]]
    [320, 390].each do |width|
      with_narrow_viewport(width: width) do
        expect(page.evaluate_script("window.innerWidth")).to eq(width)
        %w[sort-newest sort-alpha sort-score sort-latest-action].each do |test_id|
          target = find("[data-testid='#{test_id}']")
          bounds = target.evaluate_script("({width: this.getBoundingClientRect().width, height: this.getBoundingClientRect().height})")
          expect(bounds.fetch("width")).to be >= 44
          expect(bounds.fetch("height")).to be >= 44
        end
        # @lat: [[bill-interesting-score#Why picker selection targets grow on phones]]
        locale_trigger = find("[data-testid='admin-locale-selector']")
        expect(locale_trigger.evaluate_script("this.getBoundingClientRect().height")).to be >= 44
        locale_trigger.click
        locale_options = all("[role='option']", minimum: 1)
        locale_options.each do |option|
          expect(option.evaluate_script("this.getBoundingClientRect().height")).to be >= 44
        end
        # @lat: [[bill-interesting-score#Why locale selection stays in the shell]]
        find("[role='option']", text: sway_locale.to_select_option[:label], exact_text: true).click
        expect(page).to have_no_css("[role='listbox']")

        find("[data-testid='bill-creator-picker']").click
        search = find_field("Search by bill number or title…")
        expect(search.evaluate_script("this.getBoundingClientRect().height")).to be >= 44
        search.set("Zoning")
        expect(find("[role='listbox']")).to have_text("Zoning Interest Act")
        expect(find("[role='listbox']")).to have_no_text("Alpha Boring Act")
        all("[role='option']", minimum: 2).each do |option|
          expect(option.evaluate_script("this.getBoundingClientRect().height")).to be >= 44
        end
        search.send_keys(:home, :enter)
        expect(page).to have_no_css("[role='listbox']")
        expect(find("[data-testid='bill-creator-picker']")).to have_text("New Bill")
        expect_no_horizontal_page_scroll!("picker controls at #{width}px")
      end
    end

    find("[data-testid='bill-creator-picker']", wait: 10).click

    expect(page).to have_css("[role='listbox']", text: "Alpha Boring Act", wait: 10)
    expect(page).to have_css("[role='listbox']", text: "Zoning Interest Act")

    # @lat: [[bill-creator-shell#Why the admin picker sorts by introduction date]]
    expect(page).to have_css("[data-testid='bill-picker-sort-toggle']")
    expect_listbox_order("Alpha Boring Act", "Zoning Interest Act")

    # The badges show up on the scored row. CSS prints them in capitals and
    # Selenium reads the capitalized text, hence the case-insensitive match.
    expect(page).to have_css("[role='listbox']", text: /split/i)
    expect(page).to have_css("[role='listbox']", text: /live/i)

    # Most Interesting puts the scored bill first and sinks bills that were
    # never scored. Close the popup before clicking the toggle, then reopen
    # it: the sort setting lives on the picker, not inside the popup.
    find("body").send_keys(:escape)
    find("[data-testid='sort-score']").send_keys(:enter)
    expect(page).to have_css("[data-testid='sort-score'][aria-pressed='true']")
    find("[data-testid='bill-creator-picker']").click
    expect_listbox_order("Zoning Interest Act", "Alpha Boring Act")

    # And back to A–Z.
    find("body").send_keys(:escape)
    find("[data-testid='sort-alpha']").click
    find("[data-testid='bill-creator-picker']").click
    expect_listbox_order("Alpha Boring Act", "Zoning Interest Act")

    find("body").send_keys(:escape)
    find("[data-testid='sort-score']").click
    expect(page).to have_current_path(/bill_creator_sort=score/, wait: 10)
    find("[data-testid='bill-creator-picker']").click
    expect_listbox_order("Zoning Interest Act", "Alpha Boring Act")
    find("[role='option']", text: /Zoning Interest Act/).click
    wait_until_loaded
    expect(page).to have_current_path(%r{/admin/bill_creator/#{interesting.id}/creator})
    expect(page).to have_current_path(/bill_creator_sort=score/)

    click_on "Pipeline & LLM"
    wait_until_loaded
    expect(page).to have_current_path(%r{/admin/bill_creator/#{interesting.id}/pipeline})
    expect(page).to have_current_path(/bill_creator_sort=score/)
    find("[data-testid='run-selector'] option[value='#{pinned_run.id}']").select_option
    wait_until_loaded
    expect(page).to have_current_path(/run_id=#{pinned_run.id}/)

    click_on "Summary"
    wait_until_loaded
    expect(page).to have_current_path(%r{/admin/bill_creator/#{interesting.id}/summary})
    expect(page).to have_current_path(/run_id=#{pinned_run.id}/)
    expect(page).to have_current_path(/bill_creator_sort=score/)

    click_on "Pipeline & LLM"
    wait_until_loaded
    expect(page).to have_current_path(%r{/admin/bill_creator/#{interesting.id}/pipeline})
    expect(page).to have_current_path(/run_id=#{pinned_run.id}/)
    expect(page).to have_current_path(/bill_creator_sort=score/)
    expect(find("[data-testid='run-selector']").value).to eq(pinned_run.id.to_s)
    expect(find("[data-testid='sort-score']")["aria-pressed"]).to eq("true")
    find("[data-testid='bill-creator-picker']").click
    expect_listbox_order("Zoning Interest Act", "Alpha Boring Act")
  end

  # @lat: [[bill-creator-shell#The Bill Creator shell#Why the picker sort stays in the address]]
  it "opens a pasted valid sort and defaults missing or unknown sort values to Newest" do
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      external_id: "aaa-picker-alpha",
      title: "Alpha Picker Act",
      introduced_date_time_utc: 1.day.ago
    )
    scored_bill = create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      external_id: "zzz-picker-score",
      title: "Score Picker Act",
      introduced_date_time_utc: 2.days.ago
    )
    create(:bill_interesting_score, bill: scored_bill)

    sign_in_as(sway_admin_user)
    visit "/admin/bill_creator/new?bill_creator_sort=score&sway_locale_id=#{sway_locale.id}"
    wait_until_loaded
    expect(find("[data-testid='sort-score']")["aria-pressed"]).to eq("true")
    find("[data-testid='bill-creator-picker']").click
    expect_listbox_order("Score Picker Act", "Alpha Picker Act")

    visit "/admin/bill_creator/new?bill_creator_sort=unknown&sway_locale_id=#{sway_locale.id}"
    wait_until_loaded
    expect(find("[data-testid='sort-newest']")["aria-pressed"]).to eq("true")
    find("[data-testid='bill-creator-picker']").click
    expect_listbox_order("Alpha Picker Act", "Score Picker Act")

    visit "/admin/bill_creator/new?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded
    expect(find("[data-testid='sort-newest']")["aria-pressed"]).to eq("true")
    find("[data-testid='bill-creator-picker']").click
    expect_listbox_order("Alpha Picker Act", "Score Picker Act")
    expect(scored_bill).to be_persisted
  end
end
