# == Schema Information
#
# Table name: legislator_terms
# Database name: primary
#
#  id              :integer          not null, primary key
#  began_on        :date
#  began_on_source :string
#  ended_on        :date
#  ended_on_source :string
#  term_end_year   :integer          not null
#  term_start_year :integer          not null
#  title           :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  district_id     :integer          not null
#  legislator_id   :integer          not null
#  seat_id         :integer
#
# Indexes
#
#  index_legislator_terms_on_district_id                        (district_id)
#  index_legislator_terms_on_legislator_id_and_term_start_year  (legislator_id,term_start_year) UNIQUE
#  index_legislator_terms_on_seat_id                            (seat_id)
#
# Foreign Keys
#
#  district_id    (district_id => districts.id)
#  legislator_id  (legislator_id => legislators.id)
#  seat_id        (seat_id => seats.id)
#
require "rails_helper"

RSpec.describe LegislatorTerm, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:congress_locale) do
    create(:sway_locale, city: "congress", state: "congress", country: "United States")
  end
  let(:congress_district) { create(:district, sway_locale: congress_locale) }
  # The district on the legislator record itself is left over from an older
  # design and has nothing to do with the term's district. A LegislatorTerm gets
  # its locale from district.sway_locale, not from the legislator, so any
  # legislator will do here.
  let(:congress_legislator) { create(:legislator) }

  describe "validations" do
    it "is valid with factory defaults" do
      expect(build(:legislator_term)).to be_valid
    end

    it "fails uniqueness validation on a duplicate (legislator_id, term_start_year)" do
      legislator = create(:legislator)
      create(:legislator_term, legislator:, term_start_year: 2025)
      duplicate = build(:legislator_term, legislator:, term_start_year: 2025)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:term_start_year]).to be_present
    end
  end

  describe ".current" do
    # @lat: [[current-legislator-term#A locale with no declared calendar is skipped, not refused]]
    it "leaves out a term whose locale has no declared calendar, without taking the rest down" do
      travel_to Time.zone.local(2026, 6, 1) do
        declared_term = create(:legislator_term, legislator: congress_legislator, district: congress_district)

        undeclared_locale = create(:sway_locale, city: "austin", state: "TX", country: "United States")
        undeclared_district = create(:district, sway_locale: undeclared_locale, name: "TX1")
        create(:legislator_term, legislator: create(:legislator), district: undeclared_district)

        expect(described_class.current.pluck(:id)).to eq([declared_term.id])
      end
    end

    it "returns only the latest-convened term as of Date.current" do
      travel_to Time.zone.local(2026, 6, 1) do
        term_2023 = create(:legislator_term, :prior_term, legislator: congress_legislator, district: congress_district)
        term_2025 = create(:legislator_term, legislator: congress_legislator, district: congress_district)

        expect(LegislatorTerm.current).to contain_exactly(term_2025)
        expect(term_2025.current?).to be(true)
        expect(term_2023.current?).to be(false)
      end
    end

    # @lat: [[current-legislator-term#Which term a legislator is serving now]]
    it "excludes a legislator whose only term has already ended" do
      travel_to Time.zone.local(2026, 6, 1) do
        ended = create(:legislator_term, :prior_term, legislator: congress_legislator, district: congress_district)

        expect(LegislatorTerm.current).to be_empty
        expect(ended.current?).to be(false)
        expect(congress_legislator.reload.active_term).to be_nil
        expect(Legislator.serving).not_to include(congress_legislator)
      end
    end

    # The Baltimore shape from the production report: a member who left in 2024
    # holds one 2020-2024 term, and the term-year fix alone does not remove
    # them — bounding the window is what does.
    it "excludes a departed Baltimore member holding only their 2020 term" do
      baltimore_locale = create(:sway_locale, city: "baltimore", state: "maryland", country: "United States")
      baltimore_district = create(:district, sway_locale: baltimore_locale)
      departed = create(:legislator)

      travel_to Time.zone.local(2026, 6, 1) do
        create(:legislator_term, legislator: departed, district: baltimore_district,
          term_start_year: 2020, term_end_year: 2024, title: "Council President")

        expect(departed.reload.active_term).to be_nil
        expect(Legislator.serving).not_to include(departed)
      end
    end

    it "keeps a sitting member whose term has begun and not yet ended" do
      travel_to Time.zone.local(2026, 6, 1) do
        serving = create(:legislator_term, legislator: congress_legislator, district: congress_district)

        expect(LegislatorTerm.current).to contain_exactly(serving)
        expect(congress_legislator.reload.active_term).to eq(serving)
      end
    end

    # A senator's term runs six years, not two. Nothing checked end dates
    # before, so a wrong span was invisible; now it decides who is in office.
    it "keeps a senator through the middle of a six-year term" do
      travel_to Time.zone.local(2026, 6, 1) do
        senate_term = create(:legislator_term, legislator: congress_legislator, district: congress_district,
          term_start_year: 2025, term_end_year: 2031, title: "Sen.")

        expect(congress_legislator.reload.active_term).to eq(senate_term)
      end
    end

    it "transitions Congress terms exactly on January 3 handover" do
      prior_term = create(
        :legislator_term,
        legislator: congress_legislator,
        district: congress_district,
        term_start_year: 2023,
        term_end_year: 2025
      )
      new_term = create(
        :legislator_term,
        legislator: congress_legislator,
        district: congress_district,
        term_start_year: 2025,
        term_end_year: 2027
      )

      travel_to Time.zone.local(2025, 1, 2) do
        expect(congress_legislator.reload.active_term).to eq(prior_term)
      end

      travel_to Time.zone.local(2025, 1, 3) do
        expect(congress_legislator.reload.active_term).to eq(new_term)
      end
    end

    it "transitions Maryland terms exactly on the second Wednesday of January" do
      md_locale = create(:sway_locale, :maryland)
      md_district = create(:district, sway_locale: md_locale)
      md_legislator = create(:legislator, sway_locale: md_locale)

      term_2023 = create(
        :legislator_term,
        legislator: md_legislator,
        district: md_district,
        term_start_year: 2023,
        term_end_year: 2027
      )

      # In 2023, the 2nd Wednesday of January was Jan 11.
      travel_to Time.zone.local(2023, 1, 10) do
        expect(md_legislator.reload.active_term).to be_nil
      end

      travel_to Time.zone.local(2023, 1, 11) do
        expect(md_legislator.reload.active_term).to eq(term_2023)
      end

      # In 2027, the 2nd Wednesday of January is Jan 13.
      travel_to Time.zone.local(2027, 1, 12) do
        expect(md_legislator.reload.active_term).to eq(term_2023)
      end

      travel_to Time.zone.local(2027, 1, 13) do
        expect(md_legislator.reload.active_term).to be_nil
      end
    end

    it "transitions Baltimore terms on Thursday after first Monday of December" do
      balt_locale = create(:sway_locale, :baltimore)
      balt_district = create(:district, sway_locale: balt_locale)
      balt_legislator = create(:legislator, sway_locale: balt_locale)

      term_2020 = create(
        :legislator_term,
        legislator: balt_legislator,
        district: balt_district,
        term_start_year: 2020,
        term_end_year: 2024
      )
      term_2024 = create(
        :legislator_term,
        legislator: balt_legislator,
        district: balt_district,
        term_start_year: 2024,
        term_end_year: 2028
      )

      # In 2024, 1st Monday of Dec was Dec 2; Thu after 1st Mon was Dec 5.
      travel_to Time.zone.local(2024, 12, 4) do
        expect(balt_legislator.reload.active_term).to eq(term_2020)
      end

      travel_to Time.zone.local(2024, 12, 5) do
        expect(balt_legislator.reload.active_term).to eq(term_2024)
      end
    end

    it "honours explicit began_on for mid-cycle successors" do
      create(
        :legislator_term,
        legislator: congress_legislator,
        district: congress_district,
        term_start_year: 2025,
        term_end_year: 2027,
        began_on: Date.new(2025, 9, 1),
        began_on_source: LegislatorTerm::DateSource::OBSERVED
      )

      travel_to Time.zone.local(2025, 8, 31) do
        expect(congress_legislator.reload.active_term).to be_nil
      end

      travel_to Time.zone.local(2025, 9, 1) do
        expect(congress_legislator.reload.active_term).to be_present
      end
    end

    it "honours explicit ended_on for mid-term departures" do
      create(
        :legislator_term,
        legislator: congress_legislator,
        district: congress_district,
        term_start_year: 2025,
        term_end_year: 2027,
        ended_on: Date.new(2026, 4, 15),
        ended_on_source: LegislatorTerm::DateSource::PUBLISHED
      )

      travel_to Time.zone.local(2026, 4, 14) do
        expect(congress_legislator.reload.active_term).to be_present
      end

      travel_to Time.zone.local(2026, 4, 15) do
        expect(congress_legislator.reload.active_term).to be_nil
      end
    end

    it "scopes legislator.terms.current to the owner in SQL" do
      other_legislator = create(:legislator)
      other_term = create(:legislator_term, legislator: other_legislator, district: congress_district)
      own_term = create(:legislator_term, legislator: congress_legislator, district: congress_district)

      expect(congress_legislator.terms.current).to contain_exactly(own_term)
      expect(congress_legislator.terms.current).not_to include(other_term)
    end

    it "instantiates only the active term record on single-legislator lookup" do
      create(:legislator_term, legislator: congress_legislator, district: congress_district)

      other_legislator = create(:legislator)
      create(:legislator_term, legislator: other_legislator, district: congress_district)

      instantiations = 0
      subscription = ActiveSupport::Notifications.subscribe("instantiation.active_record") do |*, payload|
        instantiations += payload[:record_count].to_i if payload[:class_name] == "LegislatorTerm"
      end

      congress_legislator.active_term

      ActiveSupport::Notifications.unsubscribe(subscription)
      expect(instantiations).to eq(1)
    end
  end

  describe ".covering" do
    it "attributes a 2024-session vote to the 118th (2023) term" do
      term_2023 = create(:legislator_term, :prior_term, legislator: congress_legislator, district: congress_district)
      create(:legislator_term, legislator: congress_legislator, district: congress_district)

      result = LegislatorTerm.covering(Date.new(2024, 6, 1), legislator: congress_legislator)
      expect(result).to eq(term_2023)
    end

    it "attributes a 2025 vote to the 119th (2025) term" do
      create(:legislator_term, :prior_term, legislator: congress_legislator, district: congress_district)
      term_2025 = create(:legislator_term, legislator: congress_legislator, district: congress_district)

      result = LegislatorTerm.covering(Date.new(2025, 3, 1), legislator: congress_legislator)
      expect(result).to eq(term_2025)
    end

    # @lat: [[current-legislator-term#A date before every term this person served has no term]]
    it "answers nothing for a date before every term this person served" do
      create(:legislator_term, legislator: congress_legislator, district: congress_district)

      result = LegislatorTerm.covering(Date.new(2019, 1, 1), legislator: congress_legislator)

      expect(result).to be_nil
    end

    # A term that records the day it really began is honoured, so a member who
    # arrived partway through a cycle is not attributed the part before them.
    it "answers nothing for a date before a term's observed start" do
      create(
        :legislator_term,
        legislator: congress_legislator,
        district: congress_district,
        term_start_year: 2025,
        term_end_year: 2027,
        began_on: Date.new(2025, 9, 1),
        began_on_source: LegislatorTerm::DateSource::OBSERVED
      )

      expect(LegislatorTerm.covering(Date.new(2025, 3, 1), legislator: congress_legislator)).to be_nil
      expect(LegislatorTerm.covering(Date.new(2025, 10, 1), legislator: congress_legislator)).to be_present
    end

    # A member who left keeps their last term, but not the bills decided after
    # they left. Start-only picking let that term take every later bill.
    it "answers nothing for a date after the person's last term ended" do
      create(
        :legislator_term,
        legislator: congress_legislator,
        district: congress_district,
        term_start_year: 2025,
        term_end_year: 2027,
        ended_on: Date.new(2026, 4, 15),
        ended_on_source: LegislatorTerm::DateSource::PUBLISHED
      )

      expect(LegislatorTerm.covering(Date.new(2026, 3, 1), legislator: congress_legislator)).to be_present
      # The end day itself is the first day out, same as #running_on reads it.
      expect(LegislatorTerm.covering(Date.new(2026, 4, 15), legislator: congress_legislator)).to be_nil
      expect(LegislatorTerm.covering(Date.new(2026, 6, 15), legislator: congress_legislator)).to be_nil
    end

    # Somebody who served, left, and came back held no office in between.
    it "answers nothing inside a gap between two stints" do
      served_2015 = create(
        :legislator_term,
        legislator: congress_legislator,
        district: congress_district,
        term_start_year: 2015,
        term_end_year: 2017
      )
      served_2021 = create(
        :legislator_term,
        legislator: congress_legislator,
        district: congress_district,
        term_start_year: 2021,
        term_end_year: 2023
      )

      expect(LegislatorTerm.covering(Date.new(2016, 6, 1), legislator: congress_legislator)).to eq(served_2015)
      expect(LegislatorTerm.covering(Date.new(2019, 6, 1), legislator: congress_legislator)).to be_nil
      expect(LegislatorTerm.covering(Date.new(2022, 6, 1), legislator: congress_legislator)).to eq(served_2021)
      # After the last term's handover year, with no later term: not in office.
      expect(LegislatorTerm.covering(Date.new(2024, 6, 1), legislator: congress_legislator)).to be_nil
    end

    # A person with no term at all is a mayor or a governor, and callers are
    # meant to skip before asking — so it says so rather than passing quietly.
    it "warns when the person holds no terms at all" do
      allow(SwayLogging).to receive(:warn)

      result = LegislatorTerm.covering(Date.new(2025, 3, 1), legislator: congress_legislator)

      expect(result).to be_nil
      expect(SwayLogging).to have_received(:warn)
        .with("legislator_term.covering.legislator_has_no_terms", hash_including(:legislator_id))
    end
  end

  describe "undeclared locale explicit date COALESCE and .current_for query scaling" do
    it "honors explicit began_on and ended_on dates in SQL when a locale has no convening document" do
      undeclared_locale = create(:sway_locale, city: "undeclared_city", state: "XX", country: "united_states")
      undeclared_district = create(:district, sway_locale: undeclared_locale, name: "XX1")
      legislator = create(:legislator, district: undeclared_district)
      term = create(
        :legislator_term,
        legislator:,
        district: undeclared_district,
        term_start_year: 2025,
        term_end_year: 2027,
        began_on: Date.new(2025, 3, 15),
        began_on_source: LegislatorTerm::DateSource::PUBLISHED,
        ended_on: Date.new(2026, 9, 1),
        ended_on_source: LegislatorTerm::DateSource::PUBLISHED
      )

      expect(described_class.current(Date.new(2025, 2, 1)).where(id: term.id)).to be_empty
      expect(described_class.current(Date.new(2025, 6, 1)).where(id: term.id)).to contain_exactly(term)
      expect(described_class.current(Date.new(2026, 9, 1)).where(id: term.id)).to be_empty
    end

    it "resolves .current_for in a constant number of SQL queries as legislator count grows" do
      count_selects = lambda do |&blk|
        selects = 0
        sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          sql = payload[:sql].to_s
          selects += 1 if payload[:name] != "SCHEMA" && !payload[:cached] && sql.match?(/\A\s*SELECT\b/i)
        end
        begin
          blk.call
        ensure
          ActiveSupport::Notifications.unsubscribe(sub)
        end
        selects
      end

      leg_small = Array.new(2) do
        create(:legislator, district: congress_district).tap do |leg|
          create(:legislator_term, legislator: leg, district: congress_district, term_start_year: 2025, term_end_year: 2027)
        end
      end
      queries_small = count_selects.call do
        described_class.current_for(leg_small.map(&:id)).to_a
      end

      leg_large = Array.new(8) do
        create(:legislator, district: congress_district).tap do |leg|
          create(:legislator_term, legislator: leg, district: congress_district, term_start_year: 2025, term_end_year: 2027)
        end
      end
      queries_large = count_selects.call do
        described_class.current_for((leg_small + leg_large).map(&:id)).to_a
      end

      expect(queries_large).to eq(queries_small)
    end
  end
end
