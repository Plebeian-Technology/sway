# typed: false
# frozen_string_literal: true

require_relative "../../db/seeds/models/legislator"

CONGRESS = {
  city: "congress",
  state: "congress",
  country: "united_states"
}

skip_running_this_test_because_it_hits_the_congress_gov_api_for_each_seeded_legislator_and_seeds_are_bad_in_tests = false

if skip_running_this_test_because_it_hits_the_congress_gov_api_for_each_seeded_legislator_and_seeds_are_bad_in_tests
  RSpec.describe CongressLegislatorVoteUpdateService do
    describe "#run" do
      context "a new CONGRESSIONAL Bill is created" do
        before do
          sway_locale = create(
            :sway_locale,
            CONGRESS
          )

          SeedLegislator.run([sway_locale])
        end

        after do
          Legislator.all.each do |l|
            l.bills.each(&:destroy)
          end
          Legislator.all.each(&:destroy)
          SwayLocale.find_by(CONGRESS).destroy
        end

        it "creates new LegislatorVotes for both the house and senate" do
          expect(Legislator.count).to be > 500
          expect(LegislatorVote.count).to eql(0)

          address = build(:address, region_code: "MD")

          sway_locale = SwayLocale.find_by(CONGRESS)
          expect(sway_locale).to_not be_nil

          district = build(:district, sway_locale:)

          senator = Legislator.find_by(external_id: "V000128").presence || build(:legislator, address:, district:, title: "Sen.", external_id: "V000128", first_name: "Chris",
            last_name: "Van Hollen")
          representative = Legislator.find_by(external_id: "M000687").presence || build(:legislator, address:, district:, first_name: "Kweisi", last_name: "Mfume",
            external_id: "M000687", title: "Rep.")

          bill = create(:bill, sway_locale: sway_locale, external_id: "hr815")
          create(:vote, bill:)

          expect(LegislatorVote.count).to eql(510)
          expect(LegislatorVote.where(legislator: senator).first&.support).to eql("FOR")
          expect(LegislatorVote.where(legislator: representative).first&.support).to eql("FOR")
        end
      end
    end
  end
end
