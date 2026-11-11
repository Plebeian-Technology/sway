# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scraper::Congress::Senate::LegislatorVotes do
  include ActiveSupport::Testing::TimeHelpers

  # Checks the shape of what .process hands back: an array of
  # Scraper::LegislatorVote, every one of the 6 standard fields a String, and
  # support set to either FOR or AGAINST and nothing else.

  subject(:scraper) { described_class.new(year: 2025, roll_call_number: 421) }

  # Example XML in the same shape the Senate roll_call_vote feed uses
  let(:senate_xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <roll_call_vote>
        <members>
          <member>
            <first_name>Chris</first_name>
            <last_name>Van Hollen</last_name>
            <state>MD</state>
            <party>D</party>
            <vote_cast>Yea</vote_cast>
            <lis_member_id>V000128</lis_member_id>
          </member>
          <member>
            <first_name>John</first_name>
            <last_name>Smith</last_name>
            <state>CA</state>
            <party>R</party>
            <vote_cast>Nay</vote_cast>
            <lis_member_id>S999999</lis_member_id>
          </member>
          <member>
            <first_name>Jane</first_name>
            <last_name>Doe</last_name>
            <state>TX</state>
            <party>D</party>
            <vote_cast>Not Voting</vote_cast>
            <lis_member_id>D888888</lis_member_id>
          </member>
        </members>
      </roll_call_vote>
    XML
  end

  # @lat: [[congress-roll-calls#Roll-call numbering restarts every year]]
  describe "#do_request builds the URL from the passed year" do
    it "maps an even year to session 2 of its Congress" do
      travel_to(Time.zone.local(2026, 7, 24)) do
        even_year_scraper = described_class.new(year: 2024, roll_call_number: 200)
        allow(even_year_scraper).to receive(:get)
        even_year_scraper.do_request
        expect(even_year_scraper).to have_received(:get)
          .with("legislative/LIS/roll_call_votes/vote1182/vote_118_2_00200.xml")
      end
    end

    it "maps an odd year to session 1 of its Congress" do
      travel_to(Time.zone.local(2026, 7, 24)) do
        odd_year_scraper = described_class.new(year: 2025, roll_call_number: 15)
        allow(odd_year_scraper).to receive(:get)
        odd_year_scraper.do_request
        expect(odd_year_scraper).to have_received(:get)
          .with("legislative/LIS/roll_call_votes/vote1191/vote_119_1_00015.xml")
      end
    end

    it "coerces a String year to compute congress and session without raising NoMethodError" do
      string_year_scraper = described_class.new(year: "2025", roll_call_number: 15)
      allow(string_year_scraper).to receive(:get)
      string_year_scraper.do_request
      expect(string_year_scraper).to have_received(:get)
        .with("legislative/LIS/roll_call_votes/vote1191/vote_119_1_00015.xml")
    end
  end

  # The name sits under <document> and the title ends with a newline — the real
  # shape of roll call 200 of 2024. "On the Motion" alone cannot tell a
  # concurrence from a motion to table.
  describe "#identity" do
    let(:motion_xml) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <roll_call_vote>
          <vote_date>June 18, 2024,  05:47 PM</vote_date>
          <question>On the Motion</question>
          <vote_title>Motion to Concur in the House Amendments to S. 870
          </vote_title>
          <document>
            <document_name>S. 870</document_name>
          </document>
        </roll_call_vote>
      XML
    end

    it "reads the document, the question, the title and the day" do
      allow(scraper).to receive(:result).and_return(Hash.from_xml(motion_xml))
      identity = scraper.identity

      expect(identity.document_name).to eq("S. 870")
      expect(identity.question).to eq("On the Motion")
      expect(identity.title).to eq("Motion to Concur in the House Amendments to S. 870")
      expect(identity.voted_on).to eq(Date.new(2024, 6, 18))
    end

    it "answers with an empty identity when the body is not a vote" do
      allow(scraper).to receive(:result).and_return({})
      identity = scraper.identity

      expect(identity.question).to be_nil
      expect(identity.title).to be_nil
    end
  end

  describe "#process (contract)" do
    before do
      allow(scraper).to receive(:result).and_return(Hash.from_xml(senate_xml))
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

    it "only returns FOR or AGAINST (Yea=FOR, Nay=AGAINST, Not Voting skipped)" do
      result = scraper.process
      expect(result.map(&:support)).to all(be_in(%w[FOR AGAINST]))
    end

    it "maps Yea to FOR" do
      result = scraper.process
      van_hollen = result.find { |v| v.last_name == "Van Hollen" }
      expect(van_hollen&.support).to eq("FOR")
    end

    it "maps Nay to AGAINST" do
      result = scraper.process
      smith = result.find { |v| v.last_name == "Smith" }
      expect(smith&.support).to eq("AGAINST")
    end

    it "skips Not Voting entries" do
      result = scraper.process
      expect(result.map(&:last_name)).not_to include("Doe")
    end
  end

  describe "dual-stage fallback to Voteview" do
    it "uses primary XML without calling Voteview when senate.gov responds with valid XML" do
      valid_xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <roll_call_vote>
          <vote_date>June 18, 2025, 05:47 PM</vote_date>
          <question>On the Motion</question>
          <vote_title>Motion to Concur</vote_title>
          <document>
            <document_name>S. 870</document_name>
          </document>
          <members>
            <member>
              <first_name>Chris</first_name>
              <last_name>Van Hollen</last_name>
              <state>MD</state>
              <party>D</party>
              <vote_cast>Yea</vote_cast>
              <lis_member_id>V000128</lis_member_id>
            </member>
          </members>
        </roll_call_vote>
      XML

      stub_request(:get, "https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00421.xml")
        .to_return(status: 200, body: valid_xml)

      test_scraper = described_class.new(year: 2025, roll_call_number: 421)
      expect(test_scraper).not_to receive(:voteview_conn)

      votes = test_scraper.process
      identity = test_scraper.identity

      expect(identity.document_name).to eq("S. 870")
      expect(identity.question).to eq("On the Motion")
      expect(identity.voted_on).to eq(Date.new(2025, 6, 18))
      expect(votes.size).to eq(1)
      expect(votes.first.last_name).to eq("Van Hollen")
    end

    it "falls back to Voteview when senate.gov returns an HTML challenge page" do
      challenge_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head><title>Access Denied - Akamai Bot Manager</title></head>
          <body>Please verify you are human</body>
        </html>
      HTML

      stub_request(:get, "https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00421.xml")
        .to_return(status: 403, body: challenge_html)

      voteview_index = [
        {"session" => 1, "clerk_rollnumber" => 421, "rollnumber" => 421}
      ].to_json

      voteview_download = {
        "rollcalls" => [
          {
            "bill_number" => "S. 870",
            "question" => "On the Motion",
            "vote_title" => "Motion to Concur in the House Amendments to S. 870",
            "date" => "2025-06-18",
            "votes" => [
              {
                "lis_member_id" => "S309",
                "first_name" => "Bob",
                "last_name" => "Casey",
                "party_name" => "Democrat",
                "state_abbrev" => "PA",
                "cast_str" => "Yea"
              },
              {
                "lis_member_id" => "S999",
                "first_name" => "John",
                "last_name" => "Smith",
                "party_name" => "Republican",
                "state_abbrev" => "TX",
                "cast_str" => "Nay"
              },
              {
                "lis_member_id" => "S888",
                "first_name" => "Jane",
                "last_name" => "Doe",
                "party_name" => "Democrat",
                "state_abbrev" => "CA",
                "cast_str" => "Not Voting"
              }
            ]
          }
        ]
      }.to_json

      stub_request(:get, "https://voteview.com/static/data/out/rollcalls/S119_rollcalls.json")
        .to_return(status: 200, body: voteview_index)
      stub_request(:get, "https://voteview.com/api/download?rollcall_id=RS1190421")
        .to_return(status: 200, body: voteview_download)

      allow(SwayLogging).to receive(:warn)

      test_scraper = described_class.new(year: 2025, roll_call_number: 421)
      votes = test_scraper.process
      identity = test_scraper.identity

      expect(SwayLogging).to have_received(:warn).with(
        "senate_roll_call.primary_fetch_failed",
        hash_including(congress: 119, session: 1, roll_call_number: 421)
      )

      expect(identity.document_name).to eq("S. 870")
      expect(identity.question).to eq("On the Motion")
      expect(identity.title).to eq("Motion to Concur in the House Amendments to S. 870")
      expect(identity.voted_on).to eq(Date.new(2025, 6, 18))

      expect(votes.size).to eq(2)
      casey = votes.find { |v| v.last_name == "Casey" }
      expect(casey.external_id).to eq("S309")
      expect(casey.support).to eq("FOR")
      expect(casey.party).to eq("D")
      expect(casey.state_code).to eq("PA")

      smith = votes.find { |v| v.last_name == "Smith" }
      expect(smith.external_id).to eq("S999")
      expect(smith.support).to eq("AGAINST")
      expect(smith.party).to eq("R")
      expect(smith.state_code).to eq("TX")
    end

    it "falls back to Voteview when senate.gov raises a network connection error" do
      stub_request(:get, "https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00421.xml")
        .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

      voteview_index = [
        {"session" => 1, "clerk_rollnumber" => 421, "rollnumber" => 421}
      ].to_json

      voteview_download = {
        "rollcalls" => [
          {
            "bill_number" => "S. 870",
            "question" => "On the Motion",
            "vote_title" => "Motion to Concur",
            "date" => "2025-06-18",
            "votes" => [
              {
                "lis_member_id" => "S309",
                "first_name" => "Bob",
                "last_name" => "Casey",
                "party" => "Democrat",
                "state" => "PA",
                "vote" => 1
              }
            ]
          }
        ]
      }.to_json

      stub_request(:get, "https://voteview.com/static/data/out/rollcalls/S119_rollcalls.json")
        .to_return(status: 200, body: voteview_index)
      stub_request(:get, "https://voteview.com/api/download?rollcall_id=RS1190421")
        .to_return(status: 200, body: voteview_download)

      allow(SwayLogging).to receive(:warn)

      test_scraper = described_class.new(year: 2025, roll_call_number: 421)
      votes = test_scraper.process
      identity = test_scraper.identity

      expect(SwayLogging).to have_received(:warn).with(
        "senate_roll_call.primary_fetch_failed",
        hash_including(congress: 119, session: 1, roll_call_number: 421)
      )

      expect(identity.document_name).to eq("S. 870")
      expect(identity.voted_on).to eq(Date.new(2025, 6, 18))
      expect(votes.size).to eq(1)
      expect(votes.first.support).to eq("FOR")
      expect(votes.first.party).to eq("D")
    end

    it "raises RollCallUnavailable without reporting to Sentry when both primary and Voteview fallback fail" do
      stub_request(:get, "https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00421.xml")
        .to_return(status: 403, body: "<html>Challenge</html>")

      stub_request(:get, "https://voteview.com/static/data/out/rollcalls/S119_rollcalls.json")
        .to_return(status: 500, body: "Server Error")

      allow(SwayLogging).to receive(:warn)
      allow(Sentry).to receive(:capture_message)

      test_scraper = described_class.new(year: 2025, roll_call_number: 421)
      expect { test_scraper.process }.to raise_error(Scraper::Congress::RollCallUnavailable) do |error|
        expect(error.chamber).to eq(:senate)
        expect(error.congress).to eq(119)
        expect(error.session).to eq(1)
        expect(error.roll_call_number).to eq(421)
        expect(error.reason).to include("fallback: index_http_500")
        expect(error.reason).to match(/\Aprimary: .+, fallback: index_http_500\z/)
      end

      expect(Sentry).not_to have_received(:capture_message)
      expect(SwayLogging).to have_received(:warn).with(
        "senate_roll_call.primary_fetch_failed",
        hash_including(congress: 119, session: 1, roll_call_number: 421)
      )
      expect(SwayLogging).to have_received(:warn).with(
        "senate_roll_call.fallback_fetch_failed",
        hash_including(congress: 119, session: 1, roll_call_number: 421)
      )
    end

    it "memoizes the failure exception so subsequent calls do not repeat fetch stages or log again" do
      stub_request(:get, "https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00421.xml")
        .to_return(status: 403, body: "<html>Challenge</html>")

      stub_request(:get, "https://voteview.com/static/data/out/rollcalls/S119_rollcalls.json")
        .to_return(status: 500, body: "Server Error")

      allow(SwayLogging).to receive(:warn)

      test_scraper = described_class.new(year: 2025, roll_call_number: 421)
      expect { test_scraper.process }.to raise_error(Scraper::Congress::RollCallUnavailable)
      expect { test_scraper.identity }.to raise_error(Scraper::Congress::RollCallUnavailable)

      expect(SwayLogging).to have_received(:warn).with(
        "senate_roll_call.primary_fetch_failed",
        any_args
      ).once
      expect(SwayLogging).to have_received(:warn).with(
        "senate_roll_call.fallback_fetch_failed",
        any_args
      ).once
    end

    it "returns an empty array and empty identity without raising when roll_call_number is blank" do
      blank_scraper = described_class.new(year: 2025, roll_call_number: nil)
      expect(blank_scraper.process).to eq([])
      identity = blank_scraper.identity
      expect(identity.question).to be_nil
    end

    it "returns an empty array and empty identity without making HTTP requests when roll_call_number is an empty string" do
      WebMock::RequestRegistry.instance.reset!
      empty_scraper = described_class.new(year: 2025, roll_call_number: "")
      expect(empty_scraper.do_request).to be_nil
      expect(empty_scraper.process).to eq([])
      identity = empty_scraper.identity
      expect(identity.document_name).to be_nil
      expect(identity.question).to be_nil
      expect(identity.title).to be_nil
      expect(identity.voted_on).to be_nil
      expect(WebMock).not_to have_requested(:any, %r{senate\.gov|voteview\.com})
    end
  end

  describe "Voteview index caching" do
    around do |example|
      original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = original_cache
    end

    it "shares the cached index between scrapers for different roll calls in the same Congress" do
      raw_index = [
        {"session" => 1, "clerk_rollnumber" => 421, "rollnumber" => 421, "extra_field" => "ignore"},
        {"session" => 1, "clerk_rollnumber" => 422, "rollnumber" => 422, "extra_field" => "ignore"}
      ]
      voteview_download_421 = {
        "rollcalls" => [
          {
            "bill_number" => "S. 870",
            "question" => "On the Motion",
            "date" => "2025-06-18",
            "votes" => [{"lis_member_id" => "S309", "first_name" => "Bob", "last_name" => "Casey", "party" => "Democrat", "state" => "PA", "vote" => 1}]
          }
        ]
      }.to_json
      voteview_download_422 = {
        "rollcalls" => [
          {
            "bill_number" => "S. 871",
            "question" => "On Passage",
            "date" => "2025-06-19",
            "votes" => [{"lis_member_id" => "S309", "first_name" => "Bob", "last_name" => "Casey", "party" => "Democrat", "state" => "PA", "vote" => 1}]
          }
        ]
      }.to_json

      stub_request(:get, "https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00421.xml")
        .to_return(status: 403, body: "<html>Challenge</html>")
      stub_request(:get, "https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00422.xml")
        .to_return(status: 403, body: "<html>Challenge</html>")

      index_stub = stub_request(:get, "https://voteview.com/static/data/out/rollcalls/S119_rollcalls.json")
        .to_return(status: 200, body: raw_index.to_json)

      stub_request(:get, "https://voteview.com/api/download?rollcall_id=RS1190421")
        .to_return(status: 200, body: voteview_download_421)
      stub_request(:get, "https://voteview.com/api/download?rollcall_id=RS1190422")
        .to_return(status: 200, body: voteview_download_422)

      scraper1 = described_class.new(year: 2025, roll_call_number: 421)
      scraper2 = described_class.new(year: 2025, roll_call_number: 422)

      expect(scraper1.process.size).to eq(1)
      expect(scraper2.process.size).to eq(1)

      expect(index_stub).to have_been_requested.once

      cached_entry = Rails.cache.read("voteview/senate_rollcalls/119")
      expect(cached_entry).to be_a(Hash)
      expect(cached_entry[:data]).to eq([
        {"session" => 1, "clerk_rollnumber" => 421, "rollnumber" => 421},
        {"session" => 1, "clerk_rollnumber" => 422, "rollnumber" => 422}
      ])
    end

    it "does not cache non-200 index responses" do
      stub_request(:get, "https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00421.xml")
        .to_return(status: 403, body: "<html>Challenge</html>")

      stub_request(:get, "https://voteview.com/static/data/out/rollcalls/S119_rollcalls.json")
        .to_return(status: 503, body: "Service Unavailable")

      scraper = described_class.new(year: 2025, roll_call_number: 421)
      expect { scraper.process }.to raise_error(Scraper::Congress::RollCallUnavailable)

      expect(Rails.cache.exist?("voteview/senate_rollcalls/119")).to be false
    end

    it "does not re-fetch index when missing roll call was fetched within 15 minutes, but re-fetches after 15 minutes" do
      raw_index = [
        {"session" => 1, "clerk_rollnumber" => 421, "rollnumber" => 421, "extra_field" => "ignore"},
        {"session" => 1, "clerk_rollnumber" => 422, "rollnumber" => 422, "extra_field" => "ignore"}
      ]
      voteview_download_421 = {
        "rollcalls" => [
          {
            "bill_number" => "S. 870",
            "question" => "On the Motion",
            "date" => "2025-06-18",
            "votes" => [{"lis_member_id" => "S309", "first_name" => "Bob", "last_name" => "Casey", "party" => "Democrat", "state" => "PA", "vote" => 1}]
          }
        ]
      }.to_json

      stub_request(:get, "https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00421.xml")
        .to_return(status: 403, body: "<html>Challenge</html>")
      stub_request(:get, "https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00999.xml")
        .to_return(status: 403, body: "<html>Challenge</html>")

      index_stub = stub_request(:get, "https://voteview.com/static/data/out/rollcalls/S119_rollcalls.json")
        .to_return(status: 200, body: raw_index.to_json)

      stub_request(:get, "https://voteview.com/api/download?rollcall_id=RS1190421")
        .to_return(status: 200, body: voteview_download_421)

      initial_time = Time.zone.local(2026, 1, 15, 12, 0, 0)
      travel_to(initial_time) do
        scraper1 = described_class.new(year: 2025, roll_call_number: 421)
        expect(scraper1.process.size).to eq(1)
        expect(index_stub).to have_been_requested.once

        travel 10.minutes
        scraper_miss = described_class.new(year: 2025, roll_call_number: 999)
        expect { scraper_miss.process }.to raise_error(Scraper::Congress::RollCallUnavailable) do |error|
          expect(error.reason).to include("roll_call_not_found_in_voteview_index")
        end
        expect(index_stub).to have_been_requested.once

        travel 6.minutes
        scraper_miss_after_window = described_class.new(year: 2025, roll_call_number: 999)
        expect { scraper_miss_after_window.process }.to raise_error(Scraper::Congress::RollCallUnavailable) do |error|
          expect(error.reason).to include("roll_call_not_found_in_voteview_index")
        end
        expect(index_stub).to have_been_requested.twice
      end
    end
  end

  describe "rescue boundary restrictions" do
    it "propagates NoMethodError raised from Hash.from_xml and never requests voteview.com" do
      stub_request(:get, "https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00421.xml")
        .to_return(status: 200, body: "<valid>xml</valid>")

      allow(Hash).to receive(:from_xml).and_raise(NoMethodError.new("undefined method 'foo'"))

      scraper = described_class.new(year: 2025, roll_call_number: 421)
      expect { scraper.process }.to raise_error(NoMethodError, /undefined method 'foo'/)
      expect(WebMock).not_to have_requested(:get, %r{https://voteview\.com})
    end

    it "falls back to Voteview on malformed XML (REXML::ParseException) on a 200 response" do
      voteview_index = [{"session" => 1, "clerk_rollnumber" => 421, "rollnumber" => 421}].to_json
      voteview_download = {
        "rollcalls" => [
          {
            "bill_number" => "S. 870",
            "question" => "On the Motion",
            "date" => "2025-06-18",
            "votes" => [{"lis_member_id" => "S309", "first_name" => "Bob", "last_name" => "Casey", "party" => "Democrat", "state" => "PA", "vote" => 1}]
          }
        ]
      }.to_json

      stub_request(:get, "https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00421.xml")
        .to_return(status: 200, body: "<unclosed_tag>")

      stub_request(:get, "https://voteview.com/static/data/out/rollcalls/S119_rollcalls.json")
        .to_return(status: 200, body: voteview_index)
      stub_request(:get, "https://voteview.com/api/download?rollcall_id=RS1190421")
        .to_return(status: 200, body: voteview_download)

      scraper = described_class.new(year: 2025, roll_call_number: 421)
      votes = scraper.process

      expect(votes.size).to eq(1)
      expect(votes.first.last_name).to eq("Casey")
    end

    it "falls back to Voteview on senate.gov 504 timeout (Scraper::FaradayConnector::TimeoutError)" do
      voteview_index = [{"session" => 1, "clerk_rollnumber" => 421, "rollnumber" => 421}].to_json
      voteview_download = {
        "rollcalls" => [
          {
            "bill_number" => "S. 870",
            "question" => "On the Motion",
            "date" => "2025-06-18",
            "votes" => [{"lis_member_id" => "S309", "first_name" => "Bob", "last_name" => "Casey", "party" => "Democrat", "state" => "PA", "vote" => 1}]
          }
        ]
      }.to_json

      stub_request(:get, "https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00421.xml")
        .to_return(status: 504, body: "Gateway Timeout")

      stub_request(:get, "https://voteview.com/static/data/out/rollcalls/S119_rollcalls.json")
        .to_return(status: 200, body: voteview_index)
      stub_request(:get, "https://voteview.com/api/download?rollcall_id=RS1190421")
        .to_return(status: 200, body: voteview_download)

      scraper = described_class.new(year: 2025, roll_call_number: 421)
      votes = scraper.process

      expect(votes.size).to eq(1)
      expect(votes.first.last_name).to eq("Casey")
    end

    it "propagates NoMethodError raised inside normalize_voteview_rollcall" do
      voteview_index = [{"session" => 1, "clerk_rollnumber" => 421, "rollnumber" => 421}].to_json
      voteview_download = {
        "rollcalls" => [
          {
            "bill_number" => "S. 870",
            "question" => "On the Motion",
            "date" => "2025-06-18",
            "votes" => [{"lis_member_id" => "S309", "first_name" => "Bob", "last_name" => "Casey", "party" => "Democrat", "state" => "PA", "vote" => 1}]
          }
        ]
      }.to_json

      stub_request(:get, "https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00421.xml")
        .to_return(status: 403, body: "<html>Challenge</html>")

      stub_request(:get, "https://voteview.com/static/data/out/rollcalls/S119_rollcalls.json")
        .to_return(status: 200, body: voteview_index)
      stub_request(:get, "https://voteview.com/api/download?rollcall_id=RS1190421")
        .to_return(status: 200, body: voteview_download)

      scraper = described_class.new(year: 2025, roll_call_number: 421)
      allow(scraper).to receive(:normalize_voteview_rollcall).and_raise(NoMethodError.new("internal error"))

      expect { scraper.process }.to raise_error(NoMethodError, /internal error/)
    end
  end
end
