# frozen_string_literal: true

require "rails_helper"

RSpec.describe SwayLocaleUserCountsService do
  def register(city:, region_code: "MD", country: "United States")
    user = create(:user)
    address = create(:address, city: city, region_code: region_code, country: country)
    create(:user_address, user: user, address: address)
    address.sway_locales # materialize the city/state/congress rows
    address
  end

  # `|*, payload|` matches every other subscriber in spec/ — naming all five
  # parameters makes Steep check them against a narrower block type.
  def rows_instantiated_by
    rows = 0
    subscription = ActiveSupport::Notifications.subscribe("instantiation.active_record") do |*, payload|
      record_count = payload[:record_count].to_i #: Integer
      rows += record_count
    end
    yield
    ActiveSupport::Notifications.unsubscribe(subscription)
    rows
  end

  it "counts a user toward each of its city, state, and congress locales" do
    address = register(city: "Baltimore")
    city, state, congress = address.sway_locales

    counts = described_class.by_sway_locale_id

    expect(counts[city.id]).to eq(1)
    expect(counts[state.id]).to eq(1)
    expect(counts[congress.id]).to eq(1)
  end

  it "aggregates users sharing a state but not a city" do
    register(city: "Baltimore")
    register(city: "Annapolis")

    counts = described_class.by_sway_locale_id
    baltimore = SwayLocale.find_by!(city: "baltimore", state: "maryland")
    annapolis = SwayLocale.find_by!(city: "annapolis", state: "maryland")
    maryland = SwayLocale.find_by!(city: "maryland", state: "maryland")

    expect(counts[baltimore.id]).to eq(1)
    expect(counts[annapolis.id]).to eq(1)
    expect(counts[maryland.id]).to eq(2)
  end

  it "ignores users without an address" do
    create(:user)

    expect(described_class.by_sway_locale_id).to eq({})
  end

  it "does not count non-user (e.g. legislator) addresses" do
    create(:address, city: "Baltimore", region_code: "MD", country: "United States")
    create(:sway_locale, city: "Baltimore", state: "MD", country: "United States")

    expect(described_class.by_sway_locale_id).to eq({})
  end

  # @lat: [[locale-user-counts#Why the count is asked locale by locale]]
  # @lat: [[identity-and-access#A user holds one address]]
  it "counts a user once after their address is replaced by another in the same state" do
    user = create(:user)
    addresses = ["Baltimore", "Annapolis"].map do |city|
      address = create(:address, city: city, region_code: "MD", country: "United States")
      address.sway_locales
      address
    end
    link = create(:user_address, user: user, address: addresses.first)
    link.update!(address: addresses.last)

    counts = described_class.by_sway_locale_id
    maryland = SwayLocale.find_by!(city: "maryland", state: "maryland")
    congress = SwayLocale.find_by!(city: "congress", state: "congress")

    expect(counts[maryland.id]).to eq(1)
    expect(counts[congress.id]).to eq(1)
  end

  # @lat: [[locale-user-counts#Why only the distinct address components are read]]
  it "reads no more rows as more people register in the same place" do
    register(city: "Baltimore")
    small = rows_instantiated_by { described_class.by_sway_locale_id }
    expect(small).to be_positive, "measured no rows read, so this compares nothing"

    8.times { register(city: "Baltimore") }
    large = rows_instantiated_by { described_class.by_sway_locale_id }

    expect(large).to eq(small)
  end
end
