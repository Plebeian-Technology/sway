# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: legislative_sessions
# Database name: primary
#
#  id             :integer          not null, primary key
#  active         :boolean          default(FALSE), not null
#  end_date       :date             not null
#  name           :string           not null
#  start_date     :date             not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  sway_locale_id :integer          not null
#
# Indexes
#
#  index_legislative_sessions_on_sway_locale_id_and_active  (sway_locale_id,active)
#  index_legislative_sessions_on_sway_locale_id_and_name    (sway_locale_id,name) UNIQUE
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
RSpec.describe LegislativeSession, type: :model do
  let(:sway_locale) { create(:sway_locale, city: "session_spec_city", state: "session_spec_state", country: "United States") }
  let(:district) { create(:district, sway_locale:) }
  let(:session) do
    create(
      :legislative_session,
      sway_locale:,
      start_date: Date.new(2025, 1, 3),
      end_date: Date.new(2027, 1, 3)
    )
  end

  def build_term(began_on:, ended_on:, legislator: nil, term_district: district, term_locale: sway_locale, start_year: 2025)
    create(
      :legislator_term,
      district: term_district,
      legislator: legislator || create(:legislator, sway_locale: term_locale, district: term_district),
      began_on:,
      began_on_source: "published",
      ended_on:,
      ended_on_source: "published",
      term_start_year: start_year,
      term_end_year: start_year + 2
    )
  end

  describe "validations" do
    it "is valid with valid attributes" do
      expect(build(:legislative_session, sway_locale:)).to be_valid
    end

    it "requires a name" do
      session = build(:legislative_session, sway_locale:, name: nil)
      expect(session).not_to be_valid
      expect(session.errors[:name]).to include("can't be blank")
    end

    it "requires a start_date" do
      session = build(:legislative_session, sway_locale:, start_date: nil)
      expect(session).not_to be_valid
      expect(session.errors[:start_date]).to include("can't be blank")
    end

    it "requires an end_date" do
      session = build(:legislative_session, sway_locale:, end_date: nil)
      expect(session).not_to be_valid
      expect(session.errors[:end_date]).to include("can't be blank")
    end

    it "requires a sway_locale" do
      session = build(:legislative_session, sway_locale: nil)
      expect(session).not_to be_valid
      expect(session.errors[:sway_locale]).to be_present
    end

    it "enforces uniqueness of name scoped to sway_locale_id" do
      create(:legislative_session, sway_locale:, name: "119th Congress")
      duplicate = build(:legislative_session, sway_locale:, name: "119th Congress")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("has already been taken")
    end

    it "allows the same name in different locales" do
      other_locale = create(:sway_locale, city: "other_session_city", state: "other_session_state", country: "United States")
      create(:legislative_session, sway_locale:, name: "Shared Session Name")
      other_session = build(:legislative_session, sway_locale: other_locale, name: "Shared Session Name")
      expect(other_session).to be_valid
    end

    describe "date ordering" do
      it "is valid when end_date is after start_date" do
        session = build(:legislative_session, sway_locale:, start_date: Date.new(2025, 1, 3), end_date: Date.new(2027, 1, 3))
        expect(session).to be_valid
      end

      it "is valid when end_date equals start_date (single-day session)" do
        session = build(:legislative_session, sway_locale:, start_date: Date.new(2025, 1, 3), end_date: Date.new(2025, 1, 3))
        expect(session).to be_valid
      end

      it "is invalid when end_date is before start_date" do
        session = build(:legislative_session, sway_locale:, start_date: Date.new(2027, 1, 3), end_date: Date.new(2025, 1, 3))
        expect(session).not_to be_valid
        expect(session.errors[:end_date]).to include("must be on or after start date")
      end
    end

    it "defaults active to false" do
      new_session = LegislativeSession.new
      expect(new_session.active).to be(false)
    end
  end

  describe "associations" do
    it "belongs to sway_locale" do
      expect(session.sway_locale).to eq(sway_locale)
    end

    it "has many bills with dependent: :nullify" do
      bill = create(:bill, sway_locale:, legislative_session: session)
      expect(session.bills).to include(bill)

      session.destroy!
      expect(bill.reload.legislative_session_id).to be_nil
    end
  end

  describe ".containing_date scope" do
    it "filters sessions covering a given date" do
      target_session = create(
        :legislative_session,
        sway_locale:,
        name: "Target Session",
        start_date: Date.new(2025, 1, 3),
        end_date: Date.new(2027, 1, 3)
      )

      expect(described_class.containing_date(Date.new(2026, 1, 1))).to include(target_session)
      expect(described_class.containing_date(Date.new(2025, 1, 3))).to include(target_session)
      expect(described_class.containing_date(Date.new(2027, 1, 3))).to include(target_session)
      expect(described_class.containing_date(Date.new(2025, 1, 2))).not_to include(target_session)
      expect(described_class.containing_date(Date.new(2027, 1, 4))).not_to include(target_session)

      time = Time.zone.parse("2026-06-15 12:00:00")
      expect(described_class.containing_date(time)).to include(target_session)
    end
  end

  describe ".active scope" do
    it "filters sessions that are marked active" do
      active_session = create(
        :legislative_session,
        sway_locale:,
        name: "Active Session",
        active: true
      )
      inactive_session = create(
        :legislative_session,
        sway_locale:,
        name: "Inactive Session",
        active: false
      )

      expect(described_class.active).to include(active_session)
      expect(described_class.active).not_to include(inactive_session)
    end
  end

  describe "#legislator_terms (dynamic date overlap)" do
    it "unscopes the nonexistent legislative_session_id foreign key from queries" do
      expect { session.legislator_terms.to_a }.not_to raise_error
    end

    context "exact boundary cases" do
      it "does not overlap when term begins exactly on the session end date (half-open window)" do
        term = build_term(began_on: Date.new(2027, 1, 3), ended_on: Date.new(2029, 1, 3))
        expect(session.legislator_terms).not_to include(term)
      end

      it "does not overlap when term ends exactly on the session start date (half-open window)" do
        term = build_term(began_on: Date.new(2023, 1, 3), ended_on: Date.new(2025, 1, 3), start_year: 2023)
        expect(session.legislator_terms).not_to include(term)
      end

      it "overlaps when term has nil began_on/ended_on and falls back to TermWindow SQL" do
        congress_locale = create(:sway_locale, :congress)
        congress_district = create(:district, sway_locale: congress_locale)
        congress_session = create(
          :legislative_session,
          sway_locale: congress_locale,
          start_date: Date.new(2025, 1, 3),
          end_date: Date.new(2027, 1, 3)
        )
        term = create(
          :legislator_term,
          district: congress_district,
          legislator: create(:legislator, sway_locale: congress_locale, district: congress_district),
          began_on: nil,
          ended_on: nil,
          term_start_year: 2025,
          term_end_year: 2027
        )
        expect(congress_session.legislator_terms).to include(term)
      end

      it "does not overlap when term ends one day before session start date" do
        term = build_term(began_on: Date.new(2023, 1, 3), ended_on: Date.new(2025, 1, 2), start_year: 2023)
        expect(session.legislator_terms).not_to include(term)
      end

      it "does not overlap when term begins one day after session end date" do
        term = build_term(began_on: Date.new(2027, 1, 4), ended_on: Date.new(2029, 1, 3), start_year: 2027)
        expect(session.legislator_terms).not_to include(term)
      end
    end

    context "spanning and interior cases" do
      it "overlaps when term is completely inside the session" do
        term = build_term(began_on: Date.new(2025, 6, 1), ended_on: Date.new(2026, 6, 1))
        expect(session.legislator_terms).to include(term)
      end

      it "overlaps when term spans across the entire session boundaries (e.g. 6-year Senate term)" do
        term = build_term(began_on: Date.new(2023, 1, 3), ended_on: Date.new(2029, 1, 3), start_year: 2023)
        expect(session.legislator_terms).to include(term)
      end

      it "overlaps when term begins before session and ends during session" do
        term = build_term(began_on: Date.new(2024, 1, 1), ended_on: Date.new(2025, 6, 1), start_year: 2024)
        expect(session.legislator_terms).to include(term)
      end

      it "overlaps when term begins during session and ends after session" do
        term = build_term(began_on: Date.new(2026, 6, 1), ended_on: Date.new(2028, 1, 1), start_year: 2026)
        expect(session.legislator_terms).to include(term)
      end

      it "does not overlap when term is completely before the session" do
        term = build_term(began_on: Date.new(2020, 1, 3), ended_on: Date.new(2022, 1, 3), start_year: 2020)
        expect(session.legislator_terms).not_to include(term)
      end

      it "does not overlap when term is completely after the session" do
        term = build_term(began_on: Date.new(2030, 1, 3), ended_on: Date.new(2032, 1, 3), start_year: 2030)
        expect(session.legislator_terms).not_to include(term)
      end
    end

    it "supports relation chaining such as .where and .count" do
      term1 = build_term(began_on: Date.new(2025, 1, 3), ended_on: Date.new(2027, 1, 3))
      build_term(began_on: Date.new(2020, 1, 3), ended_on: Date.new(2022, 1, 3), start_year: 2020)

      expect(session.legislator_terms.where(id: term1.id).count).to eq(1)
    end

    context "multi-locale isolation" do
      let(:other_locale) { create(:sway_locale, city: "other_locale_city", state: "other_locale_state", country: "United States") }
      let(:other_district) { create(:district, sway_locale: other_locale) }

      it "excludes terms from another locale with identical overlapping dates" do
        local_term = build_term(began_on: Date.new(2025, 1, 3), ended_on: Date.new(2027, 1, 3))
        other_term = build_term(
          began_on: Date.new(2025, 1, 3),
          ended_on: Date.new(2027, 1, 3),
          term_district: other_district,
          term_locale: other_locale
        )

        expect(session.legislator_terms).to include(local_term)
        expect(session.legislator_terms).not_to include(other_term)
        expect(session.legislator_terms.where(district: other_district)).to be_empty
      end

      it "returns an empty relation when session locale has no terms but another locale has overlapping terms" do
        build_term(
          began_on: Date.new(2025, 1, 3),
          ended_on: Date.new(2027, 1, 3),
          term_district: other_district,
          term_locale: other_locale
        )

        expect(session.legislator_terms).to be_empty
      end

      it "isolates terms bidirectionally across concurrent sessions in different locales" do
        other_session = create(
          :legislative_session,
          sway_locale: other_locale,
          start_date: Date.new(2025, 1, 3),
          end_date: Date.new(2027, 1, 3)
        )
        local_term = build_term(began_on: Date.new(2025, 1, 3), ended_on: Date.new(2027, 1, 3))
        other_term = build_term(
          began_on: Date.new(2025, 1, 3),
          ended_on: Date.new(2027, 1, 3),
          term_district: other_district,
          term_locale: other_locale
        )

        expect(session.legislator_terms).to contain_exactly(local_term)
        expect(other_session.legislator_terms).to contain_exactly(other_term)
      end
    end
  end

  describe "#legislators (through: :legislator_terms)" do
    it "returns legislators associated with overlapping terms" do
      legislator = create(:legislator, sway_locale:)
      build_term(began_on: Date.new(2025, 1, 3), ended_on: Date.new(2027, 1, 3), legislator:)

      expect(session.legislators).to include(legislator)
    end

    it "excludes legislators whose terms do not overlap" do
      outside_legislator = create(:legislator, sway_locale:)
      build_term(began_on: Date.new(2020, 1, 3), ended_on: Date.new(2022, 1, 3), legislator: outside_legislator, start_year: 2020)

      expect(session.legislators).not_to include(outside_legislator)
    end

    it "returns distinct legislators when a legislator has multiple overlapping terms" do
      legislator = create(:legislator, sway_locale:)
      build_term(began_on: Date.new(2023, 1, 3), ended_on: Date.new(2025, 6, 1), legislator:, start_year: 2023)
      build_term(began_on: Date.new(2025, 6, 1), ended_on: Date.new(2027, 1, 3), legislator:, start_year: 2025)

      terms = session.legislator_terms.where(legislator:)
      expect(terms.count).to eq(2)

      matching_legislators = session.legislators.where(id: legislator.id)
      expect(matching_legislators.to_a.size).to eq(1)
    end

    context "multi-locale isolation" do
      let(:other_locale) { create(:sway_locale, city: "other_leg_city", state: "other_leg_state", country: "United States") }
      let(:other_district) { create(:district, sway_locale: other_locale) }

      it "excludes legislators from another locale even when their terms have identical dates" do
        local_legislator = create(:legislator, sway_locale:, district:)
        build_term(began_on: Date.new(2025, 1, 3), ended_on: Date.new(2027, 1, 3), legislator: local_legislator)

        other_legislator = create(:legislator, sway_locale: other_locale, district: other_district)
        build_term(
          began_on: Date.new(2025, 1, 3),
          ended_on: Date.new(2027, 1, 3),
          legislator: other_legislator,
          term_district: other_district,
          term_locale: other_locale
        )

        expect(session.legislators).to include(local_legislator)
        expect(session.legislators).not_to include(other_legislator)
        expect(session.legislators.where(sway_locale: other_locale)).to be_empty
      end

      it "returns an empty collection when session locale has no legislators but another locale has active legislators" do
        other_legislator = create(:legislator, sway_locale: other_locale, district: other_district)
        build_term(
          began_on: Date.new(2025, 1, 3),
          ended_on: Date.new(2027, 1, 3),
          legislator: other_legislator,
          term_district: other_district,
          term_locale: other_locale
        )

        expect(session.legislators).to be_empty
      end

      it "isolates legislators bidirectionally across concurrent sessions in different locales" do
        other_session = create(
          :legislative_session,
          sway_locale: other_locale,
          start_date: Date.new(2025, 1, 3),
          end_date: Date.new(2027, 1, 3)
        )
        local_legislator = create(:legislator, sway_locale:, district:)
        build_term(began_on: Date.new(2025, 1, 3), ended_on: Date.new(2027, 1, 3), legislator: local_legislator)

        other_legislator = create(:legislator, sway_locale: other_locale, district: other_district)
        build_term(
          began_on: Date.new(2025, 1, 3),
          ended_on: Date.new(2027, 1, 3),
          legislator: other_legislator,
          term_district: other_district,
          term_locale: other_locale
        )

        expect(session.legislators).to contain_exactly(local_legislator)
        expect(other_session.legislators).to contain_exactly(other_legislator)
      end
    end
  end

  describe "#upstream_name and #definition" do
    let(:maryland_locale) { create(:sway_locale, :maryland) }
    let(:congress_locale) { create(:sway_locale, :congress) }

    it "returns the upstream_name defined in YAML document for matching session" do
      md_session = create(:legislative_session, sway_locale: maryland_locale, name: "2024 Regular Session")
      expect(md_session.definition).to be_present
      expect(md_session.definition.upstream_name).to eq("2024RS")
      expect(md_session.upstream_name).to eq("2024RS")

      congress_session = create(:legislative_session, sway_locale: congress_locale, name: "118th Congress")
      expect(congress_session.definition).to be_present
      expect(congress_session.definition.upstream_name).to eq("118")
      expect(congress_session.upstream_name).to eq("118")
    end

    it "falls back to name when definition is absent" do
      session = create(:legislative_session, sway_locale: maryland_locale, name: "Nonexistent Session")
      expect(session.definition).to be_nil
      expect(session.upstream_name).to eq("Nonexistent Session")
    end

    it "falls back to name when sway_locale is missing or has no name" do
      session = build(:legislative_session, sway_locale: nil, name: "119th Congress")
      expect(session.definition).to be_nil
      expect(session.upstream_name).to eq("119th Congress")

      unnamed_locale = build(:sway_locale, city: "temp", state: "temp", country: "temp")
      allow(unnamed_locale).to receive(:name).and_return(nil)
      session_with_unnamed = build(:legislative_session, sway_locale: unnamed_locale, name: "119th Congress")
      expect(session_with_unnamed.definition).to be_nil
      expect(session_with_unnamed.upstream_name).to eq("119th Congress")
    end
  end
end
