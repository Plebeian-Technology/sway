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
    dev_db_file_path = Rails.root.join("storage", "development.sqlite3").to_s
    data_file_path = Rails.root.join("storage", "dev-data.sql").to_s

    unless File.exist?(dev_db_file_path)
      skip "No file found at path - #{dev_db_file_path}"
    end

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
    SwayLocale.destroy_all
    Legislator.destroy_all
    LegislatorVote.destroy_all
  end

  describe "#run" do
    context "a new CONGRESSIONAL Bill is created" do
      it "creates new LegislatorVotes for both the house and senate" do
        expect(Legislator.count).to be > 500
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

        expect(LegislatorVote.count).to be > 500
        expect(LegislatorVote.where(legislator: senator).first&.support).to eql(
          "AGAINST",
        )
        expect(
          LegislatorVote.where(legislator: representative).first&.support,
        ).to eql("AGAINST")
      end
    end
  end
end
