# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scraper::Maryland::LegislatorVotes do
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
      title: "Senator",
      external_id: "ocd-person/b0d22b6f-68c0-4dd0-892c-7844e6830693",
      first_name: "Bryan",
      last_name: "Simonaire",
      party: "R"
    ).tap { |l| create(:legislator_term, legislator: l, district: district, title: "Senator") }
  end
  let(:bill) do
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      external_id: "hb0504",
      chamber: "senate",
      introduced_date_time_utc: Time.zone.parse("2025-01-01")
    )
  end

  subject(:scraper) { described_class.new(bill: bill, roll_call_number: 1178, roll_call_chamber: "senate") }

  describe "#process (contract)" do
    # @lat: [[maryland-legislator-votes-scraper-spec-design#How the Maryland scraper's PDF read is faked]]
    let(:pdf_page) { instance_double(PDF::Reader::Page, text: "Voting Yea\nSimonaire\n\nVoting Nay\n\nNot Voting\n") }
    let(:pdf_reader) { instance_double(PDF::Reader, pages: [pdf_page]) }

    before do
      # Fake the downloaded stream, standing in for a successful response body
      allow(scraper).to receive(:result).and_return(StringIO.new("fake-pdf"))
      # Make PDF::Reader.new hand back our fake reader instead of parsing a file
      allow(PDF::Reader).to receive(:new).and_return(pdf_reader)
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

    it "only returns FOR or AGAINST (no ABSTAIN)" do
      result = scraper.process
      expect(result.map(&:support)).to all(be_in(%w[FOR AGAINST]))
    end
  end

  describe "matching against the roster of the vote's day" do
    # A senator who left after the vote must still be matchable when the sheet
    # is re-fetched later. Matching against today's roster dropped them.
    let(:pdf_page) { instance_double(PDF::Reader::Page, text: "Voting Yea\nSimonaire\n") }
    let(:pdf_reader) { instance_double(PDF::Reader, pages: [pdf_page]) }

    before do
      legislator.legislator_terms.sole.update!(
        ended_on: Date.new(2026, 6, 1),
        ended_on_source: LegislatorTerm::DateSource::OBSERVED
      )
      bill.update!(senate_vote_date_time_utc: Time.zone.parse("2026-03-10"))
      allow(scraper).to receive(:result).and_return(StringIO.new("fake-pdf"))
      allow(PDF::Reader).to receive(:new).and_return(pdf_reader)
    end

    it "matches a member who has since left, because they served on the vote's day" do
      result = scraper.process

      expect(result.map(&:external_id)).to eq([legislator.external_id])
    end
  end

  describe "#do_request retry pacing (WR-02 regression)" do
    # @lat: [[maryland-legislator-votes-scraper-spec-design#The mutation regression]]
    it "does NOT mutate @bill.introduced_date_time_utc on 404 retry" do
      original_year = bill.introduced_date_time_utc.year
      original_value = bill.introduced_date_time_utc

      # Two 404s in a row: the first request fails, and so does the retry one
      # year further back. The guard then stops retrying because we have walked
      # past the 4-year window.
      call_count = 0
      allow(OpenURI).to receive(:open_uri) do
        call_count += 1
        # @lat: [[maryland-legislator-votes-scraper-spec-design#Why the 404-retry fake wraps a StringIO in OpenURI::Meta]]
        # @type var io: StringIO & OpenURI::Meta
        io = StringIO.new.extend(OpenURI::Meta) #: StringIO & OpenURI::Meta
        raise OpenURI::HTTPError.new("404", io)
      end

      # The bill above is dated 2025, and four years before today is earlier
      # than 2025, so the first 404 causes exactly one retry and the second 404
      # is raised on through.
      expect {
        scraper.send(:do_request)
      }.to raise_error(OpenURI::HTTPError)

      # The bill record must come out unchanged.
      expect(bill.introduced_date_time_utc).to eq(original_value)
      expect(bill.introduced_date_time_utc.year).to eq(original_year)
      expect(bill).not_to be_changed
    end

    it "computes endpoint year from year_offset, not bill mutation" do
      bill.introduced_date_time_utc = Time.zone.parse("2025-03-15")
      expect(scraper.send(:endpoint, 0)).to include("/2025RS/")
      expect(scraper.send(:endpoint, 1)).to include("/2024RS/")
      expect(scraper.send(:endpoint, 2)).to include("/2023RS/")
      # The bill's year is still the same after building earlier-year URLs.
      expect(bill.introduced_date_time_utc.year).to eq(2025)
    end

    it "retries 404 errors outside Rails.env.test? as well" do
      allow(Rails.env).to receive(:test?).and_return(false)
      call_count = 0
      allow(OpenURI).to receive(:open_uri) do
        call_count += 1
        if call_count == 1
          # @type var io: StringIO & OpenURI::Meta
          io = StringIO.new.extend(OpenURI::Meta) #: StringIO & OpenURI::Meta
          raise OpenURI::HTTPError.new("404", io)
        end
        StringIO.new("pdf")
      end

      expect(scraper.send(:do_request)).to be_a(StringIO)
      expect(call_count).to eq(2)
    end

    it "returns nil without raising when introduced_date_time_utc is nil" do
      bill.introduced_date_time_utc = nil
      expect(scraper.send(:do_request)).to be_nil
    end
  end
end
