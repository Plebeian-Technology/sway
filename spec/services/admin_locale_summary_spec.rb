# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdminLocaleSummary do
  def register(city:, region_code: "MD", country: "United States")
    user = create(:user)
    address = create(:address, city: city, region_code: region_code, country: country)
    create(:user_address, user: user, address: address)
    address.sway_locales
    address
  end

  def find_tier(props, key)
    props[:tiers].find { |t| t[:key] == key }
  end

  it "returns tiers in city -> state -> congress order" do
    expect(described_class.new.as_props[:tiers].pluck(:key)).to eq(%w[city state congress])
  end

  it "buckets each locale by its geographic tier with a user count" do
    register(city: "Baltimore")
    props = described_class.new.as_props

    city_labels = find_tier(props, "city")[:locales].pluck(:label)
    state_labels = find_tier(props, "state")[:locales].pluck(:label)
    congress_locales = find_tier(props, "congress")[:locales]

    expect(city_labels).to include("Baltimore, Maryland, United States")
    expect(state_labels).to include("Maryland, United States")
    expect(congress_locales.first[:label]).to eq("U.S. Congress")
    expect(congress_locales.first[:user_count]).to eq(1)
  end

  it "sorts locales within a tier by descending user count" do
    register(city: "Baltimore")
    register(city: "Baltimore")
    register(city: "Annapolis")

    city_rows = find_tier(described_class.new.as_props, "city")[:locales]

    expect(city_rows.pluck(:user_count)).to eq(city_rows.pluck(:user_count).sort.reverse)
    expect(city_rows.first[:label]).to eq("Baltimore, Maryland, United States")
    expect(city_rows.first[:user_count]).to eq(2)
  end
end
