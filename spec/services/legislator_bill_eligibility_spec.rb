# frozen_string_literal: true

require "rails_helper"

RSpec.describe LegislatorBillEligibility do
  let(:congress) { create(:sway_locale, city: "congress", state: "congress", country: "United States") }
  let(:house_district) { create(:district, sway_locale: congress, name: "MD1") }
  let(:senate_district) { create(:district, sway_locale: congress, name: "MD0") }
  let(:house_seat) do
    Seat.find_or_create_by_identity!(
      district: house_district,
      office_identity: "md-house-district-1",
      title: "Rep.",
      chamber: "House of Representatives"
    )
  end
  let(:senate_seat) do
    Seat.find_or_create_by_identity!(
      district: senate_district,
      office_identity: "md-senate-class-1",
      title: "Sen.",
      chamber: "Senate"
    )
  end

  describe ".eligible?" do
    it "returns true when has_recorded_vote is true even outside the legislator's term and chamber" do
      legislator = create(:legislator, sway_locale: congress, district: house_district)
      create(
        :legislator_term,
        legislator:,
        district: house_district,
        seat: house_seat,
        title: "Rep.",
        term_start_year: 2025,
        term_end_year: 2027
      )
      out_of_term_senate_bill = build(
        :bill,
        sway_locale: congress,
        legislator:,
        chamber: "senate",
        scheduled_release_date_utc: Date.new(2021, 5, 1),
        senate_vote_date_time_utc: Time.utc(2021, 5, 1, 12, 0, 0)
      )

      expect(
        described_class.eligible?(legislator:, bill: out_of_term_senate_bill, has_recorded_vote: false)
      ).to be(false)
      expect(
        described_class.eligible?(legislator:, bill: out_of_term_senate_bill, has_recorded_vote: true)
      ).to be(true)
    end

    it "enforces TermWindow half-open interval [begins_on, ends_on) boundaries" do
      legislator = create(:legislator, sway_locale: congress, district: house_district)
      create(
        :legislator_term,
        legislator:,
        district: house_district,
        seat: house_seat,
        title: "Rep.",
        term_start_year: 2023,
        term_end_year: 2025
      )
      legislator.reload

      day_before_start = build(
        :bill,
        sway_locale: congress,
        legislator:,
        chamber: "house",
        scheduled_release_date_utc: Date.new(2023, 1, 2),
        house_vote_date_time_utc: Time.utc(2023, 1, 2, 12, 0, 0)
      )
      exact_start = build(
        :bill,
        sway_locale: congress,
        legislator:,
        chamber: "house",
        scheduled_release_date_utc: Date.new(2023, 1, 3),
        house_vote_date_time_utc: Time.utc(2023, 1, 3, 12, 0, 0)
      )
      day_before_end = build(
        :bill,
        sway_locale: congress,
        legislator:,
        chamber: "house",
        scheduled_release_date_utc: Date.new(2025, 1, 2),
        house_vote_date_time_utc: Time.utc(2025, 1, 2, 12, 0, 0)
      )
      exact_end = build(
        :bill,
        sway_locale: congress,
        legislator:,
        chamber: "house",
        scheduled_release_date_utc: Date.new(2025, 1, 3),
        house_vote_date_time_utc: Time.utc(2025, 1, 3, 12, 0, 0)
      )

      expect(described_class.eligible?(legislator:, bill: day_before_start)).to be(false)
      expect(described_class.eligible?(legislator:, bill: exact_start)).to be(true)
      expect(described_class.eligible?(legislator:, bill: day_before_end)).to be(true)
      expect(described_class.eligible?(legislator:, bill: exact_end)).to be(false)
    end

    it "falls back from chamber vote date to introduced_date_time_utc and then scheduled_release_date_utc" do
      legislator = create(:legislator, sway_locale: congress, district: house_district)
      create(
        :legislator_term,
        legislator:,
        district: house_district,
        seat: house_seat,
        title: "Rep.",
        term_start_year: 2025,
        term_end_year: 2027
      )
      legislator.reload

      out_of_term_intro_with_in_term_release = build(
        :bill,
        sway_locale: congress,
        legislator:,
        chamber: "house",
        introduced_date_time_utc: Time.utc(2024, 11, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2025, 3, 1),
        house_vote_date_time_utc: nil
      )
      in_term_intro_with_later_release = build(
        :bill,
        sway_locale: congress,
        legislator:,
        chamber: "house",
        introduced_date_time_utc: Time.utc(2025, 4, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2028, 3, 1),
        house_vote_date_time_utc: nil
      )
      release_fallback_bill = build(
        :bill,
        sway_locale: congress,
        legislator:,
        chamber: "house",
        introduced_date_time_utc: nil,
        scheduled_release_date_utc: Date.new(2025, 5, 1),
        house_vote_date_time_utc: nil
      )

      expect(described_class.eligible?(legislator:, bill: out_of_term_intro_with_in_term_release)).to be(false)
      expect(described_class.eligible?(legislator:, bill: in_term_intro_with_later_release)).to be(true)
      expect(described_class.eligible?(legislator:, bill: release_fallback_bill)).to be(true)
    end

    it "evaluates origin and crossover chamber vote dates for house, senate, and both bills when a legislator switches from House to Senate across terms" do
      legislator = create(:legislator, sway_locale: congress, district: senate_district)
      create(
        :legislator_term,
        legislator:,
        district: house_district,
        seat: house_seat,
        title: "Rep.",
        term_start_year: 2023,
        term_end_year: 2025
      )
      create(
        :legislator_term,
        legislator:,
        district: senate_district,
        seat: senate_seat,
        title: "Sen.",
        term_start_year: 2025,
        term_end_year: 2031
      )
      legislator.reload

      house_bill_with_2025_senate_crossover = build(
        :bill,
        sway_locale: congress,
        legislator:,
        chamber: "house",
        scheduled_release_date_utc: Date.new(2025, 4, 10),
        house_vote_date_time_utc: Time.utc(2025, 2, 1, 12, 0, 0),
        senate_vote_date_time_utc: Time.utc(2025, 4, 1, 12, 0, 0)
      )
      senate_bill_with_2024_house_crossover = build(
        :bill,
        sway_locale: congress,
        legislator:,
        chamber: "senate",
        scheduled_release_date_utc: Date.new(2024, 6, 10),
        senate_vote_date_time_utc: Time.utc(2024, 5, 1, 12, 0, 0),
        house_vote_date_time_utc: Time.utc(2024, 6, 1, 12, 0, 0)
      )
      both_chamber_bill_in_2026 = build(
        :bill,
        sway_locale: congress,
        legislator:,
        chamber: "both",
        introduced_date_time_utc: Time.utc(2026, 2, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2026, 3, 1)
      )
      house_only_bill_in_2025 = build(
        :bill,
        sway_locale: congress,
        legislator:,
        chamber: "house",
        introduced_date_time_utc: Time.utc(2025, 3, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2025, 3, 15),
        house_vote_date_time_utc: Time.utc(2025, 3, 10, 12, 0, 0),
        senate_vote_date_time_utc: nil
      )
      senate_only_bill_in_2024 = build(
        :bill,
        sway_locale: congress,
        legislator:,
        chamber: "senate",
        introduced_date_time_utc: Time.utc(2024, 3, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2024, 3, 15),
        senate_vote_date_time_utc: Time.utc(2024, 3, 10, 12, 0, 0),
        house_vote_date_time_utc: nil
      )

      expect(described_class.eligible?(legislator:, bill: house_bill_with_2025_senate_crossover)).to be(true)
      expect(described_class.eligible?(legislator:, bill: senate_bill_with_2024_house_crossover)).to be(true)
      expect(described_class.eligible?(legislator:, bill: both_chamber_bill_in_2026)).to be(true)
      expect(described_class.eligible?(legislator:, bill: house_only_bill_in_2025)).to be(false)
      expect(described_class.eligible?(legislator:, bill: senate_only_bill_in_2024)).to be(false)
    end

    it "restricts a 'both'-chamber bill with only a House vote date to House members and excludes Senators" do
      house_member = create(:legislator, sway_locale: congress, district: house_district)
      create(
        :legislator_term,
        legislator: house_member,
        district: house_district,
        seat: house_seat,
        title: "Rep.",
        term_start_year: 2025,
        term_end_year: 2027
      )
      senator = create(:legislator, sway_locale: congress, district: senate_district)
      create(
        :legislator_term,
        legislator: senator,
        district: senate_district,
        seat: senate_seat,
        title: "Sen.",
        term_start_year: 2025,
        term_end_year: 2031
      )
      house_member.reload
      senator.reload

      both_bill_with_only_house_vote = build(
        :bill,
        sway_locale: congress,
        legislator: house_member,
        chamber: "both",
        introduced_date_time_utc: Time.utc(2025, 4, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2025, 5, 1),
        house_vote_date_time_utc: Time.utc(2025, 4, 15, 12, 0, 0),
        senate_vote_date_time_utc: nil
      )

      expect(described_class.eligible?(legislator: house_member, bill: both_bill_with_only_house_vote)).to be(true)
      expect(described_class.eligible?(legislator: senator, bill: both_bill_with_only_house_vote)).to be(false)
    end

    it "resolves term chamber from seat_chambers (including TITLE_ALIASES) when seat is nil or opaque and treats unresolved legislative terms as eligible for any chamber" do
      maryland = create(:sway_locale, city: "maryland", state: "maryland", country: "United States")
      md1 = create(:district, sway_locale: maryland, name: "MD1")
      opaque_seat = Seat.find_or_create_by_identity!(
        district: md1,
        office_identity: "s1",
        title: "T1",
        chamber: "C1"
      )
      legislator = create(:legislator, sway_locale: maryland, district: md1)
      term = create(
        :legislator_term,
        legislator:,
        district: md1,
        seat: opaque_seat,
        title: "State Senator",
        term_start_year: 2023,
        term_end_year: 2027
      )
      legislator.reload

      house_only_bill = build(
        :bill,
        sway_locale: maryland,
        legislator:,
        chamber: "house",
        scheduled_release_date_utc: Date.new(2025, 2, 1),
        house_vote_date_time_utc: Time.utc(2025, 2, 1, 12, 0, 0)
      )
      senate_only_bill = build(
        :bill,
        sway_locale: maryland,
        legislator:,
        chamber: "senate",
        scheduled_release_date_utc: Date.new(2025, 3, 1),
        senate_vote_date_time_utc: Time.utc(2025, 3, 1, 12, 0, 0)
      )

      expect(described_class.eligible?(legislator:, bill: house_only_bill)).to be(false)
      expect(described_class.eligible?(legislator:, bill: senate_only_bill)).to be(true)

      term.update!(title: "State Delegate")
      legislator.reload

      expect(described_class.eligible?(legislator:, bill: house_only_bill)).to be(true)
      expect(described_class.eligible?(legislator:, bill: senate_only_bill)).to be(false)

      term.update!(title: nil)
      legislator.reload

      expect(described_class.eligible?(legislator:, bill: house_only_bill)).to be(true)
      expect(described_class.eligible?(legislator:, bill: senate_only_bill)).to be(true)
    end

    it "qualifies executive terms across Baltimore Mayor, POTUS, and Maryland Governor for in-term bills and recorded votes" do
      baltimore = create(:sway_locale, city: "baltimore", state: "maryland", country: "United States")
      bmore_district = create(:district, sway_locale: baltimore, name: "MD0")
      mayor_seat = Seat.find_or_create_by_identity!(
        district: bmore_district,
        office_identity: "baltimore-mayor",
        title: "Mayor",
        chamber: "Executive"
      )
      mayor = create(:legislator, sway_locale: baltimore, district: bmore_district)
      mayor_term = create(
        :legislator_term,
        legislator: mayor,
        district: bmore_district,
        seat: mayor_seat,
        title: "Mayor",
        term_start_year: 2020,
        term_end_year: 2024
      )
      mayor.reload

      in_term_council_bill = build(
        :bill,
        sway_locale: baltimore,
        legislator: mayor,
        chamber: "council",
        house_vote_date_time_utc: Time.utc(2022, 5, 15, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2022, 6, 1)
      )
      out_of_term_council_bill = build(
        :bill,
        sway_locale: baltimore,
        legislator: mayor,
        chamber: "council",
        house_vote_date_time_utc: Time.utc(2026, 5, 15, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2026, 6, 1)
      )

      expect(described_class.eligible?(legislator: mayor, bill: in_term_council_bill)).to be(true)
      expect(described_class.eligible?(legislator: mayor, bill: out_of_term_council_bill)).to be(false)
      expect(described_class.eligible?(legislator: mayor, bill: out_of_term_council_bill, has_recorded_vote: true)).to be(true)

      begins = TermWindow.begins_on(mayor_term)
      ends = TermWindow.ends_on(mayor_term)
      exact_start_bill = build(
        :bill,
        sway_locale: baltimore,
        legislator: mayor,
        chamber: "council",
        house_vote_date_time_utc: Time.utc(begins.year, begins.month, begins.day, 12, 0, 0),
        scheduled_release_date_utc: begins
      )
      day_before_start = begins - 1.day
      day_before_start_bill = build(
        :bill,
        sway_locale: baltimore,
        legislator: mayor,
        chamber: "council",
        house_vote_date_time_utc: Time.utc(day_before_start.year, day_before_start.month, day_before_start.day, 12, 0, 0),
        scheduled_release_date_utc: day_before_start
      )
      day_before_end = ends - 1.day
      day_before_end_bill = build(
        :bill,
        sway_locale: baltimore,
        legislator: mayor,
        chamber: "council",
        house_vote_date_time_utc: Time.utc(day_before_end.year, day_before_end.month, day_before_end.day, 12, 0, 0),
        scheduled_release_date_utc: day_before_end
      )
      exact_end_bill = build(
        :bill,
        sway_locale: baltimore,
        legislator: mayor,
        chamber: "council",
        house_vote_date_time_utc: Time.utc(ends.year, ends.month, ends.day, 12, 0, 0),
        scheduled_release_date_utc: ends
      )

      expect(described_class.eligible?(legislator: mayor, bill: exact_start_bill)).to be(true)
      expect(described_class.eligible?(legislator: mayor, bill: day_before_start_bill)).to be(false)
      expect(described_class.eligible?(legislator: mayor, bill: day_before_end_bill)).to be(true)
      expect(described_class.eligible?(legislator: mayor, bill: exact_end_bill)).to be(false)

      us0 = create(:district, sway_locale: congress, name: "US0")
      white_house_seat = Seat.find_or_create_by_identity!(
        district: us0,
        office_identity: "us-potus",
        title: CongressChamber::PRESIDENT,
        chamber: CongressChamber::WHITE_HOUSE
      )
      president = create(:legislator, sway_locale: congress, district: us0)
      pres_term = create(
        :legislator_term,
        legislator: president,
        district: us0,
        seat: nil,
        title: CongressChamber::PRESIDENT,
        term_start_year: 2025,
        term_end_year: 2029
      )
      president.reload

      in_term_house_bill = build(
        :bill,
        sway_locale: congress,
        legislator: president,
        chamber: "house",
        introduced_date_time_utc: Time.utc(2026, 1, 15, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2026, 2, 1)
      )
      in_term_senate_bill = build(
        :bill,
        sway_locale: congress,
        legislator: president,
        chamber: "senate",
        introduced_date_time_utc: Time.utc(2026, 3, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2026, 3, 15)
      )
      in_term_both_bill = build(
        :bill,
        sway_locale: congress,
        legislator: president,
        chamber: "both",
        introduced_date_time_utc: Time.utc(2026, 4, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2026, 4, 15)
      )
      out_of_term_congress_bill = build(
        :bill,
        sway_locale: congress,
        legislator: president,
        chamber: "house",
        introduced_date_time_utc: Time.utc(2021, 1, 15, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2021, 2, 1)
      )

      expect(described_class.eligible?(legislator: president, bill: in_term_house_bill)).to be(true)
      expect(described_class.eligible?(legislator: president, bill: in_term_senate_bill)).to be(true)
      expect(described_class.eligible?(legislator: president, bill: in_term_both_bill)).to be(true)
      expect(described_class.eligible?(legislator: president, bill: out_of_term_congress_bill)).to be(false)
      expect(described_class.eligible?(legislator: president, bill: out_of_term_congress_bill, has_recorded_vote: true)).to be(true)

      pres_term.update!(title: "President")
      president.reload

      expect(described_class.eligible?(legislator: president, bill: in_term_house_bill)).to be(true)
      expect(described_class.eligible?(legislator: president, bill: out_of_term_congress_bill)).to be(false)

      pres_term.update!(seat: white_house_seat, title: nil)
      president.reload

      expect(described_class.eligible?(legislator: president, bill: in_term_house_bill)).to be(true)
      expect(described_class.eligible?(legislator: president, bill: out_of_term_congress_bill)).to be(false)

      maryland = create(:sway_locale, city: "maryland", state: "maryland", country: "United States")
      md0 = create(:district, sway_locale: maryland, name: "MD0")
      md_exec = create(:legislator, sway_locale: maryland, district: md0)
      create(
        :legislator_term,
        legislator: md_exec,
        district: md0,
        seat: nil,
        title: "Governor",
        term_start_year: 2023,
        term_end_year: 2027
      )
      md_exec.reload

      in_term_md_house_bill = build(
        :bill,
        sway_locale: maryland,
        legislator: md_exec,
        chamber: "house",
        introduced_date_time_utc: Time.utc(2025, 2, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2025, 3, 1)
      )
      in_term_md_senate_bill = build(
        :bill,
        sway_locale: maryland,
        legislator: md_exec,
        chamber: "senate",
        introduced_date_time_utc: Time.utc(2025, 2, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2025, 3, 1)
      )
      in_term_md_both_bill = build(
        :bill,
        sway_locale: maryland,
        legislator: md_exec,
        chamber: "both",
        introduced_date_time_utc: Time.utc(2025, 2, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2025, 3, 1)
      )
      out_of_term_md_bill = build(
        :bill,
        sway_locale: maryland,
        legislator: md_exec,
        chamber: "house",
        introduced_date_time_utc: Time.utc(2020, 2, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2020, 3, 1)
      )

      expect(described_class.eligible?(legislator: md_exec, bill: in_term_md_house_bill)).to be(true)
      expect(described_class.eligible?(legislator: md_exec, bill: in_term_md_senate_bill)).to be(true)
      expect(described_class.eligible?(legislator: md_exec, bill: in_term_md_both_bill)).to be(true)
      expect(described_class.eligible?(legislator: md_exec, bill: out_of_term_md_bill)).to be(false)
      expect(described_class.eligible?(legislator: md_exec, bill: out_of_term_md_bill, has_recorded_vote: true)).to be(true)
    end

    it "evaluates a career-switcher who served in a legislative chamber and later as an executive" do
      maryland = create(:sway_locale, city: "maryland", state: "maryland", country: "United States")
      md_district = create(:district, sway_locale: maryland, name: "MD1")
      md0 = create(:district, sway_locale: maryland, name: "MD0")
      house_seat = Seat.find_or_create_by_identity!(
        district: md_district,
        office_identity: "md-house-delegate-1",
        title: "Delegate",
        chamber: "House of Delegates"
      )
      gov_seat = Seat.find_or_create_by_identity!(
        district: md0,
        office_identity: "md-governor",
        title: "Governor",
        chamber: "Executive"
      )
      legislator = create(:legislator, sway_locale: maryland, district: md_district)
      create(
        :legislator_term,
        legislator:,
        district: md_district,
        seat: house_seat,
        title: "Delegate",
        term_start_year: 2019,
        term_end_year: 2023
      )
      create(
        :legislator_term,
        legislator:,
        district: md0,
        seat: gov_seat,
        title: "Governor",
        term_start_year: 2023,
        term_end_year: 2027
      )
      legislator.reload

      unvoted_2021_house_bill = build(
        :bill,
        sway_locale: maryland,
        legislator:,
        chamber: "house",
        introduced_date_time_utc: Time.utc(2021, 2, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2021, 3, 1),
        house_vote_date_time_utc: Time.utc(2021, 2, 15, 12, 0, 0),
        senate_vote_date_time_utc: nil
      )
      unvoted_2021_senate_bill = build(
        :bill,
        sway_locale: maryland,
        legislator:,
        chamber: "senate",
        introduced_date_time_utc: Time.utc(2021, 2, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2021, 3, 1),
        senate_vote_date_time_utc: Time.utc(2021, 2, 15, 12, 0, 0),
        house_vote_date_time_utc: nil
      )
      unvoted_2025_house_bill = build(
        :bill,
        sway_locale: maryland,
        legislator:,
        chamber: "house",
        introduced_date_time_utc: Time.utc(2025, 2, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2025, 3, 1),
        house_vote_date_time_utc: Time.utc(2025, 2, 15, 12, 0, 0)
      )
      unvoted_2025_senate_bill = build(
        :bill,
        sway_locale: maryland,
        legislator:,
        chamber: "senate",
        introduced_date_time_utc: Time.utc(2025, 2, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2025, 3, 1),
        senate_vote_date_time_utc: Time.utc(2025, 2, 15, 12, 0, 0)
      )

      expect(described_class.eligible?(legislator:, bill: unvoted_2021_house_bill)).to be(true)
      expect(described_class.eligible?(legislator:, bill: unvoted_2021_senate_bill)).to be(false)
      expect(described_class.eligible?(legislator:, bill: unvoted_2025_house_bill)).to be(true)
      expect(described_class.eligible?(legislator:, bill: unvoted_2025_senate_bill)).to be(true)
    end

    it "evaluates council vote_date_time_utc, unknown chamber fallback, and bills with no dates" do
      legislator = create(:legislator, sway_locale: congress, district: house_district)
      create(
        :legislator_term,
        legislator:,
        district: house_district,
        seat: nil,
        title: nil,
        term_start_year: 2025,
        term_end_year: 2027
      )
      legislator.reload

      council_bill_with_vote_date = build(
        :bill,
        sway_locale: congress,
        legislator:,
        chamber: "council",
        introduced_date_time_utc: Time.utc(2024, 10, 1, 12, 0, 0),
        house_vote_date_time_utc: Time.utc(2025, 3, 15, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2025, 4, 1)
      )
      unrecognized_chamber_bill = build(
        :bill,
        sway_locale: congress,
        legislator:,
        chamber: "joint",
        introduced_date_time_utc: Time.utc(2025, 6, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2025, 7, 1)
      )
      dateless_bill = build(
        :bill,
        sway_locale: congress,
        legislator:,
        chamber: "house",
        introduced_date_time_utc: nil,
        scheduled_release_date_utc: nil,
        house_vote_date_time_utc: nil
      )

      expect(described_class.eligible?(legislator:, bill: council_bill_with_vote_date)).to be(true)
      expect(described_class.eligible?(legislator:, bill: unrecognized_chamber_bill)).to be(true)
      expect(described_class.eligible?(legislator:, bill: dateless_bill)).to be(false)
    end

    it "skips undeclared-locale terms without stored dates and uses stored dates when present" do
      austin = create(:sway_locale, city: "austin", state: "texas", country: "United States")
      district = create(:district, sway_locale: austin, name: "TX1")
      legislator = create(:legislator, sway_locale: austin, district:)
      term = create(
        :legislator_term,
        legislator:,
        district:,
        term_start_year: 2025,
        term_end_year: 2027
      )
      legislator.reload

      in_year_bill = build(
        :bill,
        sway_locale: austin,
        legislator:,
        chamber: "council",
        introduced_date_time_utc: Time.utc(2025, 5, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2025, 6, 1)
      )
      out_of_year_bill = build(
        :bill,
        sway_locale: austin,
        legislator:,
        chamber: "council",
        introduced_date_time_utc: Time.utc(2023, 5, 1, 12, 0, 0),
        scheduled_release_date_utc: Date.new(2023, 6, 1)
      )

      expect(described_class.eligible?(legislator:, bill: in_year_bill)).to be(false)
      expect(described_class.eligible?(legislator:, bill: out_of_year_bill)).to be(false)

      term.update!(
        began_on: Date.new(2025, 1, 1),
        began_on_source: LegislatorTerm::DateSource::OBSERVED,
        ended_on: Date.new(2027, 1, 1),
        ended_on_source: LegislatorTerm::DateSource::OBSERVED
      )
      legislator.reload

      expect(described_class.eligible?(legislator:, bill: in_year_bill)).to be(true)
      expect(described_class.eligible?(legislator:, bill: out_of_year_bill)).to be(false)
    end
  end
end
