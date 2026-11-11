# frozen_string_literal: true

require "rails_helper"

# Reassigns a user's legislators by comparing old and new, doing nothing
# rather than something wrong when resolution fails. Resolves through the
# congress locale (Census-backed, easy to fake).
RSpec.describe ReconcileUserDistrictsService do
  def create_supported_term(legislator:, district:, seat: nil, office_identity: "test-representative-office", **term_attributes)
    seat ||= Seat.find_or_create_by_identity!(
      district:,
      office_identity:,
      title: "Test representative",
      chamber: "House"
    )
    create(:legislator_term, legislator:, district:, seat:, **term_attributes)
  end

  let(:congress_json) { JSON.parse(File.read("spec/support/files/congress.json")) }

  before do
    allow_any_instance_of(Census::Congress).to receive(:request).and_return(
      double(body: congress_json.to_json)
    )
  end

  def build_user_with_congress_locale
    user = create(:user)
    address =
      create(
        :address,
        street: "1 East Baltimore St",
        city: "Baltimore",
        region_code: "MD",
        postal_code: "21202"
      )
    create(:user_address, user:, address:)
    sway_locale = address.sway_locales.find(&:congress?)
    [user, sway_locale]
  end

  describe "#call" do
    context "when the resolved legislator/district set is unchanged" do
      it "makes no writes and does not broadcast" do
        user, sway_locale = build_user_with_congress_locale
        district = create(:district, sway_locale:, name: "MD7")
        legislator = create(:legislator, district:)
        create_supported_term(legislator:, district:)

        # Prime stored state exactly as registration would.
        SwayRegistrationService
          .new(user, user.address, sway_locale, invited_by_id: nil, async: false)
          .create_user_legislators

        expect {
          ReconcileUserDistrictsService.new(user, sway_locale).call
        }.to change(UserLegislator, :count).by(0).and change(UserDistrict, :count).by(0)

        expect(UserLegislator.find_by(user:, legislator:).active).to be true
        expect(UserDistrict.find_by(user:, district:).active).to be true
      end

      it "does not broadcast when nothing changed" do
        user, sway_locale = build_user_with_congress_locale
        district = create(:district, sway_locale:, name: "MD7")
        legislator = create(:legislator, district:)
        create_supported_term(legislator:, district:)
        SwayRegistrationService
          .new(user, user.address, sway_locale, invited_by_id: nil, async: false)
          .create_user_legislators

        expect {
          ReconcileUserDistrictsService.new(user, sway_locale).call
        }.not_to have_broadcasted_to("scores_#{user.id}")
      end

      # @lat: [[representative-resolution-tests#Reconciliation keeps co-serving seats#Keeps each active co-serving occupant]]
      it "keeps both active links for supported co-serving seats in one district" do
        user, sway_locale = build_user_with_congress_locale
        district = create(:district, sway_locale:, name: "MD7")
        first_seat = Seat.find_or_create_by_identity!(
          district:, office_identity: "md-house-7a", title: "Delegate", chamber: "House"
        )
        second_seat = Seat.find_or_create_by_identity!(
          district:, office_identity: "md-house-7b", title: "Delegate", chamber: "House"
        )
        first = create(:legislator, district:)
        second = create(:legislator, district:)
        create_supported_term(
          legislator: first, district:, seat: first_seat,
          term_start_year: 2021, term_end_year: 2027
        )
        create_supported_term(
          legislator: second, district:, seat: second_seat,
          term_start_year: 2023, term_end_year: 2029
        )
        first_link = create(:user_legislator, user:, legislator: first, active: true)
        second_link = create(:user_legislator, user:, legislator: second, active: true)
        create(:user_district, user:, district:, active: true)
        allow(SwayGeocode).to receive(:build).and_return(double(districts: [7]))

        expect {
          ReconcileUserDistrictsService.new(user, sway_locale).call
        }.to change(UserLegislator, :count).by(0)

        expect(first_link.reload.active).to be(true)
        expect(second_link.reload.active).to be(true)
      end

      # @lat: [[representative-resolution-tests#Reconciliation keeps co-serving seats#Reactivates locale-wide link idempotently]]
      it "reactivates the locale-wide occupant link and keeps it active on the next run" do
        user, sway_locale = build_user_with_congress_locale
        us_district = create(:district, sway_locale:, name: "US0")
        president = create(:legislator, district: us_district)
        create_supported_term(
          legislator: president,
          district: us_district,
          office_identity: "us-president"
        )
        president_link = create(:user_legislator, user:, legislator: president, active: false)
        locale_link = create(:user_district, user:, district: us_district, active: false)
        allow(SwayGeocode).to receive(:build).and_return(double(districts: [7]))

        expect {
          ReconcileUserDistrictsService.new(user, sway_locale).call
        }.to change { president_link.reload.active }.from(false).to(true)
          .and change { locale_link.reload.active }.from(false).to(true)

        expect {
          ReconcileUserDistrictsService.new(user, sway_locale).call
        }.not_to change { [president_link.reload.active, locale_link.reload.active] }
      end
    end

    context "when the user's district changed (moved)" do
      it "deactivates the old link + user_district and creates new ones for the current district only" do
        user, sway_locale = build_user_with_congress_locale

        old_district = create(:district, sway_locale:, name: "MD3")
        old_legislator = create(:legislator, district: old_district)
        old_term = create_supported_term(legislator: old_legislator, district: old_district, office_identity: "old-district-office")
        old_ul = create(:user_legislator, user:, legislator: old_legislator)
        old_ud = create(:user_district, user:, district: old_district)
        old_score = create(:user_legislator_term_score, user_legislator: old_ul, legislator_term: old_term)

        new_district = create(:district, sway_locale:, name: "MD7")
        new_legislator = create(:legislator, district: new_district)
        new_term = create_supported_term(legislator: new_legislator, district: new_district, office_identity: "new-district-office")
        bill = create(:bill, sway_locale:, legislator: new_legislator)
        create(:user_vote, user:, bill:, support: LegislatorVote::Support::FOR)
        create(:legislator_vote, bill:, legislator: new_legislator, legislator_term: new_term, support: LegislatorVote::Support::FOR)

        expect {
          ReconcileUserDistrictsService.new(user, sway_locale).call
        }.to have_broadcasted_to("scores_#{user.id}")

        expect(old_ul.reload.active).to be false
        expect(old_ud.reload.active).to be false
        # Rows and scores are kept, never deleted.
        expect(UserLegislator.exists?(old_ul.id)).to be true
        expect(UserLegislatorTermScore.exists?(old_score.id)).to be true

        new_ul = UserLegislator.find_by(user:, legislator: new_legislator)
        new_ud = UserDistrict.find_by(user:, district: new_district)
        expect(new_ul.active).to be true
        expect(new_ud.active).to be true

        expect(UserLegislatorTermScore.find_by(user_legislator: new_ul, legislator_term: new_term)&.count_agreed).to eq(1)
        expect(LegislatorDistrictScore.find_by(legislator_term: new_term)&.count_agreed).to eq(1)
        expect(BillScore.find_by(bill:)&.for).to eq(1)
      end
    end

    context "when the district is unchanged but the occupant changed (successor seeded, same seat — R7)" do
      it "deactivates the old link and links to the successor without touching user_districts" do
        user, sway_locale = build_user_with_congress_locale
        district = create(:district, sway_locale:, name: "MD7")
        seat = Seat.find_or_create_by_identity!(
          district:,
          office_identity: "md-congressional-district-7",
          title: "Representative",
          chamber: "House"
        )

        old_legislator = create(:legislator, district:)
        create_supported_term(legislator: old_legislator, district:, seat:, term_start_year: 2023, term_end_year: 2025)
        old_ul = create(:user_legislator, user:, legislator: old_legislator)
        old_ud = create(:user_district, user:, district:)

        # A replacement legislator is seeded for the SAME district with a LATER
        # term_start_year, which is what makes them take over — old_legislator's
        # own single term still passes Legislator.serving?.
        new_legislator = create(:legislator, district:)
        create_supported_term(legislator: new_legislator, district:, seat:, term_start_year: 2025, term_end_year: 2027)

        expect {
          ReconcileUserDistrictsService.new(user, sway_locale).call
        }.to change(UserLegislator, :count).by(1).and change(UserDistrict, :count).by(0)

        expect(old_ul.reload.active).to be false
        expect(old_ud.reload.active).to be true

        new_ul = UserLegislator.find_by(user:, legislator: new_legislator)
        expect(new_ul.active).to be true
      end
    end

    context "when the resolved district's seat is vacant" do
      it "deactivates the old link with nothing new created" do
        user, sway_locale = build_user_with_congress_locale

        district = create(:district, sway_locale:, name: "MD7")
        # Nobody has a legislator_term in this district this time round, so the
        # seat is empty: the previous holder left and no replacement is seeded
        # yet.
        old_legislator = create(:legislator, district:)
        old_ul = create(:user_legislator, user:, legislator: old_legislator)
        old_ud = create(:user_district, user:, district:)

        expect {
          ReconcileUserDistrictsService.new(user, sway_locale).call
        }.to change(UserLegislator, :count).by(0).and change(UserDistrict, :count).by(0)

        expect(old_ul.reload.active).to be false
        expect(old_ud.reload.active).to be false
        expect(UserLegislator.where(user:, active: true).count).to eq(0)
        expect(UserDistrict.active.where(user:).count).to eq(0)
      end
    end

    context "when resolution raises" do
      it "propagates the error and makes zero writes" do
        allow_any_instance_of(Census::Congress).to receive(:request).and_raise(
          Faraday::ConnectionFailed,
          "Failed to open TCP connection to tigerweb.geo.census.gov:443"
        )

        user, sway_locale = build_user_with_congress_locale
        district = create(:district, sway_locale:, name: "MD7")
        legislator = create(:legislator, district:)
        create(:legislator_term, legislator:, district:)
        stored_ul = create(:user_legislator, user:, legislator:)
        stored_ud = create(:user_district, user:, district:)

        expect {
          expect {
            ReconcileUserDistrictsService.new(user, sway_locale).call
          }.to raise_error(SwayGeocode::ServiceUnavailableError)
        }.to change(UserLegislator, :count).by(0).and change(UserDistrict, :count).by(0)

        expect(stored_ul.reload.active).to be true
        expect(stored_ud.reload.active).to be true
      end
    end

    context "when a locale-wide district contains an unseated term" do
      # @lat: [[representative-resolution-tests#Reconciliation refusal#Refuses unseated locale-wide term]]
      it "raises Seats::UnresolvedSeatError identifying the unseated term" do
        user, sway_locale = build_user_with_congress_locale
        us0 = create(:district, sway_locale:, name: "US0")
        president = create(:legislator, sway_locale:)
        unseated_term = create(:legislator_term, legislator: president, district: us0)

        district = create(:district, sway_locale:, name: "MD7")
        legislator = create(:legislator, district:)
        create_supported_term(legislator:, district:)

        expect {
          ReconcileUserDistrictsService.new(user, sway_locale).call
        }.to raise_error(
          Seats::UnresolvedSeatError,
          "Locale-wide term #{unseated_term.id} in #{sway_locale.name} has no persisted seat identity"
        )
      end
    end

    context "when the user has no address" do
      it "returns without writing or raising" do
        user = create(:user)
        sway_locale = create(:sway_locale)

        expect { ReconcileUserDistrictsService.new(user, sway_locale).call }
          .not_to raise_error
        expect(UserLegislator.where(user:).count).to eq(0)
      end
    end
  end
end
