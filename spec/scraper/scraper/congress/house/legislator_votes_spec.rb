# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scraper::Congress::House::LegislatorVotes do
  include ActiveSupport::Testing::TimeHelpers

  subject(:scraper) { described_class.new(roll_call_number: 25, year: 2024) }

  let(:house_xml) do
    <<~JSON
      {
        "houseRollCallVoteMemberVotes": {
          "congress": 118,
          "sessionNumber": 2,
          "rollCallNumber": 25,
          "voteQuestion": "On Passage",
          "startDate": "2024-01-25T14:30:00Z",
          "legislationType": "HR",
          "legislationNumber": 5585,
          "results": [
            {
              "bioguideID": "M000687",
              "firstName": "Kweisi",
              "lastName": "Mfume",
              "voteParty": "D",
              "voteState": "MD",
              "voteCast": "Yea"
            },
            {
              "bioguideID": "R000600",
              "firstName": "John",
              "lastName": "Rogers",
              "voteParty": "R",
              "voteState": "CA",
              "voteCast": "Nay"
            },
            {
              "bioguideID": "A000100",
              "firstName": "Arthur",
              "lastName": "Aye",
              "voteParty": "D",
              "voteState": "NY",
              "voteCast": "Aye"
            },
            {
              "bioguideID": "B000200",
              "firstName": "Bob",
              "lastName": "No",
              "voteParty": "R",
              "voteState": "TX",
              "voteCast": "No"
            },
            {
              "bioguideID": "X000001",
              "firstName": "Alice",
              "lastName": "Jones",
              "voteParty": "D",
              "voteState": "TX",
              "voteCast": "Not Voting"
            },
            {
              "bioguideID": "P000002",
              "firstName": "Peter",
              "lastName": "Present",
              "voteParty": "D",
              "voteState": "IL",
              "voteCast": "Present"
            },
            {
              "bioguideID": "",
              "firstName": "Empty",
              "lastName": "ID",
              "voteParty": "D",
              "voteState": "VA",
              "voteCast": "Yea"
            }
          ]
        }
      }
    JSON
  end

  # @lat: [[congress-roll-calls#Roll-call numbering restarts every year]]
  describe "#do_request builds the URL from the passed year" do
    it "uses the vote's year, not the clock's" do
      travel_to(Time.zone.local(2026, 7, 24)) do
        fake_conn = instance_double(Faraday::Connection)
        fake_response = instance_double(Faraday::Response, status: 200, body: house_xml)
        allow(Sway::FaradayStack).to receive(:congress_gov).and_return(fake_conn)
        allow(fake_conn).to receive(:get).and_return(fake_response)

        expect(scraper.do_request).to eq(house_xml)
        expect(fake_conn).to have_received(:get).with(
          "house-vote/118/2/25/members",
          {api_key: EnvSecret.congress_gov_api_key!, format: :json}
        )
      end
    end

    it "computes session 1 for odd years" do
      odd_scraper = described_class.new(roll_call_number: 10, year: 2023)
      fake_conn = instance_double(Faraday::Connection)
      fake_response = instance_double(Faraday::Response, status: 200, body: "{}")
      allow(Sway::FaradayStack).to receive(:congress_gov).and_return(fake_conn)
      allow(fake_conn).to receive(:get).and_return(fake_response)

      odd_scraper.do_request
      expect(fake_conn).to have_received(:get).with(
        "house-vote/118/1/10/members",
        {api_key: EnvSecret.congress_gov_api_key!, format: :json}
      )
    end

    it "returns nil when roll_call_number is blank" do
      blank_scraper = described_class.new(roll_call_number: nil, year: 2024)
      expect(blank_scraper.do_request).to be_nil
    end

    it "raises Scraper::Congress::RollCallUnavailable on non-200 HTTP status" do
      stub_request(:get, "https://api.congress.gov/v3/house-vote/118/2/25/members")
        .with(query: {api_key: EnvSecret.congress_gov_api_key!, format: "json"})
        .to_return(status: 404, body: "Not Found")

      expect { scraper.do_request }.to raise_error(Scraper::Congress::RollCallUnavailable) do |error|
        expect(error.chamber).to eq(:house)
        expect(error.congress).to eq(118)
        expect(error.session).to eq(2)
        expect(error.roll_call_number).to eq(25)
        expect(error.reason).to eq("http_404")
      end
    end
  end

  # @lat: [[congress-roll-calls#Why a fetched record has to name the bill's own vote]]
  describe "#identity" do
    before { allow(scraper).to receive(:result).and_return(JSON.parse(house_xml)) }

    it "reads the bill, the question and the day the clerk states" do
      identity = scraper.identity

      expect(identity.document_name).to eq("HR 5585")
      expect(identity.names?("hr5585")).to be(true)
      expect(identity.question).to eq("On Passage")
      expect(identity.voted_on).to eq(Date.new(2024, 1, 25))
    end

    it "answers with an empty identity when the record has no metadata" do
      allow(scraper).to receive(:result).and_return({})
      identity = scraper.identity

      expect(identity.document_name).to be_nil
      expect(identity.question).to be_nil
      expect(identity.voted_on).to be_nil
    end

    # @lat: [[congress-roll-calls#Why procedural roll calls name no bill]]
    it "does not treat a procedural record as naming a bill" do
      allow(scraper).to receive(:result).and_return(
        {"houseRollCallVoteMemberVotes" => {"voteQuestion" => "On Motion to Adjourn"}}
      )

      expect(scraper.identity.document_name).to be_nil
      expect(scraper.identity.names?("hr5585")).to be(false)
    end
  end

  describe "#process (contract)" do
    before do
      allow(scraper).to receive(:result).and_return(JSON.parse(house_xml))
    end

    it "returns Array<Scraper::LegislatorVote> (contract)" do
      result = scraper.process
      expect(result).to all(be_a(Scraper::LegislatorVote))
    end

    it "populates all 6 fields as Strings" do
      result = scraper.process
      expect(result).not_to be_empty
      result.each do |v|
        %i[external_id support first_name last_name party state_code].each do |attr|
          expect(v.public_send(attr)).to be_a(String), "expected #{attr} to be a String on #{v.inspect}"
        end
      end
    end

    it "only returns FOR or AGAINST (not Not Voting)" do
      result = scraper.process
      expect(result.map(&:support)).to all(be_in(%w[FOR AGAINST]))
    end

    it "maps Yea to FOR" do
      result = scraper.process
      mfume = result.find { |v| v.external_id == "M000687" }
      expect(mfume&.support).to eq("FOR")
    end

    it "maps Nay to AGAINST" do
      result = scraper.process
      rogers = result.find { |v| v.external_id == "R000600" }
      expect(rogers&.support).to eq("AGAINST")
    end

    it "maps Aye to FOR and No to AGAINST" do
      result = scraper.process
      aye_vote = result.find { |v| v.external_id == "A000100" }
      no_vote = result.find { |v| v.external_id == "B000200" }
      expect(aye_vote&.support).to eq("FOR")
      expect(no_vote&.support).to eq("AGAINST")
    end

    it "skips Not Voting and Present entries" do
      result = scraper.process
      ids = result.map(&:external_id)
      expect(ids).not_to include("X000001")
      expect(ids).not_to include("P000002")
    end

    it "skips entries with missing required fields" do
      result = scraper.process
      expect(result.map(&:first_name)).not_to include("Empty")
    end

    it "returns an empty array when result is nil" do
      allow(scraper).to receive(:result).and_return(nil)
      expect(scraper.process).to eq([])
    end
  end

  describe "#result" do
    it "parses raw JSON string into a Hash" do
      allow(scraper).to receive(:do_request).and_return(house_xml)
      expect(scraper.send(:result)).to be_a(Hash)
      expect(scraper.send(:result).dig("houseRollCallVoteMemberVotes", "rollCallNumber")).to eq(25)
    end

    it "returns already parsed Hash directly" do
      parsed = {"houseRollCallVoteMemberVotes" => {"rollCallNumber" => 25}}
      allow(scraper).to receive(:do_request).and_return(parsed)
      expect(scraper.send(:result)).to eq(parsed)
    end

    it "converts invalid JSON on a 200 response to RollCallUnavailable(reason: 'invalid_json')" do
      stub_request(:get, "https://api.congress.gov/v3/house-vote/118/2/25/members")
        .with(query: {api_key: EnvSecret.congress_gov_api_key!, format: "json"})
        .to_return(status: 200, body: "not valid json {")

      stub_request(:get, "https://clerk.house.gov/evs/2024/roll025.xml")
        .to_return(status: 404, body: "Not Found")

      expect { scraper.process }.to raise_error(Scraper::Congress::RollCallUnavailable) do |error|
        expect(error.chamber).to eq(:house)
        expect(error.congress).to eq(118)
        expect(error.session).to eq(2)
        expect(error.roll_call_number).to eq(25)
        expect(error.reason).to include("invalid_json")
      end
    end

    it "propagates Faraday::ConnectionFailed out of #process unrescued" do
      fast_conn = Sway::FaradayStack.build(
        base_url: "https://api.congress.gov/v3",
        retry_options: {
          max: 0,
          interval: 0.5,
          backoff_factor: 2,
          retry_statuses: [429, 500, 502, 503, 504],
          methods: %i[get],
          exceptions: Sway::FaradayStack::TRANSPORT_RETRY_EXCEPTIONS
        }
      )
      allow(Sway::FaradayStack).to receive(:congress_gov).and_return(fast_conn)

      stub_request(:get, "https://api.congress.gov/v3/house-vote/118/2/25/members")
        .with(query: {api_key: EnvSecret.congress_gov_api_key!, format: "json"})
        .to_raise(Faraday::ConnectionFailed.new("connection failed"))

      expect { scraper.process }.to raise_error(Faraday::ConnectionFailed)
    end

    it "propagates Net::ReadTimeout as Faraday::TimeoutError out of #process" do
      fast_conn = Sway::FaradayStack.build(
        base_url: "https://api.congress.gov/v3",
        retry_options: {
          max: 0,
          interval: 0.5,
          backoff_factor: 2,
          retry_statuses: [429, 500, 502, 503, 504],
          methods: %i[get],
          exceptions: Sway::FaradayStack::TRANSPORT_RETRY_EXCEPTIONS
        }
      )
      allow(Sway::FaradayStack).to receive(:congress_gov).and_return(fast_conn)

      stub_request(:get, "https://api.congress.gov/v3/house-vote/118/2/25/members")
        .with(query: {api_key: EnvSecret.congress_gov_api_key!, format: "json"})
        .to_raise(Net::ReadTimeout)

      expect { scraper.process }.to raise_error(Faraday::TimeoutError)
    end

    it "propagates missing API key KeyError unrescued" do
      allow(EnvSecret).to receive(:congress_gov_api_key!).and_raise(KeyError.new("key not found: CONGRESS_GOV_API_KEY"))

      expect { scraper.process }.to raise_error(KeyError, /CONGRESS_GOV_API_KEY/)
    end

    it "memoizes transport failure so subsequent calls to #identity re-raise without a second network round trip" do
      fast_conn = Sway::FaradayStack.build(
        base_url: "https://api.congress.gov/v3",
        retry_options: {
          max: 0,
          interval: 0.5,
          backoff_factor: 2,
          retry_statuses: [429, 500, 502, 503, 504],
          methods: %i[get],
          exceptions: Sway::FaradayStack::TRANSPORT_RETRY_EXCEPTIONS
        }
      )
      allow(Sway::FaradayStack).to receive(:congress_gov).and_return(fast_conn)

      req_stub = stub_request(:get, "https://api.congress.gov/v3/house-vote/118/2/25/members")
        .with(query: {api_key: EnvSecret.congress_gov_api_key!, format: "json"})
        .to_raise(Faraday::ConnectionFailed.new("connection failed"))

      expect { scraper.process }.to raise_error(Faraday::ConnectionFailed)
      expect { scraper.identity }.to raise_error(Faraday::ConnectionFailed)
      expect(req_stub).to have_been_requested.once
    end
  end

  describe "dual-stage fetching and clerk XML fallback" do
    it "uses Congress.gov 200 and never requests clerk.house.gov" do
      congress_stub = stub_request(:get, "https://api.congress.gov/v3/house-vote/118/2/25/members")
        .with(query: {api_key: EnvSecret.congress_gov_api_key!, format: "json"})
        .to_return(status: 200, body: house_xml)

      clerk_stub = stub_request(:get, %r{https://clerk\.house\.gov/.*})

      votes = scraper.process
      expect(votes).not_to be_empty
      expect(congress_stub).to have_been_requested.once
      expect(clerk_stub).not_to have_been_requested
    end

    it "falls back to clerk XML when Congress.gov returns 404" do
      clerk_xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <rollcall-vote>
          <vote-metadata>
            <rollcall-num>25</rollcall-num>
            <legis-num>H R 5585</legis-num>
            <vote-question>On Passage</vote-question>
            <action-date>25-Jan-2024</action-date>
          </vote-metadata>
          <vote-data>
            <recorded-vote>
              <legislator name-id="M000687" sort-field="Mfume" unaccented-name="Mfume" party="D" state="MD" role="legislator">Mfume</legislator>
              <vote>Yea</vote>
            </recorded-vote>
            <recorded-vote>
              <legislator name-id="A000100" sort-field="Aye" unaccented-name="Aye" party="D" state="NY" role="legislator">Aye</legislator>
              <vote>Aye</vote>
            </recorded-vote>
            <recorded-vote>
              <legislator name-id="R000600" sort-field="Rogers" unaccented-name="Rogers" party="R" state="CA" role="legislator">Rogers</legislator>
              <vote>Nay</vote>
            </recorded-vote>
            <recorded-vote>
              <legislator name-id="B000200" sort-field="No" unaccented-name="No" party="R" state="TX" role="legislator">No</legislator>
              <vote>No</vote>
            </recorded-vote>
            <recorded-vote>
              <legislator name-id="P000002" sort-field="Present" unaccented-name="Present" party="D" state="IL" role="legislator">Present</legislator>
              <vote>Present</vote>
            </recorded-vote>
            <recorded-vote>
              <legislator name-id="X000001" sort-field="Jones" unaccented-name="Jones" party="D" state="TX" role="legislator">Jones</legislator>
              <vote>Not Voting</vote>
            </recorded-vote>
          </vote-data>
        </rollcall-vote>
      XML

      stub_request(:get, "https://api.congress.gov/v3/house-vote/118/2/25/members")
        .with(query: {api_key: EnvSecret.congress_gov_api_key!, format: "json"})
        .to_return(status: 404, body: "Not Found")

      stub_request(:get, "https://clerk.house.gov/evs/2024/roll025.xml")
        .to_return(status: 200, body: clerk_xml, headers: {"Content-Type" => "application/xml"})

      allow(SwayLogging).to receive(:warn)

      identity = scraper.identity
      expect(identity.document_name).to eq("H R 5585")
      expect(identity.question).to eq("On Passage")
      expect(identity.voted_on).to eq(Date.new(2024, 1, 25))

      votes = scraper.process
      expect(votes).to eq([
        Scraper::LegislatorVote.new(external_id: "M000687", support: "FOR", first_name: "", last_name: "Mfume", party: "D", state_code: "MD"),
        Scraper::LegislatorVote.new(external_id: "A000100", support: "FOR", first_name: "", last_name: "Aye", party: "D", state_code: "NY"),
        Scraper::LegislatorVote.new(external_id: "R000600", support: "AGAINST", first_name: "", last_name: "Rogers", party: "R", state_code: "CA"),
        Scraper::LegislatorVote.new(external_id: "B000200", support: "AGAINST", first_name: "", last_name: "No", party: "R", state_code: "TX")
      ])

      expect(SwayLogging).to have_received(:warn).with(
        "house_roll_call.primary_fetch_failed",
        hash_including(congress: 118, session: 2, roll_call_number: 25, error: "http_404")
      )
    end

    [
      ["an empty body", ""],
      ["a JSON Array", "[]"],
      ["a JSON Hash without houseRollCallVoteMemberVotes", "{}"]
    ].each do |description, invalid_body|
      it "falls back to clerk XML and logs invalid_json when Congress.gov returns 200 with #{description}" do
        clerk_xml = <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <rollcall-vote>
            <vote-metadata>
              <rollcall-num>25</rollcall-num>
              <legis-num>H R 5585</legis-num>
              <vote-question>On Passage</vote-question>
              <action-date>25-Jan-2024</action-date>
            </vote-metadata>
            <vote-data>
              <recorded-vote>
                <legislator name-id="M000687" sort-field="Mfume" unaccented-name="Mfume" party="D" state="MD" role="legislator">Mfume</legislator>
                <vote>Yea</vote>
              </recorded-vote>
            </vote-data>
          </rollcall-vote>
        XML

        stub_request(:get, "https://api.congress.gov/v3/house-vote/118/2/25/members")
          .with(query: {api_key: EnvSecret.congress_gov_api_key!, format: "json"})
          .to_return(status: 200, body: invalid_body)

        stub_request(:get, "https://clerk.house.gov/evs/2024/roll025.xml")
          .to_return(status: 200, body: clerk_xml, headers: {"Content-Type" => "application/xml"})

        allow(SwayLogging).to receive(:warn)

        expect(scraper.identity.document_name).to eq("H R 5585")
        expect(scraper.process).to eq([
          Scraper::LegislatorVote.new(external_id: "M000687", support: "FOR", first_name: "", last_name: "Mfume", party: "D", state_code: "MD")
        ])

        expect(SwayLogging).to have_received(:warn).with(
          "house_roll_call.primary_fetch_failed",
          hash_including(congress: 118, session: 2, roll_call_number: 25, error: "invalid_json")
        )
      end

      it "raises RollCallUnavailable when Congress.gov returns 200 with #{description} and clerk fails" do
        stub_request(:get, "https://api.congress.gov/v3/house-vote/118/2/25/members")
          .with(query: {api_key: EnvSecret.congress_gov_api_key!, format: "json"})
          .to_return(status: 200, body: invalid_body)

        stub_request(:get, "https://clerk.house.gov/evs/2024/roll025.xml")
          .to_return(status: 404, body: "Not Found")

        allow(SwayLogging).to receive(:warn)

        expect { scraper.process }.to raise_error(Scraper::Congress::RollCallUnavailable) do |error|
          expect(error.reason).to eq("primary: invalid_json, fallback: http_404")
        end
        expect { scraper.identity }.to raise_error(Scraper::Congress::RollCallUnavailable)

        expect(SwayLogging).to have_received(:warn).with(
          "house_roll_call.primary_fetch_failed",
          hash_including(congress: 118, session: 2, roll_call_number: 25, error: "invalid_json")
        )
      end
    end

    it "raises RollCallUnavailable naming both failures when Congress.gov and clerk both return 404" do
      stub_request(:get, "https://api.congress.gov/v3/house-vote/118/2/25/members")
        .with(query: {api_key: EnvSecret.congress_gov_api_key!, format: "json"})
        .to_return(status: 404, body: "Not Found")

      stub_request(:get, "https://clerk.house.gov/evs/2024/roll025.xml")
        .to_return(status: 404, body: "Not Found")

      allow(SwayLogging).to receive(:warn)

      expect { scraper.process }.to raise_error(Scraper::Congress::RollCallUnavailable) do |error|
        expect(error.chamber).to eq(:house)
        expect(error.congress).to eq(118)
        expect(error.session).to eq(2)
        expect(error.roll_call_number).to eq(25)
        expect(error.reason).to include("http_404")
        expect(error.reason).to match(/primary.*fallback/i)
      end

      expect(SwayLogging).to have_received(:warn).with(
        "house_roll_call.fallback_fetch_failed",
        hash_including(congress: 118, session: 2, roll_call_number: 25, error: "http_404")
      )
    end

    it "propagates Congress.gov transport error immediately without fallback to clerk" do
      fast_conn = Sway::FaradayStack.build(
        base_url: "https://api.congress.gov/v3",
        retry_options: {
          max: 0,
          interval: 0.5,
          backoff_factor: 2,
          retry_statuses: [429, 500, 502, 503, 504],
          methods: %i[get],
          exceptions: Sway::FaradayStack::TRANSPORT_RETRY_EXCEPTIONS
        }
      )
      allow(Sway::FaradayStack).to receive(:congress_gov).and_return(fast_conn)

      stub_request(:get, "https://api.congress.gov/v3/house-vote/118/2/25/members")
        .with(query: {api_key: EnvSecret.congress_gov_api_key!, format: "json"})
        .to_raise(Faraday::ConnectionFailed.new("connection failed"))

      clerk_stub = stub_request(:get, %r{https://clerk\.house\.gov/.*})

      expect { scraper.process }.to raise_error(Faraday::ConnectionFailed)
      expect(clerk_stub).not_to have_been_requested
    end

    it "propagates Faraday::ConnectionFailed when clerk fallback encounters a transport error" do
      stub_request(:get, "https://api.congress.gov/v3/house-vote/118/2/25/members")
        .with(query: {api_key: EnvSecret.congress_gov_api_key!, format: "json"})
        .to_return(status: 404, body: "Not Found")

      fast_clerk_conn = Sway::FaradayStack.build(
        base_url: "https://clerk.house.gov",
        retry_options: {
          max: 0,
          interval: 0.5,
          backoff_factor: 2,
          retry_statuses: [429, 500, 502, 503, 504],
          methods: %i[get],
          exceptions: Sway::FaradayStack::TRANSPORT_RETRY_EXCEPTIONS
        }
      )
      allow(scraper).to receive(:clerk_conn).and_return(fast_clerk_conn)

      stub_request(:get, "https://clerk.house.gov/evs/2024/roll025.xml")
        .to_raise(Faraday::ConnectionFailed.new("clerk connection failed"))

      expect { scraper.process }.to raise_error(Faraday::ConnectionFailed, /clerk connection failed/)
    end

    it "memoizes dual-stage failure so subsequent #identity does not re-request either stage" do
      congress_stub = stub_request(:get, "https://api.congress.gov/v3/house-vote/118/2/25/members")
        .with(query: {api_key: EnvSecret.congress_gov_api_key!, format: "json"})
        .to_return(status: 404, body: "Not Found")

      clerk_stub = stub_request(:get, "https://clerk.house.gov/evs/2024/roll025.xml")
        .to_return(status: 404, body: "Not Found")

      expect { scraper.process }.to raise_error(Scraper::Congress::RollCallUnavailable)
      expect { scraper.identity }.to raise_error(Scraper::Congress::RollCallUnavailable)

      expect(congress_stub).to have_been_requested.once
      expect(clerk_stub).to have_been_requested.once
    end
  end
end
