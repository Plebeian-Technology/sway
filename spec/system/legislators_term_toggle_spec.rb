# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislators-tab-switching-design#The Current | Lifetime toggle and why an open accordion used to close on flip]]
RSpec.describe "Legislators term toggle", type: :system, js: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }

  # Reads the number shown directly under a given label. A score tile is a div
  # holding the label, followed by a sibling div holding the value (see
  # app/frontend/components/legislators/ScoreTile.tsx).
  def score_tile_value(label)
    find(:xpath, "//div[normalize-space(text())='#{label}']/following-sibling::div[1]").text
  end

  it "defaults to current-term tallies and Lifetime reveals the sum across every term" do
    current_term = create(:legislator_term, legislator: legislator, district: district)
    prior_term = create(:legislator_term, :prior_term, legislator: legislator, district: district)

    user = create(:user)
    user_legislator = create(:user_legislator, user: user, legislator: legislator, active: true)
    user.complete!

    create(:user_legislator_term_score, user_legislator: user_legislator, legislator_term: current_term,
      count_agreed: 3, count_disagreed: 1, count_no_legislator_vote: 0, count_legislator_abstained: 0)
    create(:user_legislator_term_score, user_legislator: user_legislator, legislator_term: prior_term,
      count_agreed: 2, count_disagreed: 0, count_no_legislator_vote: 1, count_legislator_abstained: 0)

    sign_in_as(user)
    visit "/legislators?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    expect(page).to have_text(legislator.full_name, wait: 10)
    expect(page).to have_text("Current term")
    # Under the toggle sits the current term's year range and nothing else:
    # two years joined by an en dash, no extra words. The factory's default
    # term runs 2025–2027, and LegislatorResource sends term_start_year and
    # term_end_year.
    expect(page).to have_text("2025–2027")

    # The default tab counts the current term only: 3 agreed, 1 disagreed.
    expect(score_tile_value("Agreed")).to eq("3")
    expect(score_tile_value("Disagreed")).to eq("1")

    find("[id$='-trigger-lifetime']").click

    # Lifetime adds the current term (3 agreed / 1 disagreed / 0 no-vote) to
    # the earlier term (2 / 0 / 1).
    expect(score_tile_value("Agreed")).to eq("5")
    expect(score_tile_value("Disagreed")).to eq("1")
    expect(score_tile_value("No vote")).to eq("1")

    # Switching back to Current term shows the un-added numbers again. The
    # toggle only changes what is displayed; it does not throw anything away
    # and it goes both ways.
    find("[id$='-trigger-current']").click
    expect(score_tile_value("Agreed")).to eq("3")
  end

  # @lat: [[legislators-tab-switching-design#The Current | Lifetime toggle and why an open accordion used to close on flip]]
  it "keeps an expanded card's charts accordion open across the Current<->Lifetime flip" do
    create(:legislator_term, legislator: legislator, district: district)

    user = create(:user)
    user_legislator = create(:user_legislator, user: user, legislator: legislator, active: true)
    user.complete!
    create(:user_legislator_term_score, user_legislator: user_legislator,
      legislator_term: legislator.legislator_terms.first,
      count_agreed: 3, count_disagreed: 1, count_no_legislator_vote: 0, count_legislator_abstained: 0)

    sign_in_as(user)
    visit "/legislators?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded
    expect(page).to have_text(legislator.full_name, wait: 10)
    expect(page).to have_button("Show voter agreement", wait: 10)

    charts_id = "legislator-charts-#{legislator.external_id}"

    # Open the accordion on the default (Current term) tab.
    click_button("Show voter agreement")
    expect(page).to have_css("##{charts_id}", wait: 5)

    # @lat: [[legislators-tab-switching-design#The Current | Lifetime toggle and why an open accordion used to close on flip]]
    find("[id$='-trigger-lifetime']").click
    expect(page).to have_css("[id$='-trigger-lifetime'][data-state='active']", wait: 5)
    expect(page).to have_css("##{charts_id}")
    expect(page).to have_button("Hide voter agreement")

    # And back to Current term — still open.
    find("[id$='-trigger-current']").click
    expect(page).to have_css("[id$='-trigger-current'][data-state='active']", wait: 5)
    expect(page).to have_css("##{charts_id}")
  end
end
