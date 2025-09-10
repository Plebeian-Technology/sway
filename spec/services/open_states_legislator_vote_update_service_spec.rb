# typed: true
# frozen_string_literal: true

require "open3"

MARYLAND = { city: "maryland", state: "maryland", country: "united_states" }.freeze

RSpec.describe OpenStatesLegislatorVoteUpdateService do
    before do
        dev_db_file_path = Rails.root.join("storage", "development.sqlite3").to_s
        data_file_path = Rails.root.join("storage", "dev-data.sql").to_s

        skip "No file found at path - #{dev_db_file_path}" unless File.exist?(dev_db_file_path)

        command =
            "sqlite3 storage/development.sqlite3 '.dump \"legislators\" \"sway_locales\" \"districts\"' | grep '^INSERT' > #{data_file_path}"
        _, stderr, status = Open3.capture3(command)
        expect(status.success?).to be true
        expect(stderr).to be_empty

        sql = File.read(data_file_path).gsub("'environment','development'", "'environment','test'")

        statements = sql.split(/;$/)
        statements.pop # remove empty line
        statements.each { |line| ActiveRecord::Base.connection.execute(line) }

        User.destroy_all

        skip "Legislators must be pre-seeded to run this test." if Legislator.count.zero?

        sway_locale = SwayLocale.find_by(MARYLAND)

        skip "Congress Locale must be pre-seeded to run this test." if sway_locale.nil?

        LegislatorVote.destroy_all
    end

    after(:all) do
        SwayLocale.destroy_all
        Legislator.destroy_all
        LegislatorVote.destroy_all
    end

    describe "#run" do
        context "a new MARYLAND Bill is created" do
            it "creates new LegislatorVotes for both the house and senate" do
                expect(Legislator.count).to be > 100
                expect(LegislatorVote.count).to eql(0)

                address = build(:address, region_code: "MD")

                sway_locale = SwayLocale.find_by(MARYLAND)
                expect(sway_locale).to_not be_nil

                district = build(:district, sway_locale:)

                president =
                    Legislator.find_by(external_id: "ocd-person/86f0d40f-05f4-46a2-9c24-21ff52fdc6fe").presence ||
                        build(
                            :legislator,
                            address:,
                            district:,
                            title: "Senator",
                            external_id: "ocd-person/86f0d40f-05f4-46a2-9c24-21ff52fdc6fe",
                            first_name: "Bill",
                            last_name: "Ferguson",
                        )

                speaker =
                    Legislator.find_by(external_id: "ocd-person/4bf0680f-fd5c-48a1-b6d3-73672f71048a").presence ||
                        build(
                            :legislator,
                            address:,
                            district:,
                            title: "Delegate",
                            external_id: "ocd-person/4bf0680f-fd5c-48a1-b6d3-73672f71048a",
                            first_name: "Adrienne",
                            last_name: "Jones",
                        )

                senator =
                    Legislator.find_by(external_id: "ocd-person/b0d22b6f-68c0-4dd0-892c-7844e6830693").presence ||
                        build(
                            :legislator,
                            address:,
                            district:,
                            title: "Senator",
                            external_id: "ocd-person/b0d22b6f-68c0-4dd0-892c-7844e6830693",
                            first_name: "Bryan",
                            last_name: "Simonaire",
                        )

                delegate =
                    Legislator.find_by(external_id: "ocd-person/0bdef1bb-ea31-4a27-937c-eb680ae67343").presence ||
                        build(
                            :legislator,
                            address:,
                            district:,
                            first_name: "Mary",
                            last_name: "Washington",
                            external_id: "ocd-person/0bdef1bb-ea31-4a27-937c-eb680ae67343",
                            title: "Delegate",
                        )

                bill = create(:bill, sway_locale: sway_locale, external_id: "hb0504")
                create(:vote, bill:, house_roll_call_vote_number: "1397", senate_roll_call_vote_number: "1178")

                expect(LegislatorVote.count).to eql(183)
                expect(LegislatorVote.where(legislator: president).first&.support).to eql(LegislatorVote::Support::FOR)
                expect(LegislatorVote.where(legislator: speaker).first&.support).to eql(LegislatorVote::Support::FOR)
                expect(LegislatorVote.where(legislator: senator).first&.support).to eql(LegislatorVote::Support::AGAINST)
                expect(LegislatorVote.where(legislator: delegate).first&.support).to eql(LegislatorVote::Support::FOR)

                expect(LegislatorVote.where(bill:, support: LegislatorVote::Support::FOR).size).to eql(131)
                expect(LegislatorVote.where(bill:, support: LegislatorVote::Support::AGAINST).size).to eql(50)
                expect(LegislatorVote.where(bill:, support: LegislatorVote::Support::ABSTAIN).size).to eql(2)
            end
        end
    end
end
