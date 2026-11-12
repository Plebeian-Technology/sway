# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeedQuery do
  it "returns representatives_found, user_joined, and three legislative_term_began items newest first for a Baltimore user" do
    user = create(:user)
    create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
    baltimore, maryland, congress = user.sway_locales
    rep1 = create(:legislator, sway_locale: baltimore)
    rep2 = create(:legislator, sway_locale: maryland)
    create(:user_legislator, user: user, legislator: rep1, created_at: 2.hours.ago)
    create(:user_legislator, user: user, legislator: rep2, created_at: 1.hour.ago)

    query = described_class.new(user: user)
    items = query.items

    expect(items.map(&:kind)).to contain_exactly(
      "representatives_found",
      "user_joined",
      "legislative_term_began",
      "legislative_term_began",
      "legislative_term_began"
    )
    expect(items.each_cons(2).all? { |a, b| ([a.occurred_at, a.key] <=> [b.occurred_at, b.key]) == 1 }).to be(true)

    joined_item = items.find { |item| item.kind == "user_joined" }
    expect(joined_item.key).to eq("user_joined:#{user.id}")
    expect(joined_item.occurred_at).to be_within(1.second).of(user.created_at)

    reps_item = items.find { |item| item.kind == "representatives_found" }
    expect(reps_item.key).to eq("representatives_found:#{user.id}")
    expect(reps_item.legislators).to contain_exactly(rep1, rep2)
    expect(reps_item.occurred_at).to be_within(1.second).of(user.user_legislators.minimum(:created_at))

    [baltimore, maryland, congress].each do |locale|
      term_item = items.find { |item| item.kind == "legislative_term_began" && item.sway_locale == locale }
      expected_date = TermWindow.convening_date(locale, TermWindow.cycle_start_year(locale, Date.current))
      expect(term_item.key).to eq("legislative_term_began:#{locale.id}")
      expect(term_item.occurred_at).to eq(expected_date.in_time_zone("UTC").beginning_of_day)
      expect(described_class.term_start_on(locale)).to eq(expected_date)
    end
  end

  it "produces no legislative_term_began item for an undeclared locale" do
    user = create(:user)
    create(:user_address, user: user, address: create(:address, city: "Frederick", region_code: "MD", country: "United States"))
    undeclared_locale = user.sway_locales.find { |locale| !locale.declared? }
    expect(undeclared_locale).to be_present

    term_items = described_class.new(user: user).items.select { |item| item.kind == "legislative_term_began" }

    expect(term_items.map(&:sway_locale)).not_to include(undeclared_locale)
    expect(term_items.size).to eq(2)
  end

  it "pages with per_page 2 without duplicates or gaps and returns nil next_cursor on the last page" do
    user = create(:user)
    create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
    rep = create(:legislator, sway_locale: user.sway_locales.first)
    create(:user_legislator, user: user, legislator: rep)

    all_items = described_class.new(user: user, per_page: 20).items
    expect(all_items.size).to eq(5)

    page1 = described_class.new(user: user, per_page: 2)
    expect(page1.items.size).to eq(2)
    expect(page1.next_cursor).to be_a(String)

    page2 = described_class.new(user: user, cursor: page1.next_cursor, per_page: 2)
    expect(page2.items.size).to eq(2)
    expect(page2.next_cursor).to be_a(String)

    page3 = described_class.new(user: user, cursor: page2.next_cursor, per_page: 2)
    expect(page3.items.size).to eq(1)
    expect(page3.next_cursor).to be_nil

    paged_keys = (page1.items + page2.items + page3.items).map(&:key)
    expect(paged_keys).to eq(all_items.map(&:key))
  end

  it "omits representatives_found when the user has no active user_legislators" do
    user = create(:user)
    create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
    inactive_rep = create(:legislator, sway_locale: user.sway_locales.first)
    create(:user_legislator, user: user, legislator: inactive_rep, active: false)

    items = described_class.new(user: user).items

    expect(items.map(&:kind)).not_to include("representatives_found")
    expect(items.map(&:kind)).to include("user_joined", "legislative_term_began")
  end
end
