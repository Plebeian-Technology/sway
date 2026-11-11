# frozen_string_literal: true

require "rails_helper"

# @lat: [[representative-reassignment-notifications#Observation seam and non-interference]]
RSpec.describe "Legislator reassignment (R7)", type: :system, js: true do
  let(:congress_json) { JSON.parse(File.read("spec/support/files/congress.json")) }

  before do
    allow_any_instance_of(Census::Congress).to receive(:request).and_return(
      double(body: congress_json.to_json)
    )
  end

  def register_user_with_address_for(legislator, district)
    user = create(:user)
    address = build_baltimore_address
    create(:user_address, user: user, address: address)
    create(:user_legislator, user: user, legislator: legislator, active: true)
    create(:user_district, user: user, district: district, active: true)
    user.complete!
    user
  end

  def build_baltimore_address
    create(
      :address,
      street: "1 East Baltimore St",
      city: "Baltimore",
      region_code: "MD",
      postal_code: "21202"
    )
  end

  # Gets the real congress SwayLocale by asking an address which locales it
  # falls under — what the neighbouring specs do — instead of copying
  # RegionUtil's name-normalizing rules by hand.
  def congress_sway_locale
    build_baltimore_address.sway_locales.find(&:congress?) || raise("congress locale not resolved")
  end

  it "auto-reassigns to a successor with no user action; the Legislators page reflects it" do
    sway_locale = congress_sway_locale
    district = create(:district, sway_locale: sway_locale, name: "MD7")
    seat = Seat.find_or_create_by_identity!(
      district:,
      office_identity: "test-congress-district-7",
      title: "Test representative",
      chamber: "House"
    )

    old_legislator =
      create(:legislator, district: district, sway_locale: sway_locale, first_name: "Departed", last_name: "Rep")
    # @lat: [[current-legislator-term#Which term a legislator is serving now]]
    create(:legislator_term, legislator: old_legislator, district: district,
      seat:, term_start_year: 2025, term_end_year: 2027)

    user = register_user_with_address_for(old_legislator, district)

    sign_in_as(user)
    visit "/legislators?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    expect(page).to have_text(old_legislator.full_name, wait: 10)

    # The seat changes hands: the sitting member's term finishes and a
    # successor's begins. The old term is kept rather than deleted, which is
    # what really happens to a former member's history.
    old_legislator.legislator_terms.update_all(term_start_year: 2023, term_end_year: 2025)

    # A successor is seeded for the SAME seat — the user does nothing.
    new_legislator =
      create(:legislator, district: district, sway_locale: sway_locale, first_name: "Successor", last_name: "Rep")
    create(:legislator_term, legislator: new_legislator, district: district,
      seat:, term_start_year: 2025, term_end_year: 2027)

    ReconcileUserDistrictsJob.new.perform(sway_locale.id)

    expect(UserLegislator.find_by(user: user, legislator: old_legislator).active).to be false
    expect(UserLegislator.find_by(user: user, legislator: new_legislator).active).to be true

    visit "/legislators?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    within(first("[role='tabpanel']")) do
      expect(page).to have_text(new_legislator.full_name, wait: 10)
      expect(page).to have_no_text(old_legislator.full_name, wait: 10)
    end
  end

  it "shows fewer representatives when the seat becomes vacant with no successor yet" do
    sway_locale = congress_sway_locale
    district = create(:district, sway_locale: sway_locale, name: "MD7")
    seat = Seat.find_or_create_by_identity!(
      district:,
      office_identity: "test-congress-district-7",
      title: "Test representative",
      chamber: "House"
    )

    old_legislator =
      create(:legislator, district: district, sway_locale: sway_locale, first_name: "Departed", last_name: "Rep")
    # Running, not finished — see the note in the example above.
    create(:legislator_term, legislator: old_legislator, district: district,
      seat:, term_start_year: 2025, term_end_year: 2027)

    user = register_user_with_address_for(old_legislator, district)

    other_locale = create(:sway_locale, :maryland)
    other_district = create(:district, sway_locale: other_locale, name: "Other Locale District")
    other_legislator = create(:legislator, district: other_district)
    create(:legislator_term, legislator: other_legislator, district: other_district)
    # @lat: [[identity-and-access#Registration is asynchronous by necessity]]
    other_assignment = create(:user_legislator, user: user, legislator: other_legislator, active: true)
    create(:user_district, user: user, district: other_district, active: true)

    sign_in_as(user)
    visit "/legislators?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    expect(page).to have_text(old_legislator.full_name, wait: 10)

    # @lat: [[representative-reassignment-notifications#Four reassignment transition scenarios]]
    old_legislator.legislator_terms.destroy_all

    ReconcileUserDistrictsJob.new.perform(sway_locale.id)

    expect(other_assignment.reload.active).to be(true)
    expect(UserLegislator.where(user: user, active: true).count).to eq(1)
    expect(user.reload.registered?).to be(true)
    # @lat: [[legislators-controller-design#Representative rows stay within the viewed locale]]
    expect(
      UserLegislator
        .joins(:legislator)
        .where(user: user, active: true, legislators: {sway_locale_id: sway_locale.id})
        .count
    ).to eq(0)

    visit "/legislators?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    # @lat: [[representative-reassignment-notifications#Browser examples confirm the destination page before checking absence]]
    expect(page).to have_css("[role='tabpanel']", wait: 10)

    within(first("[role='tabpanel']")) do
      expect(page).to have_no_text(old_legislator.full_name, wait: 10)
    end
  end

  it "notifies user of reassignment in-app and displays banner with dismissal" do
    sway_locale = congress_sway_locale
    district = create(:district, sway_locale: sway_locale, name: "MD7")
    seat = Seat.find_or_create_by_identity!(
      district:,
      office_identity: "test-congress-district-7",
      title: "Test representative",
      chamber: "House"
    )

    old_legislator =
      create(:legislator, district: district, sway_locale: sway_locale, first_name: "Departed", last_name: "Rep")
    create(:legislator_term, legislator: old_legislator, district: district,
      seat:, term_start_year: 2023, term_end_year: 2025)
    user = register_user_with_address_for(old_legislator, district)

    new_legislator =
      create(:legislator, district: district, sway_locale: sway_locale, first_name: "Successor", last_name: "Rep")
    create(:legislator_term, legislator: new_legislator, district: district,
      seat:, term_start_year: 2025, term_end_year: 2027)

    expect {
      ReconcileUserDistrictsJob.new.perform(sway_locale.id)
    }.to change { user.representative_reassignments.pending_in_app.count }.by(1)

    sign_in_as(user)
    visit "/legislators?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded
    expect(page).to have_css("[data-testid='reassignment-banner']", wait: 10)
    expect(page).to have_text("Successor Rep has succeeded Departed Rep as your representative for MD7.")

    find("[data-testid='reassignment-banner-dismiss']").click
    expect(page).to have_no_css("[data-testid='reassignment-banner']", wait: 10)
    # @lat: [[capybara-wait-semantics#Waiting on the side effect instead#An optimistic unmount is not a server answer]]
    wait_until { user.representative_reassignments.pending_in_app.none? }
    expect(user.representative_reassignments.pending_in_app.count).to eq(0)
  end

  it "displays all four reassignment banner presentation types with aria-live='polite' and optimistic DOM dismissal" do
    sway_locale = create(:sway_locale, :baltimore)
    district_a = create(:district, sway_locale: sway_locale, name: "District 7")
    district_b = create(:district, sway_locale: sway_locale, name: "District 8")
    rep_1 = create(:legislator, district: district_a, sway_locale: sway_locale, first_name: "Departed", last_name: "Rep")
    rep_dist_b = create(:legislator, district: district_b, sway_locale: sway_locale, first_name: "Arthur", last_name: "Dent")
    rep_succ = create(:legislator, district: district_a, sway_locale: sway_locale, first_name: "Ford", last_name: "Prefect")
    rep_vac_fill = create(:legislator, district: district_a, sway_locale: sway_locale, first_name: "Tricia", last_name: "McMillan")
    user = create(:user)

    create(:user_district, user: user, district: district_a, active: true)
    create(:user_legislator, user: user, legislator: rep_1, active: true)
    user.complete!

    r_dist = RepresentativeReassignment.create!(user: user, district: district_b, previous_district: district_a, legislator: rep_dist_b, previous_legislator: rep_1, reassignment_type: :district_changed)
    r_succ = RepresentativeReassignment.create!(user: user, district: district_a, previous_district: district_a, legislator: rep_succ, previous_legislator: rep_1, reassignment_type: :successor_seeded)
    r_vac = RepresentativeReassignment.create!(user: user, district: district_a, previous_district: district_a, legislator: nil, previous_legislator: rep_1, reassignment_type: :vacant_seat)
    r_fill = RepresentativeReassignment.create!(user: user, district: district_a, previous_district: district_a, legislator: rep_vac_fill, previous_legislator: nil, reassignment_type: :vacancy_filled)

    page.current_window.resize_to(390, 844)
    sign_in_as(user)
    visit "/legislators?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    banner = find("[data-testid='reassignment-banner']", wait: 10)
    expect(banner["aria-live"]).to eq("polite")
    expect(banner["aria-atomic"]).to eq("true")

    expect(page).to have_text("Your voting district has changed to District 8. Your new representative is Arthur Dent.")
    expect(page).to have_text("Ford Prefect has succeeded Departed Rep as your representative for District 7.")
    expect(page).to have_text("Departed Rep no longer represents District 7 and the seat is currently vacant.")
    expect(page).to have_text("Tricia McMillan has been seated as your new representative for District 7.")

    page.execute_script("window.__adversarial_session_token = 'active-client-session';")
    [r_dist, r_succ, r_vac, r_fill].each do
      first("[data-testid='reassignment-banner-dismiss']").click
    end
    wait_until { [r_dist, r_succ, r_vac, r_fill].all? { |rec| rec.reload.dismissed_at.present? } }

    expect(page).to have_no_css("[data-testid='reassignment-banner']", wait: 5)
    expect(page.evaluate_script("window.__adversarial_session_token")).to eq("active-client-session")
  end
end
