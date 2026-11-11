# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scraper::OpenStates::House::LegislatorVotes do
  # Checks the shape of what .process hands back: an array of
  # Scraper::LegislatorVote, every one of the 6 standard fields a String, and
  # support set to either FOR or AGAINST and nothing else.

  let(:sway_locale) do
    SwayLocale.find_by(city: "maryland", state: "maryland", country: "united_states") ||
      create(:sway_locale, city: "maryland", state: "maryland", country: "united_states")
  end
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) do
    create(
      :legislator,
      district: district,
      title: "Delegate",
      external_id: "ocd-person/ccc58f21-f2fd-4830-85b6-f490b0867d14",
      first_name: "Mary",
      last_name: "Washington",
      party: "D"
    )
  end
  let(:bill) do
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      external_id: "HB001",
      chamber: "house",
      introduced_date_time_utc: Time.zone.parse("2025-01-01")
    )
  end

  subject(:scraper) { described_class.new(bill: bill, roll_call_number: nil, roll_call_chamber: "house") }

  let(:open_states_votes_response) do
    {
      "votes" => [
        {
          "id" => "e0049138-1ad8-4506-a2a4-f4dd1251bbba",
          "option" => "yes",
          "voter_name" => "Washington",
          "voter" => {
            "id" => "ocd-person/ccc58f21-f2fd-4830-85b6-f490b0867d14",
            "name" => "Mary Washington",
            "party" => "Democratic",
            "current_role" => {
              "title" => "Delegate",
              "org_classification" => "lower",
              "district" => 43
            }
          }
        },
        {
          "id" => "d0049139-1ad8-4506-a2a4-f4dd1251bbba",
          "option" => "no",
          "voter_name" => "Brown",
          "voter" => {
            "id" => "ocd-person/ddd58f21-f2fd-4830-85b6-f490b0867d14",
            "name" => "James Brown",
            "party" => "Republican",
            "current_role" => {
              "title" => "Delegate",
              "org_classification" => "lower",
              "district" => 12
            }
          }
        }
      ]
    }
  end

  describe "#vote_number (WR-01 regression)" do
    # @lat: [[open-states-vote-number-unwired#Why the OpenStates House/Senate scrapers' vote_number raises]]
    it "raises NotImplementedError because the per-state path is unwired" do
      expect { scraper.send(:vote_number) }.to raise_error(NotImplementedError, /No OpenStates House scraper exists/)
    end
  end

  describe "#process (contract)" do
    it "returns Array<Scraper::LegislatorVote> (contract)" do
      allow(scraper).to receive(:result).and_return(
        {votes: open_states_votes_response["votes"].map(&:deep_symbolize_keys)}
      )
      result = scraper.process
      expect(result).to all(be_a(Scraper::LegislatorVote))
    end

    it "populates all 6 fields as Strings" do
      allow(scraper).to receive(:result).and_return(
        {votes: open_states_votes_response["votes"].map(&:deep_symbolize_keys)}
      )
      result = scraper.process
      expect(result).not_to be_empty
      result.each do |v|
        %i[external_id support first_name last_name party state_code].each do |attr|
          expect(v.public_send(attr)).to be_a(String), "expected #{attr} to be a String on #{v.inspect}"
        end
      end
    end

    it "only returns FOR or AGAINST" do
      allow(scraper).to receive(:result).and_return(
        {votes: open_states_votes_response["votes"].map(&:deep_symbolize_keys)}
      )
      result = scraper.process
      expect(result.map(&:support)).to all(be_in(%w[FOR AGAINST]))
    end
  end
end
