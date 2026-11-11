# typed: true
# frozen_string_literal: true

require "rails_helper"

CONGRESS = {
  city: "congress",
  state: "congress",
  country: "united_states"
}.freeze

RSpec.describe CongressLegislatorVoteUpdateService do
  include ActiveSupport::Testing::TimeHelpers

  # These tests once relied on DevDataLoader (a full dev DB dump) and live
  # scrapes, both unreliable in CI. They now build only the records needed
  # and fake the Scraper classes.

  let(:sway_locale) do
    SwayLocale.find_by(CONGRESS) ||
      create(
        :sway_locale,
        city: "congress",
        state: "congress",
        country: "united_states"
      )
  end
  # Congress seats are named for the state: "MD0" is Maryland's statewide
  # Senate seat, "MD7" a House district. The Senate publishes the state rather
  # than an id Sway holds, so matching reads this name.
  let(:district) { create(:district, sway_locale: sway_locale, name: "MD0") }

  # @lat: [[congress-roll-calls#Why the test suite fakes the scrapers with an agreeing identity]]
  let(:agreeing_identity) do
    instance_double(
      Scraper::Congress::RollCallIdentity,
      taken_on?: true,
      names?: true,
      document_name: nil,
      question: "On Passage of the Bill",
      title: nil,
      voted_on: Date.new(2024, 6, 18),
      to_h: {}
    )
  end

  before do
    @senate_scraper = instance_double(Scraper::Congress::Senate::LegislatorVotes)
    allow(Scraper::Congress::Senate::LegislatorVotes).to receive(:new).and_return(@senate_scraper)
    allow(@senate_scraper).to receive(:process).and_return([])
    allow(@senate_scraper).to receive(:identity).and_return(agreeing_identity)

    @house_scraper = instance_double(Scraper::Congress::House::LegislatorVotes)
    allow(Scraper::Congress::House::LegislatorVotes).to receive(:new).and_return(@house_scraper)
    allow(@house_scraper).to receive(:process).and_return([])
    allow(@house_scraper).to receive(:identity).and_return(agreeing_identity)
  end

  # Vote#after_create queues LegislatorVoteFetchJob rather than
  # calling this service directly. Run queued jobs immediately so existing
  # assertions still hold.
  around do |ex|
    prev_adapter = ActiveJob::Base.queue_adapter
    begin
      ActiveJob::Base.queue_adapter = :inline
      ex.run
    ensure
      ActiveJob::Base.queue_adapter = prev_adapter
    end
  end

  describe "#run" do
    let(:senate_vote_double) do
      Scraper::LegislatorVote.new(
        external_id: legislator.external_id,
        support: "FOR",
        first_name: legislator.first_name,
        last_name: legislator.last_name,
        party: legislator.party.to_s,
        state_code: "MD"
      )
    end
    let(:vote_record) do
      create(
        :vote,
        bill: bill,
        senate_roll_call_vote_number: "99",
        house_roll_call_vote_number: nil
      )
    end
    # @lat: [[congress-roll-calls#Roll-call numbering restarts every year]]
    let(:bill) do
      create(
        :bill,
        sway_locale: sway_locale,
        legislator: legislator,
        external_id: "s99",
        house_vote_date_time_utc: Time.utc(2024, 5, 23),
        senate_vote_date_time_utc: Time.utc(2024, 6, 18)
      )
    end
    # -----------------------------------------------------------------------
    # Later-added behaviours
    # -----------------------------------------------------------------------

    # Shared bill and legislator setup for the contexts below.
    # They all use the congress sway_locale set up above.
    let(:legislator) do
      create(
        :legislator,
        district: district,
        title: "Sen.",
        external_id: "V000128",
        first_name: "Chris",
        last_name: "Van Hollen",
        party: "D"
      ).tap do |l|
        # Two terms, because this bill was voted on in 2024 and the roll call
        # is matched against whoever held the seat THAT day, not today. The
        # 2025 term is the one running now; the 2023 one covers the votes.
        create(:legislator_term, legislator: l, district: district, title: "Sen.")
        create(:legislator_term, :prior_term, legislator: l, district: district, title: "Sen.")
      end
    end

    # @lat: [[congress-roll-calls#Roll-call numbering restarts every year]]
    describe "fetch year" do
      it "hands each scraper the year of that chamber's vote, whatever year it is now" do
        vote_record # senate roll-call number 99; bill's senate vote is 2024-06-18
        travel_to(Time.zone.local(2026, 7, 24)) do
          described_class.new(bill.id).call
        end
        # Twice is expected: Vote#after_create ran the service once already,
        # inline, at creation. Both calls must carry the vote's year.
        expect(Scraper::Congress::Senate::LegislatorVotes)
          .to have_received(:new).with(year: 2024, roll_call_number: 99).at_least(:once)
      end

      # @lat: [[congress-roll-calls#Why a fetched record has to name the bill's own vote]]
      it "hands the House scraper the House vote's year and roll number" do
        create(:vote, bill: bill, house_roll_call_vote_number: "232", senate_roll_call_vote_number: nil)
        travel_to(Time.zone.local(2026, 7, 24)) do
          described_class.new(bill.id).call
        end
        expect(Scraper::Congress::House::LegislatorVotes)
          .to have_received(:new).with(roll_call_number: 232, year: 2024).at_least(:once)
      end

      it "skips a chamber whose roll number has no vote date instead of guessing the year" do
        dateless_bill = create(
          :bill,
          sway_locale: sway_locale,
          legislator: legislator,
          external_id: "s100",
          scheduled_release_date_utc: 6.days.ago.to_date
        )
        create(:vote, bill: dateless_bill, senate_roll_call_vote_number: "7", house_roll_call_vote_number: nil)

        described_class.new(dateless_bill.id).call

        expect(Scraper::Congress::Senate::LegislatorVotes).not_to have_received(:new)
      end
    end

    # @lat: [[congress-roll-calls#Why a fetched record has to name the bill's own vote]]
    describe "the record has to be the bill's own vote" do
      let(:voter) do
        Scraper::LegislatorVote.new(
          external_id: legislator.external_id,
          support: "FOR",
          first_name: legislator.first_name,
          last_name: legislator.last_name,
          party: legislator.party.to_s,
          state_code: "MD"
        )
      end

      let(:other_day) do
        Scraper::Congress::RollCallIdentity.new(
          document_name: "S. 870",
          question: "On the Motion",
          title: "Motion to Concur in the House Amendments to S. 870",
          voted_on: Date.new(2026, 6, 18)
        )
      end

      before do
        allow(@senate_scraper).to receive(:process).and_return([voter])
        legislator
      end

      # Vote#after_create runs the service inline, so the number is recorded
      # while the record still agrees. The disagreement then stands for a later
      # re-fetch, which is when this really happens.
      before do
        create(:vote, bill: bill, senate_roll_call_vote_number: "200", house_roll_call_vote_number: nil)
      end

      it "refuses a record taken on a different day" do
        allow(@senate_scraper).to receive(:identity).and_return(other_day)

        expect { described_class.new(bill.id).call }
          .to raise_error(Scraper::Congress::RollCallMismatch, /2026-06-18.*2024-06-18/m)
      end

      it "writes nothing when it refuses" do
        allow(@senate_scraper).to receive(:identity).and_return(other_day)
        LegislatorVote.where(bill: bill).delete_all

        expect {
          begin
            described_class.new(bill.id).call
          rescue Scraper::Congress::RollCallMismatch
            nil
          end
        }.not_to change(LegislatorVote.where(bill: bill), :count)
      end

      # A bill can pass folded into another. Bill s1111 really is roll call 200
      # of 2024, and that record names S. 870 — so a different name is recorded,
      # never refused.
      it "records the votes when the day agrees but the record names another bill" do
        same_day = Scraper::Congress::RollCallIdentity.new(
          document_name: "S. 870",
          question: "On the Motion",
          title: "Motion to Concur in the House Amendments to S. 870",
          voted_on: Date.new(2024, 6, 18)
        )
        allow(@senate_scraper).to receive(:identity).and_return(same_day)
        allow(SwayLogging).to receive(:warn)
        LegislatorVote.where(bill: bill).delete_all

        described_class.new(bill.id).call

        expect(LegislatorVote.where(bill: bill, legislator: legislator)).to exist
        expect(SwayLogging).to have_received(:warn)
          .with("congress_legislator_votes.record_names_another_document", hash_including(document_name: "S. 870"))
          .at_least(:once)
      end
    end

    # @lat: [[congress-roll-calls#A vote on something else is not a position on the bill]]
    describe "the chamber has to have been asked about the bill" do
      let(:voter) do
        Scraper::LegislatorVote.new(
          external_id: legislator.external_id,
          support: "FOR",
          first_name: legislator.first_name,
          last_name: legislator.last_name,
          party: legislator.party.to_s,
          state_code: "MD"
        )
      end

      def senate_record(question, title = nil)
        Scraper::Congress::RollCallIdentity.new(
          document_name: "s1111",
          question: question,
          title: title,
          voted_on: Date.new(2024, 6, 18)
        )
      end

      before do
        allow(@senate_scraper).to receive(:process).and_return([voter])
        legislator
        # The number is recorded while the record still agrees, the same way
        # the day check is exercised above.
        create(:vote, bill: bill, senate_roll_call_vote_number: "200", house_roll_call_vote_number: nil)
      end

      it "refuses a cloture vote taken on the right day" do
        allow(@senate_scraper).to receive(:identity)
          .and_return(senate_record("On the Cloture Motion", "Motion to Invoke Cloture"))

        expect { described_class.new(bill.id).call }
          .to raise_error(Scraper::Congress::RollCallNotOnTheBill, /cloture.*not a vote on the bill/mi)
      end

      it "writes nothing when it refuses" do
        allow(@senate_scraper).to receive(:identity)
          .and_return(senate_record("On the Cloture Motion", "Motion to Invoke Cloture"))
        LegislatorVote.where(bill: bill).delete_all

        expect {
          begin
            described_class.new(bill.id).call
          rescue Scraper::Congress::RollCallNotOnTheBill
            nil
          end
        }.not_to change(LegislatorVote.where(bill: bill), :count)
      end

      it "says so when the question is one Sway has never seen" do
        allow(@senate_scraper).to receive(:identity).and_return(senate_record("On Something New"))

        expect { described_class.new(bill.id).call }
          .to raise_error(Scraper::Congress::RollCallNotOnTheBill, /does not know/)
      end

      it "records the votes when the chamber was asked to pass the bill" do
        allow(@senate_scraper).to receive(:identity).and_return(senate_record("On Passage of the Bill"))
        LegislatorVote.where(bill: bill).delete_all

        described_class.new(bill.id).call

        expect(LegislatorVote.where(bill: bill, legislator: legislator)).to exist
      end

      it "refreshes house votes even when the senate roll call is refused" do
        senate_district = create(:district, sway_locale: sway_locale, name: "MD0")
        house_district = create(:district, sway_locale: sway_locale, name: "MD7")

        senator_record = create(
          :legislator,
          district: senate_district,
          external_id: "S000001",
          first_name: "Benjamin",
          last_name: "Cardin",
          party: "D"
        ).tap do |leg|
          create(:legislator_term, :prior_term, legislator: leg, district: senate_district, title: "Sen.")
        end

        rep_record = create(
          :legislator,
          district: house_district,
          external_id: "H000001",
          first_name: "Kweisi",
          last_name: "Mfume",
          party: "D"
        ).tap do |leg|
          create(:legislator_term, :prior_term, legislator: leg, district: house_district, title: "Rep.")
        end

        senate_voter = Scraper::LegislatorVote.new(
          external_id: senator_record.external_id,
          support: "FOR",
          first_name: senator_record.first_name,
          last_name: senator_record.last_name,
          party: senator_record.party.to_s,
          state_code: "MD"
        )
        house_voter = Scraper::LegislatorVote.new(
          external_id: rep_record.external_id,
          support: "FOR",
          first_name: rep_record.first_name,
          last_name: rep_record.last_name,
          party: rep_record.party.to_s,
          state_code: "MD"
        )

        test_bill = create(
          :bill,
          sway_locale: sway_locale,
          legislator: rep_record,
          external_id: "hr1234",
          senate_vote_date_time_utc: Time.utc(2024, 6, 18),
          house_vote_date_time_utc: Time.utc(2024, 6, 18)
        )
        create(
          :vote,
          bill: test_bill,
          senate_roll_call_vote_number: "200",
          house_roll_call_vote_number: "150"
        )

        allow(@senate_scraper).to receive(:process).and_return([senate_voter])
        allow(@senate_scraper).to receive(:identity).and_return(
          Scraper::Congress::RollCallIdentity.new(
            document_name: "s1111",
            question: "On the Cloture Motion",
            title: "Motion to Invoke Cloture",
            voted_on: Date.new(2024, 6, 18)
          )
        )

        allow(@house_scraper).to receive(:process).and_return([house_voter])
        allow(@house_scraper).to receive(:identity).and_return(
          Scraper::Congress::RollCallIdentity.new(
            document_name: "hr1111",
            question: "On Passage of the Bill",
            title: "Passage of the Bill",
            voted_on: Date.new(2024, 6, 18)
          )
        )

        expect { described_class.new(test_bill.id).call }
          .to raise_error(Scraper::Congress::RollCallNotOnTheBill)

        expect(LegislatorVote.where(bill: test_bill, legislator: rep_record)).to exist
        expect(LegislatorVote.where(bill: test_bill, legislator: senator_record)).not_to exist
      end
    end

    # @lat: [[congress-roll-calls#The roster a roll call is matched against is the vote day's]]
    describe "the roster is the vote day's, not today's" do
      let(:departed) do
        create(
          :legislator,
          district: district,
          external_id: "R000600",
          first_name: "Benjamin",
          last_name: "Cardin",
          party: "D"
        ).tap do |person|
          create(:legislator_term, :prior_term, legislator: person, district: district, title: "Sen.")
        end
      end

      def cast(last_name, state_code = "MD")
        Scraper::LegislatorVote.new(
          external_id: "R000600", support: "FOR", first_name: "Ben",
          last_name: last_name, party: "D", state_code: state_code
        )
      end

      before do
        departed
        create(:vote, bill: bill, senate_roll_call_vote_number: "200", house_roll_call_vote_number: nil)
      end

      # Their last term ended in January 2025, so today's roster does not hold
      # them. The Senate prints "Ben" where Sway stores "Benjamin", which is
      # why the given name is not part of the match.
      it "records the vote of a member who has since left" do
        allow(@senate_scraper).to receive(:process).and_return([cast("Cardin")])
        LegislatorVote.where(bill: bill).delete_all

        described_class.new(bill.id).call

        expect(LegislatorVote.where(bill: bill, legislator: departed)).to exist
      end

      it "names the voters it could not match" do
        allow(@senate_scraper).to receive(:process).and_return([cast("Nobody", "CA")])
        allow(SwayLogging).to receive(:warn)

        described_class.new(bill.id).call

        expect(SwayLogging).to have_received(:warn).with(
          "congress_legislator_votes.voters_not_matched",
          hash_including(matched: 0, published: 1, names: ["Nobody (CA)"])
        )
      end

      it "says nothing when every published voter was matched" do
        allow(@senate_scraper).to receive(:process).and_return([cast("Cardin")])
        allow(SwayLogging).to receive(:warn)

        described_class.new(bill.id).call

        expect(SwayLogging).not_to have_received(:warn)
          .with("congress_legislator_votes.voters_not_matched", anything)
      end
    end

    context "a new CONGRESSIONAL Bill is created" do
      it "creates LegislatorVotes for both the house and senate" do
        senator =
          create(
            :legislator,
            district: district,
            title: "Sen.",
            external_id: "V000128",
            first_name: "Chris",
            last_name: "Van Hollen",
            party: "D"
          ).tap { |l| create(:legislator_term, legislator: l, district: district, title: "Sen.") }
        representative =
          create(
            :legislator,
            district: district,
            title: "Rep.",
            external_id: "M000687",
            first_name: "Kweisi",
            last_name: "Mfume",
            party: "D"
          ).tap { |l| create(:legislator_term, legislator: l, district: district, title: "Rep.") }

        allow(@senate_scraper).to receive(:process).and_return(
          [
            Scraper::LegislatorVote.new(
              external_id: "V000128",
              first_name: "Chris",
              last_name: "Van Hollen",
              state_code: "MD",
              party: "D",
              support: LegislatorVote::Support::FOR
            )
          ]
        )
        allow(@house_scraper).to receive(:process).and_return(
          [
            Scraper::LegislatorVote.new(
              external_id: "M000687",
              first_name: "Kweisi",
              last_name: "Mfume",
              state_code: "MD",
              party: "D",
              support: LegislatorVote::Support::AGAINST
            )
          ]
        )

        # Real records rather than fakes, so the day each states is the day the
        # bill records and the roster is built from it. Bill S5's own roll
        # calls: House 23 of 2025 on 22 January, Senate 7 on 20 January.
        allow(@senate_scraper).to receive(:identity).and_return(
          Scraper::Congress::RollCallIdentity.new(
            document_name: "S. 5", question: "On Passage of the Bill", voted_on: Date.new(2025, 1, 20)
          )
        )
        allow(@house_scraper).to receive(:identity).and_return(
          Scraper::Congress::RollCallIdentity.new(
            document_name: "S 5", question: "On Passage", voted_on: Date.new(2025, 1, 22)
          )
        )

        bill =
          create(
            :bill,
            sway_locale: sway_locale,
            legislator: representative,
            external_id: "s5",
            house_vote_date_time_utc: Time.utc(2025, 1, 22),
            senate_vote_date_time_utc: Time.utc(2025, 1, 20)
          )
        create(
          :vote,
          bill: bill,
          house_roll_call_vote_number: "23",
          senate_roll_call_vote_number: "7"
        )

        expect(LegislatorVote.where(legislator: senator).first&.support).to eq(
          LegislatorVote::Support::FOR
        )
        expect(LegislatorVote.where(legislator: representative).first&.support).to eq(
          LegislatorVote::Support::AGAINST
        )
      end

      it "does nothing when the bill's sway_locale is not congress" do
        other_locale =
          create(
            :sway_locale,
            city: "baltimore",
            state: "MD",
            country: "United States"
          )
        other_district = create(:district, sway_locale: other_locale)
        legislator = create(:legislator, district: other_district).tap { |l| create(:legislator_term, legislator: l, district: other_district) }
        bill =
          create(:bill, sway_locale: other_locale, legislator: legislator)
        # Empty the Legistar MatterFile pointer so Vote#after_create's fetch does
        # nothing. update_column writes it while skipping the presence
        # validation and callbacks.
        bill.update_column(:external_id, "")
        vote =
          create(
            :vote,
            bill: bill,
            house_roll_call_vote_number: "1",
            senate_roll_call_vote_number: "1"
          )

        # The locale is not congress, so service#run returns straight away;
        # after_create already routes non-congress locales to the OpenStates
        # service instead.
        expect(Scraper::Congress::Senate::LegislatorVotes).not_to receive(:new)
        expect(Scraper::Congress::House::LegislatorVotes).not_to receive(:new)

        described_class.new(bill.id).call
        expect(vote).to be_persisted
      end
    end

    context "source policy" do
      it "writes new rows with source: 'congress'" do
        allow(@senate_scraper).to receive(:process).and_return([senate_vote_double])
        vote_record  # trigger create → service runs
        row = LegislatorVote.find_by(bill_id: bill.id, legislator_id: legislator.id)
        expect(row&.source).to eq("congress")
        # Real roll-call votes that were fetched are NOT marked inferred.
        expect(row&.inferred).to be(false)
      end

      it "does NOT modify rows where source = 'manual'" do
        create(
          :legislator_vote,
          bill: bill,
          legislator: legislator,
          support: "AGAINST",
          source: "manual"
        )
        allow(@senate_scraper).to receive(:process).and_return([senate_vote_double])
        described_class.new(bill.id).call
        row = LegislatorVote.find_by(bill_id: bill.id, legislator_id: legislator.id)
        expect(row.support).to eq("AGAINST")
        expect(row&.source).to eq("manual")
      end

      it "updates non-manual rows with new support and refreshed source" do
        create(
          :legislator_vote,
          bill: bill,
          legislator: legislator,
          support: "AGAINST",
          source: "congress"
        )
        against_vote = Scraper::LegislatorVote.new(
          external_id: legislator.external_id,
          support: "FOR",
          first_name: legislator.first_name,
          last_name: legislator.last_name,
          party: legislator.party.to_s,
          state_code: "MD"
        )
        allow(@senate_scraper).to receive(:process).and_return([against_vote])
        # The bill needs a senate roll-call number so the SCRAPER path drives
        # the update; without it, this test used to pass only because a
        # made-up FOR overwrote the real row.
        vote_record
        described_class.new(bill.id).call
        row = LegislatorVote.find_by(bill_id: bill.id, legislator_id: legislator.id)
        expect(row.support).to eq("FOR")
        expect(row&.source).to eq("congress")
        expect(row&.inferred).to be(false)
      end
    end

    context "sponsor-inference fallback — gated on UPSTREAM row count" do
      it "creates FOR rows for primary sponsor + cosponsors when scraper returns []" do
        cosponsor_leg = create(:legislator, district: district).tap { |l| create(:legislator_term, :prior_term, legislator: l, district: district) }
        create(:bill_cosponsor, bill: bill, legislator: cosponsor_leg)
        # Scrapers return nothing → upstream_count == 0 → sponsor-inference fires
        vote_record  # trigger create → service runs (scrapers already return [])
        expect(LegislatorVote.where(bill_id: bill.id, support: "FOR").count).to eq(2)
        expect(LegislatorVote.where(bill_id: bill.id).pluck(:source).uniq).to eq(["congress"])
        # Made-up sponsor-FOR rows are marked inferred: true.
        expect(LegislatorVote.where(bill_id: bill.id).pluck(:inferred).uniq).to eq([true])
      end

      it "creates exactly one FOR row when scraper returns [] AND cosponsors empty" do
        # A bill always has a primary sponsor: bills.legislator_id is NOT NULL.
        # So the realistic "nothing gets written" case is an empty scraper
        # result plus no cosponsors.
        bill.bill_cosponsors.destroy_all
        vote_record  # trigger create
        expect(LegislatorVote.where(bill_id: bill.id).count).to eq(1)
        expect(LegislatorVote.where(bill_id: bill.id).pluck(:source).uniq).to eq(["congress"])
      end

      it "does NOT fire sponsor-inference when scraper returned rows but NONE mapped (WR-NEW-05)" do
        # Sponsorship guessing depends on rows returned upstream, not rows
        # written. Data we failed to match locally must NOT trigger a guess —
        # that's a bug worth seeing, not papering over.
        cosponsor_leg = create(:legislator, district: district).tap { |l| create(:legislator_term, :prior_term, legislator: l, district: district) }
        create(:bill_cosponsor, bill: bill, legislator: cosponsor_leg)
        unmapped_vote = Scraper::LegislatorVote.new(
          external_id: "UNMAPPED-99999",
          support: "FOR",
          first_name: "Ghost",
          last_name: "Senator",
          party: "I",
          state_code: "ZZ"
        )
        allow(@senate_scraper).to receive(:process).and_return([unmapped_vote])
        vote_record  # trigger after_create → service runs through production path (Vote#after_create → LegislatorVoteFetchJob)
        # Inference suppressed → no LegislatorVote rows persist for this bill.
        expect(LegislatorVote.where(bill_id: bill.id).count).to eq(0)
      end

      it "does NOT overwrite a REAL roll-call row with synthetic sponsor-FOR when scraper returns [] (CR-02)" do
        # The sponsor already has a REAL recorded AGAINST vote. When the scraper
        # later comes back empty, the guess must never turn that real row into
        # a made-up FOR — real data always wins.
        bill.bill_cosponsors.destroy_all
        create(
          :legislator_vote,
          bill: bill,
          legislator: legislator,
          support: "AGAINST",
          source: "congress",
          inferred: false
        )
        # Scrapers return [] (default stub) → upstream_count == 0 → inference fires.
        vote_record # trigger after_create → service runs
        row = LegislatorVote.find_by(bill_id: bill.id, legislator_id: legislator.id)
        expect(row&.support).to eq("AGAINST")
        expect(row&.inferred).to be(false)
        expect(row&.source).to eq("congress")
      end

      it "DOES demote a prior inferred sponsor-FOR row when a REAL roll-call vote arrives (iter-2 IN-01)" do
        # The guard only blocks an INCOMING guess; a REAL roll-call arriving
        # after must still overwrite a made-up FOR row, or every guessed bill
        # would freeze in its made-up state.
        bill.bill_cosponsors.destroy_all
        create(
          :legislator_vote,
          bill: bill,
          legislator: legislator,
          support: "FOR",
          source: "congress",
          inferred: true
        )
        real_against_vote = Scraper::LegislatorVote.new(
          external_id: legislator.external_id,
          support: "AGAINST",
          first_name: legislator.first_name,
          last_name: legislator.last_name,
          party: legislator.party.to_s,
          state_code: "MD"
        )
        allow(@senate_scraper).to receive(:process).and_return([real_against_vote])
        vote_record # roll-call pointer present → SCRAPER path (real data) drives the write
        row = LegislatorVote.find_by(bill_id: bill.id, legislator_id: legislator.id)
        expect(row&.support).to eq("AGAINST")
        expect(row&.inferred).to be(false)
        expect(row&.source).to eq("congress")
      end

      it "does NOT fire sponsor-inference when upstream returned rows but admin-wins suppressed all writes (WR-NEW-05)" do
        create(
          :legislator_vote,
          bill: bill,
          legislator: legislator,
          support: "AGAINST",
          source: "manual"
        )
        allow(@senate_scraper).to receive(:process).and_return([senate_vote_double])
        bill.bill_cosponsors.destroy_all
        # Writing zero rows used to trigger infer_from_sponsors, replacing the
        # admin row with FOR. The guess now depends on rows from UPSTREAM, not
        # WRITTEN, so the manual row survives.
        expect_any_instance_of(described_class).not_to receive(:infer_from_sponsors)
        expect { vote_record }.not_to raise_error  # trigger after_create → service runs
        expect(LegislatorVote.find_by(bill_id: bill.id, legislator_id: legislator.id)&.source).to eq("manual")
      end

      it "suppresses sponsor-inference when senate is refused and house returns 0 votes" do
        test_bill = create(
          :bill,
          sway_locale: sway_locale,
          legislator: legislator,
          external_id: "s999",
          senate_vote_date_time_utc: Time.utc(2024, 6, 18),
          house_vote_date_time_utc: Time.utc(2024, 6, 18)
        )
        create(
          :vote,
          bill: test_bill,
          senate_roll_call_vote_number: "200",
          house_roll_call_vote_number: "150"
        )
        allow(@senate_scraper).to receive(:identity).and_return(
          Scraper::Congress::RollCallIdentity.new(
            document_name: "s999",
            question: "On the Cloture Motion",
            title: "Motion to Invoke Cloture",
            voted_on: Date.new(2024, 6, 18)
          )
        )
        allow(@house_scraper).to receive(:process).and_return([])
        LegislatorVote.where(bill: test_bill).delete_all

        expect { described_class.new(test_bill.id).call }
          .to raise_error(Scraper::Congress::RollCallNotOnTheBill)
        expect(LegislatorVote.where(bill: test_bill)).not_to exist
      end

      it "suppresses sponsor-inference when house is refused and senate returns 0 votes" do
        test_bill = create(
          :bill,
          sway_locale: sway_locale,
          legislator: legislator,
          external_id: "hr999",
          senate_vote_date_time_utc: Time.utc(2024, 6, 18),
          house_vote_date_time_utc: Time.utc(2024, 6, 18)
        )
        create(
          :vote,
          bill: test_bill,
          senate_roll_call_vote_number: "200",
          house_roll_call_vote_number: "150"
        )
        allow(@senate_scraper).to receive(:process).and_return([])
        allow(@house_scraper).to receive(:identity).and_return(
          Scraper::Congress::RollCallIdentity.new(
            document_name: "hr999",
            question: "On Motion to Table",
            title: "Table the Measure",
            voted_on: Date.new(2024, 6, 18)
          )
        )
        LegislatorVote.where(bill: test_bill).delete_all

        expect { described_class.new(test_bill.id).call }
          .to raise_error(Scraper::Congress::RollCallNotOnTheBill)
        expect(LegislatorVote.where(bill: test_bill)).not_to exist
      end
    end

    context "exception handling (HIGH-3)" do
      it "RE-RAISES upstream/transport errors so the job-layer retry_on fires" do
        # Create the vote first, while the fake scraper still returns [], so the
        # bill has a valid Vote record. Then change the fake to raise on the
        # next call.
        create(:vote, bill: bill,
          senate_roll_call_vote_number: "7",
          house_roll_call_vote_number: nil)
        allow(@senate_scraper).to receive(:process)
          .and_raise(StandardError.new("senate.gov 503"))
        expect {
          described_class.new(bill.id).call
        }.to raise_error(StandardError, /senate.gov 503/)
      end

      it "skips a row on ActiveRecord::RecordInvalid and continues the batch" do
        # Two votes for the same legislator. The first has an invalid support
        # value, which raises RecordInvalid; the second is fine. The service
        # must not raise, and Sentry must record the failed row.
        invalid_vote = Scraper::LegislatorVote.new(
          external_id: legislator.external_id,
          support: "INVALID_VALUE",
          first_name: legislator.first_name,
          last_name: legislator.last_name,
          party: legislator.party.to_s,
          state_code: "MD"
        )
        valid_vote = Scraper::LegislatorVote.new(
          external_id: legislator.external_id,
          support: "FOR",
          first_name: legislator.first_name,
          last_name: legislator.last_name,
          party: legislator.party.to_s,
          state_code: "MD"
        )
        # Create the vote first, while the fakes still return nothing, then
        # change what they return.
        create(:vote, bill: bill,
          senate_roll_call_vote_number: "7",
          house_roll_call_vote_number: nil)
        allow(@senate_scraper).to receive(:process)
          .and_return([invalid_vote, valid_vote])
        # @lat: [[error-reporting-in-tests#Why Sentry's methods are watched rather than the constant replaced]]
        allow(Sentry).to receive(:capture_exception)
        # The batch completes without raising; Sentry captured the invalid row.
        expect { described_class.new(bill.id).call }.not_to raise_error
        expect(Sentry).to have_received(:capture_exception).at_least(:once)
      end

      it "lets senate Faraday::TimeoutError take precedence over house refusals" do
        test_bill = create(
          :bill,
          sway_locale: sway_locale,
          legislator: legislator,
          external_id: "s1001",
          senate_vote_date_time_utc: Time.utc(2024, 6, 18),
          house_vote_date_time_utc: Time.utc(2024, 6, 18)
        )
        create(:vote, bill: test_bill, senate_roll_call_vote_number: "10", house_roll_call_vote_number: "20")
        allow(@senate_scraper).to receive(:process).and_raise(Faraday::TimeoutError.new("Senate timeout"))
        allow(@house_scraper).to receive(:identity).and_return(
          Scraper::Congress::RollCallIdentity.new(
            document_name: "hr1001", question: "On Motion to Table", voted_on: Date.new(2024, 6, 18)
          )
        )

        expect { described_class.new(test_bill.id).call }
          .to raise_error(Faraday::TimeoutError, /Senate timeout/)
      end

      it "lets house Faraday::TimeoutError take precedence over senate refusals" do
        test_bill = create(
          :bill,
          sway_locale: sway_locale,
          legislator: legislator,
          external_id: "s1002",
          senate_vote_date_time_utc: Time.utc(2024, 6, 18),
          house_vote_date_time_utc: Time.utc(2024, 6, 18)
        )
        create(:vote, bill: test_bill, senate_roll_call_vote_number: "10", house_roll_call_vote_number: "20")
        allow(@senate_scraper).to receive(:identity).and_return(
          Scraper::Congress::RollCallIdentity.new(
            document_name: "s1002", question: "On the Cloture Motion", voted_on: Date.new(2024, 6, 18)
          )
        )
        allow(@house_scraper).to receive(:process).and_raise(Faraday::TimeoutError.new("House timeout"))

        expect { described_class.new(test_bill.id).call }
          .to raise_error(Faraday::TimeoutError, /House timeout/)
      end

      it "lets Faraday::Error take precedence over RollCallMismatch" do
        test_bill = create(
          :bill,
          sway_locale: sway_locale,
          legislator: legislator,
          external_id: "s1003",
          senate_vote_date_time_utc: Time.utc(2024, 6, 18),
          house_vote_date_time_utc: Time.utc(2024, 6, 18)
        )
        create(:vote, bill: test_bill, senate_roll_call_vote_number: "10", house_roll_call_vote_number: "20")
        allow(@senate_scraper).to receive(:identity).and_return(
          Scraper::Congress::RollCallIdentity.new(
            document_name: "s1003", question: "On Passage of the Bill", voted_on: Date.new(2023, 1, 1)
          )
        )
        allow(@house_scraper).to receive(:process).and_raise(Faraday::ConnectionFailed.new("House connect failed"))

        expect { described_class.new(test_bill.id).call }
          .to raise_error(Faraday::ConnectionFailed, /House connect failed/)
      end

      it "logs secondary chamber errors when both chambers fail and a transport error is raised" do
        test_bill = create(
          :bill,
          sway_locale: sway_locale,
          legislator: legislator,
          external_id: "s1004",
          senate_vote_date_time_utc: Time.utc(2024, 6, 18),
          house_vote_date_time_utc: Time.utc(2024, 6, 18)
        )
        create(:vote, bill: test_bill, senate_roll_call_vote_number: "10", house_roll_call_vote_number: "20")
        allow(@senate_scraper).to receive(:process).and_raise(Faraday::TimeoutError.new("Senate timeout"))
        allow(@house_scraper).to receive(:process).and_raise(Faraday::ConnectionFailed.new("House connection refused"))

        expect(SwayLogging).to receive(:warn).with(
          "congress_legislator_votes.secondary_chamber_error",
          hash_including(
            bill_id: test_bill.id,
            bill_external_id: test_bill.external_id,
            chamber: :house,
            error_class: "Faraday::ConnectionFailed",
            error_message: "House connection refused"
          )
        )

        expect { described_class.new(test_bill.id).call }
          .to raise_error(Faraday::TimeoutError, /Senate timeout/)
      end
    end

    describe ".call" do
      it "accepts a Bill instance directly" do
        allow(@senate_scraper).to receive(:process).and_return([senate_vote_double])
        vote_record

        expect { described_class.call(bill) }.not_to raise_error
        expect(LegislatorVote.find_by(bill_id: bill.id, legislator_id: legislator.id)).to be_present
      end

      it "accepts a bill id integer" do
        allow(@senate_scraper).to receive(:process).and_return([senate_vote_double])
        vote_record

        expect { described_class.call(bill.id) }.not_to raise_error
        expect(LegislatorVote.find_by(bill_id: bill.id, legislator_id: legislator.id)).to be_present
      end
    end

    describe "LegislativeVoteCoverage parity" do
      around do |ex|
        prev_adapter = ActiveJob::Base.queue_adapter
        ActiveJob::Base.queue_adapter = :test
        ex.run
      ensure
        ActiveJob::Base.queue_adapter = prev_adapter
      end

      before do
        @coverage_class = class_double("LegislativeVoteCoverage")
        stub_const("LegislativeVoteCoverage", @coverage_class)
        stub_const(
          "LegislativeVoteCoverage::Status",
          Module.new do
            const_set(:COMPLETE, "complete")
            const_set(:PARTIAL, "partial")
            const_set(:UNRESOLVED, "unresolved")
            const_set(:MISSING_VOTE_DATE, "missing_vote_date")
            const_set(:FETCH_FAILED, "fetch_failed")
          end
        )
      end

      it "records coverage for each chamber when defined" do
        allow(@senate_scraper).to receive(:process).and_return([senate_vote_double])
        create(
          :vote,
          bill: bill,
          senate_roll_call_vote_number: "99",
          house_roll_call_vote_number: nil
        )

        expect(@coverage_class).to receive(:record_coverage!).with(
          bill: bill,
          chamber: "senate",
          roll_call_number: "99",
          eligible_count: 1,
          matched_count: 1,
          unresolved_tokens: [],
          status: "complete"
        )

        described_class.new(bill.id).call
      end

      context "when a matched member has no term covering the bill" do
        let(:seated_after_house_vote) do
          create(
            :legislator,
            district: district,
            external_id: "A000600",
            first_name: "Alex",
            last_name: "Appointee",
            party: "D"
          ).tap do |person|
            create(
              :legislator_term,
              :prior_term,
              legislator: person,
              district: district,
              title: "Sen.",
              began_on: Date.new(2024, 6, 1),
              began_on_source: LegislatorTerm::DateSource::PUBLISHED
            )
          end
        end
        let(:skipped_ballot) do
          Scraper::LegislatorVote.new(
            external_id: seated_after_house_vote.external_id,
            support: "FOR",
            first_name: seated_after_house_vote.first_name,
            last_name: seated_after_house_vote.last_name,
            party: "D",
            state_code: "MD"
          )
        end
        let(:off_topic_senate_record) do
          Scraper::Congress::RollCallIdentity.new(
            document_name: "s99",
            question: "On Motion to Table",
            voted_on: Date.new(2024, 6, 18)
          )
        end
        let(:off_topic_house_record) do
          Scraper::Congress::RollCallIdentity.new(
            document_name: "s99",
            question: "On Motion to Table",
            voted_on: Date.new(2024, 5, 23)
          )
        end

        it "records partial when some senators are skipped" do
          allow(@senate_scraper).to receive(:process).and_return([senate_vote_double, skipped_ballot])
          create(:vote, bill: bill, senate_roll_call_vote_number: "99", house_roll_call_vote_number: nil)

          expect(@coverage_class).to receive(:record_coverage!).with(
            hash_including(chamber: "senate", eligible_count: 2, matched_count: 1, unresolved_tokens: [], status: "partial")
          )

          described_class.new(bill.id).call

          expect(LegislatorVote.where(bill: bill, legislator: seated_after_house_vote)).not_to exist
        end

        it "records unresolved with nothing matched when every senator is skipped" do
          allow(@senate_scraper).to receive(:process).and_return([skipped_ballot])
          create(:vote, bill: bill, senate_roll_call_vote_number: "99", house_roll_call_vote_number: nil)

          expect(@coverage_class).to receive(:record_coverage!).with(
            hash_including(chamber: "senate", eligible_count: 1, matched_count: 0, unresolved_tokens: [], status: "unresolved")
          )

          described_class.new(bill.id).call
        end

        it "records partial when some representatives are skipped" do
          allow(@house_scraper).to receive(:process).and_return([senate_vote_double, skipped_ballot])
          create(:vote, bill: bill, senate_roll_call_vote_number: nil, house_roll_call_vote_number: "20")

          expect(@coverage_class).to receive(:record_coverage!).with(
            hash_including(chamber: "house", eligible_count: 2, matched_count: 1, unresolved_tokens: [], status: "partial")
          )

          described_class.new(bill.id).call
        end

        it "records unresolved with nothing matched when every representative is skipped" do
          allow(@house_scraper).to receive(:process).and_return([skipped_ballot])
          create(:vote, bill: bill, senate_roll_call_vote_number: nil, house_roll_call_vote_number: "20")

          expect(@coverage_class).to receive(:record_coverage!).with(
            hash_including(chamber: "house", eligible_count: 1, matched_count: 0, unresolved_tokens: [], status: "unresolved")
          )

          described_class.new(bill.id).call
        end

        it "does not report a skipped senator as a refreshed vote" do
          allow(@coverage_class).to receive(:record_coverage!)
          allow(@senate_scraper).to receive(:process).and_return([skipped_ballot])
          allow(@house_scraper).to receive(:identity).and_return(off_topic_house_record)
          create(:vote, bill: bill, senate_roll_call_vote_number: "99", house_roll_call_vote_number: "20")

          expect { described_class.new(bill.id).call }
            .to raise_error(Scraper::Congress::RollCallNotOnTheBill, /Senate refreshed: 0 votes/)
        end

        it "does not report a skipped representative as a refreshed vote" do
          allow(@coverage_class).to receive(:record_coverage!)
          allow(@house_scraper).to receive(:process).and_return([skipped_ballot])
          allow(@senate_scraper).to receive(:identity).and_return(off_topic_senate_record)
          create(:vote, bill: bill, senate_roll_call_vote_number: "99", house_roll_call_vote_number: "20")

          expect { described_class.new(bill.id).call }
            .to raise_error(Scraper::Congress::RollCallNotOnTheBill, /House refreshed: 0 votes/)
        end
      end

      context "when the votes are already stored" do
        before do
          allow(@senate_scraper).to receive(:process).and_return([senate_vote_double])
          create(:vote, bill: bill, senate_roll_call_vote_number: "99", house_roll_call_vote_number: nil)
        end

        it "stays complete on a re-fetch that changes nothing" do
          allow(@coverage_class).to receive(:record_coverage!)
          described_class.new(bill.id).call

          expect(@coverage_class).to receive(:record_coverage!).with(
            hash_including(eligible_count: 1, matched_count: 1, status: "complete")
          )

          described_class.new(bill.id).call
        end

        it "counts an admin's manual vote as covered" do
          create(:legislator_vote, :against, bill: bill, legislator: legislator, legislator_term: legislator.terms.find_by(term_start_year: 2023), source: "manual")

          expect(@coverage_class).to receive(:record_coverage!).with(
            hash_including(eligible_count: 1, matched_count: 1, status: "complete")
          )

          described_class.new(bill.id).call

          expect(LegislatorVote.find_by(bill: bill, legislator: legislator).support).to eq(LegislatorVote::Support::AGAINST)
        end

        it "records unresolved when a write fails" do
          allow(LegislatorVote).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique.new("duplicate"))

          expect(@coverage_class).to receive(:record_coverage!).with(
            hash_including(eligible_count: 1, matched_count: 0, status: "unresolved")
          )

          described_class.new(bill.id).call
        end
      end

      it "records fetch_failed status when chamber raises an exception" do
        create(
          :vote,
          bill: bill,
          senate_roll_call_vote_number: "99",
          house_roll_call_vote_number: nil
        )
        allow(@senate_scraper).to receive(:process).and_raise(StandardError.new("upstream down"))

        expect(@coverage_class).to receive(:record_coverage!).with(
          bill: bill,
          chamber: "senate",
          roll_call_number: "99",
          eligible_count: 0,
          matched_count: 0,
          unresolved_tokens: [],
          status: "fetch_failed"
        )

        expect { described_class.new(bill.id).call }.to raise_error(StandardError, /upstream down/)
      end

      it "records missing_vote_date status when vote date is blank" do
        dateless_bill = create(
          :bill,
          sway_locale: sway_locale,
          legislator: legislator,
          external_id: "s100_dateless",
          scheduled_release_date_utc: 6.days.ago.to_date,
          senate_vote_date_time_utc: nil
        )
        create(:vote, bill: dateless_bill, senate_roll_call_vote_number: "77", house_roll_call_vote_number: nil)

        expect(@coverage_class).to receive(:record_coverage!).with(
          bill: dateless_bill,
          chamber: "senate",
          roll_call_number: "77",
          eligible_count: 0,
          matched_count: 0,
          unresolved_tokens: [],
          status: "missing_vote_date"
        )

        described_class.new(dateless_bill.id).call
      end

      it "records upstream eligible_count when roll-call verification refuses the record" do
        create(
          :vote,
          bill: bill,
          senate_roll_call_vote_number: "99",
          house_roll_call_vote_number: nil
        )
        allow(@senate_scraper).to receive(:process).and_return([senate_vote_double])
        allow(@senate_scraper).to receive(:identity).and_return(
          Scraper::Congress::RollCallIdentity.new(
            document_name: "s99",
            question: "On the Cloture Motion",
            title: "Motion to Invoke Cloture",
            voted_on: Date.new(2024, 6, 18)
          )
        )

        expect(@coverage_class).to receive(:record_coverage!).with(
          bill: bill,
          chamber: "senate",
          roll_call_number: "99",
          eligible_count: 1,
          matched_count: 0,
          unresolved_tokens: [],
          status: "fetch_failed"
        )

        expect { described_class.new(bill.id).call }
          .to raise_error(Scraper::Congress::RollCallNotOnTheBill)
      end

      it "records unresolved status when scraper returns zero votes and verification passes" do
        create(
          :vote,
          bill: bill,
          senate_roll_call_vote_number: "99",
          house_roll_call_vote_number: nil
        )
        allow(@senate_scraper).to receive(:process).and_return([])

        expect(@coverage_class).to receive(:record_coverage!).with(
          bill: bill,
          chamber: "senate",
          roll_call_number: "99",
          eligible_count: 0,
          matched_count: 0,
          unresolved_tokens: [],
          status: "unresolved"
        )

        described_class.new(bill.id).call
      end
    end
  end
end
