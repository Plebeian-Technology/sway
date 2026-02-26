# typed: true
# frozen_string_literal: true

require "open3"

CONGRESS = {
  city: "congress",
  state: "congress",
  country: "united_states",
}.freeze

RSpec.describe CongressLegislatorVoteUpdateService do
  before do
    data_file_path = Rails.root.join("storage", "dev-data.sql").to_s

    command =
      "sqlite3 storage/development.sqlite3 '.dump \"legislators\" \"sway_locales\" \"districts\"' | grep '^INSERT' > #{data_file_path}"
    _, stderr, status = Open3.capture3(command)

    expect(status.success?).to be true
    expect(stderr).to be_empty

    sql =
      File.read(data_file_path).gsub(
        "'environment','development'",
        "'environment','test'",
      )

    # Ensure test DB doesn't already contain the seeded rows that the dump will insert
    # (prevents UNIQUE constraint failures when the dump contains explicit ids).
    Legislator.destroy_all
    District.destroy_all
    SwayLocale.destroy_all

    statements = sql.split(/;$/)
    statements.pop # remove empty line
    statements.each { |line| ActiveRecord::Base.connection.execute(line) }

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
