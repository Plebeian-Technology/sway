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

  describe "bill_of_the_month_released items" do
    it "includes a Bill of the Month released this term in the user's locale, dated by its release day, with the user's vote" do
      user = create(:user)
      create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
      baltimore = user.sway_locales.first
      term_start = described_class.term_start_on(baltimore)
      release_date = [term_start, Time.zone.today - 1.day].max
      bill_with_vote = create(:bill, sway_locale: baltimore, scheduled_release_date_utc: release_date)
      user_vote = create(:user_vote, user: user, bill: bill_with_vote)
      bill_without_vote = create(:bill, sway_locale: baltimore, scheduled_release_date_utc: Time.zone.today)

      items = described_class.new(user: user).items.select { |item| item.kind == "bill_of_the_month_released" }

      voted_item = items.find { |item| item.bill == bill_with_vote }
      expect(voted_item).to be_present
      expect(voted_item.key).to eq("bill_of_the_month_released:#{bill_with_vote.id}")
      expect(voted_item.occurred_at).to eq(release_date.in_time_zone("UTC").beginning_of_day)
      expect(voted_item.sway_locale).to eq(baltimore)
      expect(voted_item.user_vote).to eq(user_vote)

      unvoted_item = items.find { |item| item.bill == bill_without_vote }
      expect(unvoted_item).to be_present
      expect(unvoted_item.user_vote).to be_nil
    end

    it "excludes a bill scheduled for a future date" do
      user = create(:user)
      create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
      baltimore = user.sway_locales.first
      future_bill = create(:bill, sway_locale: baltimore, scheduled_release_date_utc: Time.zone.today + 1.day)

      bills = described_class.new(user: user).items.filter_map(&:bill)

      expect(bills).not_to include(future_bill)
    end

    it "excludes a Bill of the Month released before the locale's current term" do
      user = create(:user)
      create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
      baltimore = user.sway_locales.first
      term_start = described_class.term_start_on(baltimore)
      old_bill = create(:bill, sway_locale: baltimore, scheduled_release_date_utc: term_start - 1.day)

      bills = described_class.new(user: user).items.filter_map(&:bill)

      expect(bills).not_to include(old_bill)
    end

    it "excludes a bill with no scheduled_release_date_utc" do
      user = create(:user)
      create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
      baltimore = user.sway_locales.first
      unscheduled_bill = create(:bill, sway_locale: baltimore, scheduled_release_date_utc: nil)

      bills = described_class.new(user: user).items.filter_map(&:bill)

      expect(bills).not_to include(unscheduled_bill)
    end

    it "excludes a Bill of the Month in a locale the user does not belong to" do
      user = create(:user)
      create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
      annapolis = create(:sway_locale, city: "Annapolis", state: "maryland", country: "united_states")
      expect(user.sway_locales).not_to include(annapolis)

      other_bill = create(:bill, sway_locale: annapolis, scheduled_release_date_utc: Time.zone.today)

      bills = described_class.new(user: user).items.filter_map(&:bill)

      expect(bills).not_to include(other_bill)
    end
  end

  describe "legislator_voted items" do
    it "includes a vote this term by the user's active legislator with the bill's vote date and the user's own vote" do
      user = create(:user)
      create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
      baltimore = user.sway_locales.first
      rep = create(:legislator, sway_locale: baltimore)
      create(:user_legislator, user: user, legislator: rep)

      vote_time = described_class.term_start_on(baltimore).in_time_zone("UTC").beginning_of_day + 2.days
      bill = create(:bill, sway_locale: baltimore, scheduled_release_date_utc: nil, house_vote_date_time_utc: vote_time)
      legislator_vote = create(:legislator_vote, bill: bill, legislator: rep)
      user_vote = create(:user_vote, user: user, bill: bill)

      items = described_class.new(user: user).items.select { |item| item.kind == "legislator_voted" }

      expect(items.size).to eq(1)
      item = items.first
      expect(item.key).to eq("legislator_voted:#{legislator_vote.id}")
      expect(item.occurred_at).to eq(vote_time)
      expect(item.legislator).to eq(rep)
      expect(item.bill).to eq(bill)
      expect(item.sway_locale).to eq(baltimore)
      expect(item.legislator_vote).to eq(legislator_vote)
      expect(item.user_vote).to eq(user_vote)
    end

    it "excludes votes by a non-user legislator or an inactive user_legislator" do
      user = create(:user)
      create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
      baltimore = user.sway_locales.first
      other_rep = create(:legislator, sway_locale: baltimore)
      inactive_rep = create(:legislator, sway_locale: baltimore)
      create(:user_legislator, user: user, legislator: inactive_rep, active: false)

      vote_time = described_class.term_start_on(baltimore).in_time_zone("UTC").beginning_of_day + 2.days
      bill = create(:bill, sway_locale: baltimore, scheduled_release_date_utc: nil, house_vote_date_time_utc: vote_time)
      create(:legislator_vote, bill: bill, legislator: other_rep)
      create(:legislator_vote, bill: bill, legislator: inactive_rep)

      items = described_class.new(user: user).items.select { |item| item.kind == "legislator_voted" }

      expect(items).to be_empty
    end

    it "excludes a vote dated before the locale's term start" do
      user = create(:user)
      create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
      baltimore = user.sway_locales.first
      rep = create(:legislator, sway_locale: baltimore)
      create(:user_legislator, user: user, legislator: rep)

      before_term = described_class.term_start_on(baltimore).in_time_zone("UTC").beginning_of_day - 1.day
      bill = create(:bill, sway_locale: baltimore, scheduled_release_date_utc: nil, house_vote_date_time_utc: before_term)
      create(:legislator_vote, bill: bill, legislator: rep)

      items = described_class.new(user: user).items.select { |item| item.kind == "legislator_voted" }

      expect(items).to be_empty
    end

    it "falls back to the legislator vote's created_at when the bill has no vote date" do
      user = create(:user)
      create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
      baltimore = user.sway_locales.first
      rep = create(:legislator, sway_locale: baltimore)
      create(:user_legislator, user: user, legislator: rep)

      vote_created_at = described_class.term_start_on(baltimore).in_time_zone("UTC").beginning_of_day + 3.days
      bill = create(:bill, sway_locale: baltimore, scheduled_release_date_utc: nil, house_vote_date_time_utc: nil, senate_vote_date_time_utc: nil)
      legislator_vote = create(:legislator_vote, bill: bill, legislator: rep, created_at: vote_created_at)

      items = described_class.new(user: user).items.select { |item| item.kind == "legislator_voted" }

      expect(items.size).to eq(1)
      expect(items.first.legislator_vote).to eq(legislator_vote)
      expect(items.first.occurred_at).to be_within(1.second).of(vote_created_at)
    end

    it "excludes inferred legislator votes" do
      user = create(:user)
      create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
      baltimore = user.sway_locales.first
      rep = create(:legislator, sway_locale: baltimore)
      create(:user_legislator, user: user, legislator: rep)

      vote_time = described_class.term_start_on(baltimore).in_time_zone("UTC").beginning_of_day + 2.days
      bill = create(:bill, sway_locale: baltimore, scheduled_release_date_utc: nil, house_vote_date_time_utc: vote_time)
      create(:legislator_vote, :inferred, bill: bill, legislator: rep)

      items = described_class.new(user: user).items.select { |item| item.kind == "legislator_voted" }

      expect(items).to be_empty
    end

    it "includes a vote on an archived bill from earlier this term" do
      user = create(:user)
      create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
      baltimore = user.sway_locales.first
      rep = create(:legislator, sway_locale: baltimore)
      create(:user_legislator, user: user, legislator: rep)

      vote_time = described_class.term_start_on(baltimore).in_time_zone("UTC").beginning_of_day + 2.days
      bill = create(:bill, sway_locale: baltimore, scheduled_release_date_utc: nil, house_vote_date_time_utc: vote_time, archived_at: 1.day.ago)
      legislator_vote = create(:legislator_vote, bill: bill, legislator: rep)

      items = described_class.new(user: user).items.select { |item| item.kind == "legislator_voted" }

      expect(items.size).to eq(1)
      expect(items.first.bill).to eq(bill)
      expect(items.first.legislator_vote).to eq(legislator_vote)
    end

    it "dates a senator's vote by senate_vote_date_time_utc when the House date is earlier" do
      user = create(:user)
      create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
      congress = user.sway_locales.find(&:congress?)
      district = create(:district, sway_locale: congress)
      senator = create(:legislator, sway_locale: congress)
      term = create(:legislator_term, legislator: senator, district: district, title: "Sen.")
      create(:user_legislator, user: user, legislator: senator)

      term_start = described_class.term_start_on(congress).in_time_zone("UTC").beginning_of_day
      house_time = term_start + 1.day
      senate_time = term_start + 5.days
      bill = create(:bill, sway_locale: congress, scheduled_release_date_utc: nil, house_vote_date_time_utc: house_time, senate_vote_date_time_utc: senate_time)
      create(:legislator_vote, bill: bill, legislator: senator, legislator_term: term)

      items = described_class.new(user: user).items.select { |item| item.kind == "legislator_voted" }

      expect(items.size).to eq(1)
      expect(items.first.occurred_at).to eq(senate_time)
    end
  end

  describe "organization_position_taken items" do
    it "includes an active position by a followed organization on a bill in the user's locale, dated by activated_at" do
      user = create(:user)
      create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
      baltimore = user.sway_locales.first
      org = create(:organization, sway_locale: baltimore)
      create(:organization_follow, user: user, organization: org)

      term_start = described_class.term_start_on(baltimore).in_time_zone("UTC").beginning_of_day
      activated_time = term_start + 5.days
      created_time = term_start - 10.days

      bill = create(:bill, sway_locale: baltimore, scheduled_release_date_utc: nil)
      user_vote = create(:user_vote, user: user, bill: bill)
      position = create(:organization_bill_position, organization: org, bill: bill, active: true, created_at: created_time)
      position.update_columns(activated_at: activated_time)

      items = described_class.new(user: user).items.select { |item| item.kind == "organization_position_taken" }

      expect(items.size).to eq(1)
      item = items.first
      expect(item.key).to eq("organization_position_taken:#{position.id}")
      expect(item.occurred_at).to be_within(1.second).of(activated_time)
      expect(item.organization_bill_position).to eq(position)
      expect(item.bill).to eq(bill)
      expect(item.sway_locale).to eq(baltimore)
      expect(item.user_vote).to eq(user_vote)
    end

    it "excludes an inactive position, a position by an unfollowed organization, and a position activated before term start" do
      user = create(:user)
      create(:user_address, user: user, address: create(:address, city: "Baltimore", region_code: "MD", country: "United States"))
      baltimore = user.sway_locales.first
      followed_org = create(:organization, sway_locale: baltimore)
      unfollowed_org = create(:organization, sway_locale: baltimore)
      create(:organization_follow, user: user, organization: followed_org)

      term_start = described_class.term_start_on(baltimore).in_time_zone("UTC").beginning_of_day
      in_term_time = term_start + 3.days

      inactive_bill = create(:bill, sway_locale: baltimore, scheduled_release_date_utc: nil)
      create(:organization_bill_position, organization: followed_org, bill: inactive_bill, active: false)

      unfollowed_bill = create(:bill, sway_locale: baltimore, scheduled_release_date_utc: nil)
      unfollowed_position = create(:organization_bill_position, organization: unfollowed_org, bill: unfollowed_bill, active: true)
      unfollowed_position.update_columns(activated_at: in_term_time)

      old_bill = create(:bill, sway_locale: baltimore, scheduled_release_date_utc: nil)
      old_position = create(:organization_bill_position, organization: followed_org, bill: old_bill, active: true)
      old_position.update_columns(activated_at: term_start - 1.day)

      items = described_class.new(user: user).items.select { |item| item.kind == "organization_position_taken" }

      expect(items).to be_empty
    end
  end
end
