# typed: true
# frozen_string_literal: true

CONGRESS = {
  city: "congress",
  state: "congress",
  country: "united_states",
}.freeze

RSpec.describe CongressLegislatorVoteUpdateService do
  include_context "DevDataLoader"

  before do
    sql = dev_seed_sql
    reset_dev_seed_tables!
    load_dev_seed_sql!(sql)

    User.destroy_all

    if Legislator.count.zero?
      skip "Legislators must be pre-seeded to run this test."
    end

    sway_locale = SwayLocale.find_by(CONGRESS)

    if sway_locale.nil?
      skip "Congress Locale must be pre-seeded to run this test."
    end

    LegislatorVote.destroy_all
  end

  after(:all) do
    LegislatorVote.destroy_all
    Legislator.destroy_all
    SwayLocale.destroy_all
  end

  describe "#run" do
    context "a new CONGRESSIONAL Bill is created" do
      it "creates new LegislatorVotes for both the house and senate" do
        expect([496, 761]).to include(Legislator.count)
        expect(LegislatorVote.count).to eql(0)

        address = build(:address, region_code: "MD")

        sway_locale = SwayLocale.find_by(CONGRESS)
        expect(sway_locale).to_not be_nil

        district = build(:district, sway_locale:)

        senator =
          Legislator.find_by(external_id: "V000128").presence ||
            build(
              :legislator,
              address:,
              district:,
              title: "Sen.",
              external_id: "V000128",
              first_name: "Chris",
              last_name: "Van Hollen",
            )
        representative =
          Legislator.find_by(external_id: "M000687").presence ||
            build(
              :legislator,
              address:,
              district:,
              first_name: "Kweisi",
              last_name: "Mfume",
              external_id: "M000687",
              title: "Rep.",
            )

        bill = create(:bill, sway_locale: sway_locale, external_id: "s5")
        create(
          :vote,
          bill:,
          house_roll_call_vote_number: "23",
          senate_roll_call_vote_number: "7",
        )

        expect([496, 762]).to include(Legislator.count)
        expect(LegislatorVote.where(legislator: senator).first&.support).to eql(
          "FOR",
        )
        expect(
          LegislatorVote.where(legislator: representative).first&.support,
        ).to eql("AGAINST")
      end
    end
  end
end
