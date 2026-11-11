# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "legislator")
require Rails.root.join("db", "seeds", "models", "sway_locale")

RSpec.describe "Legislators Search again", type: :system, js: true do
  # @lat: [[registration-dead-ends#The dead ends in registration#An empty list says which kind of empty it is]]
  # @lat: [[identity-and-access#Identity and access#Registration is asynchronous by necessity]]
  it "finds a representative for the selected locale when the registered user has no local assignment" do
    baltimore = SeedSwayLocale.run.find do |locale|
      locale.name == "baltimore-maryland-united_states"
    end || raise("Baltimore locale is not configured")
    SeedLegislator.run([baltimore])

    address = DevelopmentAccountAddressService.resolve(sway_locale: baltimore)
    user = create(:user)
    create(:user_address, user: user, address: address)

    other_locale = create(:sway_locale, :maryland)
    other_district = create(:district, sway_locale: other_locale)
    other_legislator = create(:legislator, district: other_district)
    complete_registration_with_active_link(user, legislator: other_legislator)

    expect(user).to be_registered
    expect(
      user.user_legislators.where(active: true).joins(:legislator)
        .where(legislators: {sway_locale_id: baltimore.id}).exists?
    ).to be(false)

    mayor = baltimore.legislators.to_a.find do |legislator|
      legislator.active_term&.title == "Mayor"
    end || raise("Baltimore roster has no active Mayor")

    sign_in_as(user)
    visit "/legislators?sway_locale_id=#{baltimore.id}"
    wait_until_loaded
    app = find_by_id("app", visible: :visible)

    expect(app).to have_css(
      "[data-testid='legislators-count-line']",
      text: "No representatives found for Baltimore",
      visible: :visible,
      wait: 10
    )
    expect(app).to have_button("Search again", visible: :visible)
    expect(app).to have_no_css("a[href='/legislators/#{mayor.id}']", visible: :visible)

    click_button "Search again"

    mayor_card_link = app.find("a[href='/legislators/#{mayor.id}']", visible: :visible, wait: 15)
    mayor_card = mayor_card_link.ancestor("[data-slot='card']")
    expect(mayor_card).to have_text(mayor.full_name)
    expect(user.user_legislators.where(active: true, legislator: mayor).exists?).to be(true)
  end
end
