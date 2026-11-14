# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "legislator")

RSpec.describe SeedLegislator do
  include ActiveSupport::Testing::TimeHelpers

  let(:baltimore) do
    create(:sway_locale, city: "baltimore", state: "maryland", country: "United States")
  end
  let!(:district) { create(:district, sway_locale: baltimore) }

  # Take a legislator out of the real seed file, so the seeder picks the same data
  # preparer it would in production. The first entry is the reference row, looked up
  # later by its own id.
  let(:anchor_entry) do
    path = Rails.root.join("db", "seeds", "data", "united_states", "maryland", "baltimore", "legislators.json")
    JSON.parse(File.read(path)).first
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding#Identity is a table of rows, not one column]]
  def seat_and_name_key(entry)
    identity = LegislatorIdentity.seat_and_name(
      seat: entry.fetch("external_id", entry.fetch("externalId", nil)),
      first_name: entry.fetch("first_name"),
      last_name: entry.fetch("last_name")
    ) #: LegislatorIdentity
    identity.value
  end

  def baltimore_row_for(entry)
    Legislator.find_by(sway_locale: baltimore, external_id: seat_and_name_key(entry))
  end

  # @lat: [[current-legislator-term#Roster identity during seeding]]
  describe "an entry the roster names but cannot put a person in" do
    # Some entries in the committed file carry "external_id", some only
    # "externalId", so both are read here the way the preparer reads them.
    let(:council_president_entry) do
      path = Rails.root.join("db", "seeds", "data", "united_states", "maryland", "baltimore", "legislators.json")
      JSON.parse(File.read(path)).find { |entry|
        (entry["external_id"] || entry["externalId"]) == "baltimore-council-president"
      } #: Hash[String, untyped]
    end

    it "leaves the sitting member in office" do
      described_class.run([baltimore])
      council_president = baltimore_row_for(council_president_entry) #: Legislator
      expect(council_president.reload.serving?).to be(true)

      blanked = JSON.parse(
        Rails.root.join("db", "seeds", "data", "united_states", "maryland", "baltimore", "legislators.json").read
      ).map { |entry|
        next entry unless (entry["external_id"] || entry["externalId"]) == "baltimore-council-president"

        entry.merge("first_name" => "", "last_name" => "")
      }
      allow(described_class).to receive(:read_legislators).and_return(blanked)

      described_class.run([baltimore])

      expect(council_president.reload.serving?).to be(true)
      expect(council_president.legislator_terms.first&.ended_on).to be_nil
      # Their name is not overwritten with the blank either — the other half of
      # the guard, checked here so the pair cannot come apart again.
      expect(council_president.last_name).to eq(council_president_entry.fetch("last_name"))
    end
  end

  describe ".run" do
    it "seeds legislators from the JSON file and stamps last_seeded_at == updated_at for each" do
      expect { described_class.run([baltimore]) }.to change(Legislator, :count)

      Legislator.find_each do |l|
        expect(l.last_seeded_at).not_to be_nil
        expect(l.last_seeded_at).to eq(l.updated_at)
      end
    end

    it "does NOT overwrite an out-of-band-edited legislator on a force: false re-run" do
      SeedLegislator.run([baltimore])
      target = baltimore_row_for(anchor_entry) #: Legislator
      target.update_columns(last_seeded_at: 1.hour.ago)
      frozen_updated_at = target.updated_at

      SeedLegislator.run([baltimore], force: false)

      expect(target.reload.updated_at).to eq(frozen_updated_at)
    end

    # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding]]
    it "still adds a missing term to an out-of-band-edited legislator on a force: false re-run" do
      SeedLegislator.run([baltimore])
      target = baltimore_row_for(anchor_entry) #: Legislator
      target.legislator_terms.destroy_all
      target.update_columns(last_seeded_at: 1.hour.ago)
      frozen_updated_at = target.updated_at

      SeedLegislator.run([baltimore], force: false)

      target.reload
      expect(target.legislator_terms.count).to eq(1)
      # The person row is still protected: the guard did its job.
      expect(target.updated_at).to eq(frozen_updated_at)
    end

    it "overwrites and re-stamps an out-of-band-edited legislator when force: true" do
      SeedLegislator.run([baltimore])
      target = baltimore_row_for(anchor_entry) #: Legislator
      target.update_columns(last_seeded_at: 1.hour.ago)

      SeedLegislator.run([baltimore], force: true)

      target.reload
      expect(target.last_seeded_at).to eq(target.updated_at)
    end

    it "sets sway_locale_id on every seeded legislator" do
      described_class.run([baltimore])

      Legislator.find_each do |l|
        expect(l.sway_locale_id).to eq(baltimore.id)
      end
    end
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding#Identity is a table of rows, not one column]]
  describe "skip guard (identity-key)" do
    let(:anchor_json2) do
      JSON.parse(
        Rails.root.join("db", "seeds", "data", "united_states", "maryland", "baltimore", "legislators.json").read
      ).first
    end

    it "seeds a new record and stamps last_seeded_at == updated_at" do
      SeedLegislator.run([baltimore], force: false)
      persisted = baltimore_row_for(anchor_json2) #: Legislator
      expect(persisted).not_to be_nil
      expect(persisted.last_seeded_at).to eq(persisted.updated_at)
    end

    it "skips a record whose updated_at != last_seeded_at (out-of-band edited)" do
      record = create(:legislator,
        external_id: seat_and_name_key(anchor_json2),
        first_name: anchor_json2.fetch("first_name"),
        last_name: anchor_json2.fetch("last_name"),
        district: district)
      record.update_columns(last_seeded_at: 1.hour.ago)
      original_updated_at = record.updated_at

      SeedLegislator.run([baltimore], force: false)

      expect(record.reload.updated_at).to eq(original_updated_at)
    end

    it "re-seeds and re-stamps when force: true even if edited out-of-band" do
      record = create(:legislator,
        external_id: seat_and_name_key(anchor_json2),
        first_name: anchor_json2.fetch("first_name"),
        last_name: anchor_json2.fetch("last_name"),
        district: district)
      record.update_columns(last_seeded_at: 1.hour.ago)

      SeedLegislator.run([baltimore], force: true)

      record.reload
      expect(record.last_seeded_at).to eq(record.updated_at)
    end
  end

  # @lat: [[seed-legislator-title-tests#Configured roster seat mapping#Defers an overlapping successor seat]]
  describe "(a) a changed name under a published id" do
    it "makes a NEW person when the id names a seat, leaving the previous occupant whole" do
      SeedLegislator.run([baltimore])
      previous_occupant = baltimore_row_for(anchor_entry) #: Legislator
      expect(previous_occupant).not_to be_nil
      previous_term = previous_occupant.legislator_terms.current.sole #: LegislatorTerm
      previous_seat = previous_term.seat
      expect(previous_seat).to have_attributes(seat_identifier: "baltimore-mayor")
      previous_term_before = previous_term.attributes
      previous_interval = [TermWindow.begins_on(previous_term), TermWindow.ends_on(previous_term)]
      bill = create(:bill, sway_locale: baltimore)
      cast_vote = create(:legislator_vote, legislator: previous_occupant, bill: bill)
      cast_vote_before = cast_vote.attributes
      # Counted after the bill, because the bill factory makes its own sponsor.
      original_count = Legislator.count

      successor_json = anchor_entry.merge("first_name" => "Successor", "last_name" => "Arrived")
      expect(SwayLogging).to receive(:warn).with(
        "seed_legislator_terms.configured_seat_overlap",
        hash_including(
          sway_locale: baltimore.name,
          office_identity: "baltimore-mayor",
          conflicting_legislator_id: previous_occupant.id,
          conflicting_term_id: previous_term.id
        )
      )
      SeedLegislator.new(successor_json, baltimore, force: true).seed

      expect(Legislator.count).to eq(original_count + 1)

      previous_occupant.reload
      expect(previous_occupant.full_name).to eq(
        "#{anchor_entry.fetch("first_name")} #{anchor_entry.fetch("last_name")}"
      )
      expect(cast_vote.reload.legislator_id).to eq(previous_occupant.id)

      successor = baltimore_row_for(successor_json) #: Legislator
      expect(successor).not_to be_nil
      expect(successor.id).not_to eq(previous_occupant.id)
      expect(successor.legislator_votes).to be_empty
      successor_term = successor.legislator_terms.current.sole #: LegislatorTerm
      expect(successor_term.seat).to be_nil
      expect([TermWindow.begins_on(successor_term), TermWindow.ends_on(successor_term)])
        .to eq(previous_interval)
      expect(previous_term.reload.attributes).to eq(previous_term_before)
      expect(previous_term.seat).to eq(previous_seat)
      expect(cast_vote.reload.attributes).to eq(cast_vote_before)
    end

    it "updates the row in place when the id names a person" do
      congress = create(:sway_locale, city: "congress", state: "congress", country: "United States")
      create(:district, name: "VA1", sway_locale: congress)
      entry = {
        "bioguideId" => "RENAME001",
        "currentMember" => true,
        "firstName" => "Married",
        "lastName" => "Before",
        "partyName" => "Democratic",
        "state" => "VA",
        "district" => "1",
        "terms" => {"item" => [{"chamber" => "House of Representatives", "startYear" => 2023}]}
      }
      SeedLegislator.new(entry, congress, force: true).seed
      original_count = Legislator.count

      SeedLegislator.new(entry.merge("lastName" => "After"), congress, force: true).seed

      expect(Legislator.count).to eq(original_count)
      target = Legislator.find_by(external_id: "RENAME001", sway_locale: congress) #: Legislator
      expect(target.last_name).to eq("After")
    end
  end

  # ---------------------------------------------------------------------------
  # (b) An external id nobody has seen before, whose data includes term years.
  # ---------------------------------------------------------------------------
  describe "(b) new-member INSERT with term years (H2)" do
    it "creates a new legislator with exactly one LegislatorTerm at the given years" do
      json = {
        "externalId" => "new-member-2024",
        "active" => true,
        "party" => "D",
        "district" => "MD1",
        "regionCode" => "MD",
        "title" => "Council Member",
        "first_name" => "New",
        "last_name" => "Member",
        "zip" => "21201",
        "country" => "united_states",
        "term_start_year" => 2024,
        "term_end_year" => 2028
      }
      expect do
        sl = SeedLegislator.new(json, baltimore, force: true)
        sl.seed
      end.not_to raise_error

      leg = Legislator.find_by(external_id: seat_and_name_key(json)) #: Legislator
      expect(leg).not_to be_nil
      expect(leg.legislator_terms.count).to eq(1)
      term = leg.legislator_terms.first #: LegislatorTerm
      expect(term.term_start_year).to eq(2024)
      expect(term.term_end_year).to eq(2028)
    end
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars#Current roster rows can supply today's term]]
  describe "(b2) new-member INSERT with term keys absent" do
    it "seeds exactly one (current) term even when source blob omits term fields" do
      json = {
        "externalId" => "no-term-member-2024",
        "active" => true,
        "party" => "D",
        "district" => "MD1",
        "regionCode" => "MD",
        "title" => "Council Member",
        "first_name" => "NoTerm",
        "last_name" => "Person",
        "zip" => "21201",
        "country" => "united_states"
        # Left out on purpose: term_start_year, term_end_year, termStartYear, termEndYear
      }
      expect do
        sl = SeedLegislator.new(json, baltimore, force: true)
        sl.seed
      end.not_to raise_error

      leg = Legislator.find_by(external_id: seat_and_name_key(json)) #: Legislator
      expect(leg).not_to be_nil
      expect(leg.legislator_terms.count).to eq(1)
      term = leg.legislator_terms.first #: LegislatorTerm
      expect(term.term_start_year).not_to be_nil
      expect(term.term_end_year).not_to be_nil
    end
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Departure safeguards]]
  describe "(c) partial-roster floor guard (T-65-07-02)" do
    it "logs a warn and skips the reconcile trigger when the fresh roster is implausibly small" do
      SeedLegislator.run([baltimore])
      serving_count = Legislator.where(sway_locale: baltimore).serving.count
      extra_district = District.find_or_create_by!(name: "MD999", sway_locale: baltimore)
      (serving_count * 3).times do |i|
        extra = create(:legislator, external_id: "floor-extra-#{i}", district: extra_district, sway_locale: baltimore)
        create(:legislator_term, legislator: extra, district: extra_district)
      end

      expect(Rails.logger).to receive(:warn).with(/skipping reconcile enqueue/i)
      expect { SeedLegislator.run([baltimore]) }.not_to raise_error
    end

    it "skips the reconcile trigger on an empty fetch against a seeded roster" do
      SeedLegislator.run([baltimore])
      allow(SeedLegislator).to receive(:read_legislators).with(baltimore).and_return([])

      expect(Rails.logger).to receive(:warn).with(/skipping reconcile enqueue/i)
      SeedLegislator.run([baltimore])
    end

    it "does not warn (proceeds normally) when the fresh roster matches the serving roster" do
      SeedLegislator.run([baltimore])

      expect(Rails.logger).not_to receive(:warn)
      SeedLegislator.run([baltimore])
    end
  end

  # ---------------------------------------------------------------------------
  # (c2) The small-roster check counts distinct ids. A fetch that returns the same
  # external id over and over must not look like a large roster.
  # ---------------------------------------------------------------------------
  describe "(c2) G2-WR-03: duplicate ids do not defeat the partial-roster floor" do
    it "skips the reconcile trigger when the UNIQUE roster is tiny even if raw JSON rows are many" do
      SeedLegislator.run([baltimore])
      serving_count = Legislator.where(sway_locale: baltimore).serving.count
      extra_district = District.find_or_create_by!(name: "MD998", sway_locale: baltimore)
      (serving_count * 3).times do |i|
        extra = create(:legislator, external_id: "dup-extra-#{i}", district: extra_district, sway_locale: baltimore)
        create(:legislator_term, legislator: extra, district: extra_district)
      end

      # A broken fetch returns one real member many times over. The raw row count is
      # large, which would fool a check that did not drop duplicates, but there is only
      # one distinct person in there.
      duplicated = Array.new((serving_count + 1) * 4) { anchor_entry }
      allow(SeedLegislator).to receive(:read_legislators).with(baltimore).and_return(duplicated)

      expect(Rails.logger).to receive(:warn).with(/skipping reconcile enqueue/i)
      SeedLegislator.run([baltimore])
    end
  end

  # ---------------------------------------------------------------------------
  # (d) A bad row — one missing a field the database will not allow to be empty — has
  # to raise an error that names the offending external id, never stop quietly.
  # ---------------------------------------------------------------------------
  describe "(d) G2-WR-02: malformed row fails loud with context" do
    it "raises SeedError naming the row" do
      SeedLegislator.run([baltimore])
      sitting = create(:legislator, external_id: "sitting-member", district: district, sway_locale: baltimore)
      create(:legislator_term, legislator: sitting, district: district)

      malformed = anchor_entry.merge("externalId" => "broken-row", "external_id" => "broken-row")
      malformed.delete("party") # party cannot be null; the preparer returns nil -> save! raises
      allow(SeedLegislator).to receive(:read_legislators).with(baltimore).and_return([anchor_entry, malformed])

      expect { SeedLegislator.run([baltimore]) }
        .to raise_error(SeedLegislator::SeedError, /broken-row/)

      expect(Legislator.find_by(external_id: "broken-row")).to be_nil
      expect(sitting.reload).not_to be_nil
    end
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Why a Congress term is rebuilt from published history#A later term does not rewrite an earlier row]]
  describe "(e) R11 append-only: term advance leaves the prior term + its score rows untouched" do
    let(:congress) { create(:sway_locale, city: "congress", state: "congress", country: "United States") }
    let!(:district_congress) { create(:district, name: "VA1", sway_locale: congress) }

    let(:first_run_json) do
      {
        "bioguideId" => "ADV001",
        "firstName" => "Advance",
        "lastName" => "Member",
        "partyName" => "Democrat",
        "state" => "Virginia",
        "currentMember" => true,
        "terms" => {"item" => [{"startYear" => 2023, "endYear" => 2025, "chamber" => "House of Representatives"}]}
      }
    end

    let(:advanced_json) do
      first_run_json.merge(
        "terms" => {
          "item" => [
            {"startYear" => 2023, "endYear" => 2025, "chamber" => "House of Representatives"},
            {"startYear" => 2025, "endYear" => 2027, "chamber" => "House of Representatives"}
          ]
        }
      )
    end

    it "adds a new term row on advance and leaves the prior term + its score rows byte-identical" do
      SeedLegislator.new(first_run_json, congress, force: true).seed
      leg = Legislator.find_by(external_id: "ADV001", sway_locale: congress) #: Legislator
      prior_term = leg.legislator_terms.find_by!(term_start_year: 2023) #: LegislatorTerm

      score = LegislatorDistrictScore.create!(legislator_term: prior_term, count_agreed: 7)
      prior_term_attrs_before = prior_term.reload.attributes
      score_attrs_before = score.reload.attributes

      SeedLegislator.new(advanced_json, congress, force: true).seed

      expect(leg.legislator_terms.count).to eq(2)
      expect(leg.legislator_terms.pluck(:term_start_year)).to contain_exactly(2023, 2025)
      expect(prior_term.reload.attributes).to eq(prior_term_attrs_before)
      expect(score.reload.attributes).to eq(score_attrs_before)
    end
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Why a Congress term is rebuilt from published history#A term keeps its assigned district and seat]]
  describe "(e2) each term keeps the seat it names" do
    let(:congress) { create(:sway_locale, city: "congress", state: "congress", country: "United States") }

    let(:moved_district_json) do
      {
        "bioguideId" => "MOVE001",
        "firstName" => "Moved",
        "lastName" => "Member",
        "partyName" => "Republican",
        "state" => "Florida",
        "district" => 16,
        "currentMember" => true,
        "terms" => {
          "item" => [
            {"startYear" => 2021, "endYear" => 2023, "chamber" => "House of Representatives",
             "stateCode" => "FL", "district" => 13},
            {"startYear" => 2023, "endYear" => 2025, "chamber" => "House of Representatives",
             "stateCode" => "FL", "district" => 16}
          ]
        }
      }
    end

    it "gives the earlier term the district it was served in, not the current one" do
      SeedLegislator.new(moved_district_json, congress, force: true).seed
      leg = Legislator.find_by(external_id: "MOVE001", sway_locale: congress) #: Legislator

      expect(leg.legislator_terms.find_by!(term_start_year: 2021).district.name).to eq("FL13")
      expect(leg.legislator_terms.find_by!(term_start_year: 2023).district.name).to eq("FL16")
    end

    # congress.gov's own roster names no seat inside terms.item. Those entries
    # must keep behaving exactly as they did before this change.
    it "falls back to the current seat when the term names none" do
      silent = moved_district_json.merge(
        "terms" => {
          "item" => [
            {"startYear" => 2021, "endYear" => 2023, "chamber" => "House of Representatives"},
            {"startYear" => 2023, "endYear" => 2025, "chamber" => "House of Representatives"}
          ]
        }
      )

      SeedLegislator.new(silent, congress, force: true).seed
      leg = Legislator.find_by(external_id: "MOVE001", sway_locale: congress) #: Legislator

      expect(leg.legislator_terms.map { |t| t.district.name }.uniq).to eq(["FL16"])
    end

    # A senator has no district number at all, so the seat reads as the
    # state's stand-in 0 — the same name the roster already produces for them.
    it "names a senate term after the state, with no district number" do
      senator = {
        "bioguideId" => "SEN001",
        "firstName" => "Senate",
        "lastName" => "Member",
        "partyName" => "Democrat",
        "state" => "Iowa",
        "currentMember" => true,
        "terms" => {
          "item" => [
            {"startYear" => 2023, "endYear" => 2029, "chamber" => "Senate", "stateCode" => "IA"}
          ]
        }
      }

      SeedLegislator.new(senator, congress, force: true).seed
      leg = Legislator.find_by(external_id: "SEN001", sway_locale: congress) #: Legislator

      expect(leg.legislator_terms.first.district.name).to eq("IA0")
    end
  end

  # ---------------------------------------------------------------------------
  # (f) Running the seeder over the same source data again and again never adds a
  # duplicate term row. A term is unique on legislator plus start year.
  # ---------------------------------------------------------------------------
  describe "(f) idempotency: re-running the seeder stays at one term row per proven year" do
    it "keeps exactly 1 term for the same term_start_year across multiple runs" do
      json = {
        "externalId" => "idempotent-001",
        "active" => true,
        "party" => "D",
        "district" => "MD0",
        "regionCode" => "MD",
        "title" => "Mayor",
        "first_name" => "Idem",
        "last_name" => "Potent",
        "zip" => "21201",
        "country" => "united_states",
        "term_start_year" => 2024,
        "term_end_year" => 2028
      }

      3.times { SeedLegislator.new(json, baltimore, force: true).seed }

      leg = Legislator.find_by(external_id: seat_and_name_key(json)) #: Legislator
      expect(leg.legislator_terms.where(term_start_year: 2024).count).to eq(1)
    end
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars#Current roster rows can supply today's term]]
  describe "(g) non-authoritative reseed does not fabricate or advance a term" do
    let!(:md1) { create(:district, name: "MD1", sway_locale: baltimore) }

    let!(:council_member) do
      create(:legislator,
        external_id: "baltimore-district-1|mark-parker",
        district: md1,
        sway_locale: baltimore,
        title: "Council Member",
        first_name: "Mark",
        last_name: "Parker")
    end

    let!(:existing_term) do
      create(:legislator_term,
        legislator: council_member,
        district: md1,
        title: "Council Member",
        term_start_year: 2024,
        term_end_year: 2028)
    end

    # The same shape BaltimoreRefresh#build_council_entry produces: identified by seat
    # name, carrying current contact details, and with no term year fields at all.
    let(:arcgis_reseed_entry) do
      {
        "title" => "Council Member",
        "externalId" => "baltimore-district-1",
        "external_id" => "baltimore-district-1",
        "active" => true,
        "party" => "D",
        "district" => "MD1",
        "phone" => "410-396-4821",
        "email" => "Mark.Parker@baltimorecity.gov",
        "link" => "https://www.baltimorecitycouncil.com/district1",
        "photoUrl" => nil,
        "regionCode" => "MD",
        "first_name" => "Mark",
        "last_name" => "Parker"
      }
    end

    it "treats the council term as non-authoritative (preparer authoritative_term? is false)" do
      prep = SeedPreparers::Legislators::Sway.new(arcgis_reseed_entry, baltimore)
      expect(prep.authoritative_term?).to be(false)
      expect(prep.proven_terms).to eq([])
    end

    it "updates the seat in place without creating a new legislator or a new term row" do
      expect {
        SeedLegislator.new(arcgis_reseed_entry, baltimore, force: true).seed
      }.not_to change(Legislator, :count)

      council_member.reload
      expect(council_member.external_id).to eq("baltimore-district-1|mark-parker")
      expect(council_member.legislator_terms.count).to eq(1)
      expect(council_member.legislator_terms.first.id).to eq(existing_term.id)
      expect(council_member.legislator_terms.first.term_start_year).to eq(2024)
    end
  end

  # ---------------------------------------------------------------------------
  # (h) The Congress JSON stored in this repo lists real past terms, so they are
  # trusted. A member with two terms gets exactly two LegislatorTerm rows.
  # ---------------------------------------------------------------------------
  describe "(h) two-term Congress member creates two LegislatorTerm rows" do
    let(:congress) { create(:sway_locale, city: "congress", state: "congress", country: "United States") }
    let!(:district_congress) { create(:district, name: "VA1", sway_locale: congress) }

    let(:two_term_json) do
      {
        "bioguideId" => "MULTI001",
        "firstName" => "Multi",
        "lastName" => "Term",
        "partyName" => "Democrat",
        "state" => "Virginia",
        "currentMember" => true,
        "terms" => {
          "item" => [
            {"startYear" => 2019, "endYear" => 2021, "chamber" => "House of Representatives"},
            {"startYear" => 2025, "endYear" => 2027, "chamber" => "House of Representatives"}
          ]
        }
      }
    end

    it "creates two LegislatorTerm rows, one per proven terms.item entry" do
      SeedLegislator.new(two_term_json, congress, force: true).seed

      leg = Legislator.find_by(external_id: "MULTI001", sway_locale: congress) #: Legislator
      expect(leg.legislator_terms.count).to eq(2)
      expect(leg.legislator_terms.pluck(:term_start_year)).to contain_exactly(2019, 2025)
      expect(leg.legislator_terms.find_by(term_start_year: 2019).term_end_year).to eq(2021)
      expect(leg.legislator_terms.find_by(term_start_year: 2025).term_end_year).to eq(2027)
    end
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Why a Congress term is rebuilt from published history#An open roster stretch uses the current calendar window]]
  describe "a member who has held the seat for years" do
    let(:congress) { create(:sway_locale, city: "congress", state: "congress", country: "United States") }
    let!(:district_congress) { create(:district, name: "VA0", sway_locale: congress) }

    let(:senator_since_2013) do
      {
        "bioguideId" => "LONG001",
        "firstName" => "Long",
        "lastName" => "Serving",
        "partyName" => "Democrat",
        "state" => "Virginia",
        "currentMember" => true,
        "terms" => {"item" => [{"startYear" => 2013, "chamber" => "Senate"}]}
      }
    end

    it "is in office on a database seeded from nothing" do
      travel_to Date.new(2026, 7, 31) do
        SeedLegislator.new(senator_since_2013, congress, force: true).seed

        leg = Legislator.find_by(external_id: "LONG001", sway_locale: congress) #: Legislator
        expect(leg.serving?).to be(true)
        expect(leg.active_term.term_start_year).to eq(2025)
        expect(leg.active_term.term_end_year).to eq(2031)
      end
    end

    it "gains the next term when seeded again in the next cycle" do
      travel_to Date.new(2026, 7, 31) do
        SeedLegislator.new(senator_since_2013, congress, force: true).seed
      end

      travel_to Date.new(2031, 3, 1) do
        SeedLegislator.new(senator_since_2013, congress, force: true).seed

        leg = Legislator.find_by(external_id: "LONG001", sway_locale: congress) #: Legislator
        expect(leg.legislator_terms.pluck(:term_start_year)).to contain_exactly(2025, 2031)
        expect(leg.serving?).to be(true)
        expect(leg.active_term.term_start_year).to eq(2031)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # (i) A Maryland or Baltimore member whose data lists no past terms gets exactly one
  # term row, for the term they are serving now. Past terms are never invented.
  # ---------------------------------------------------------------------------
  describe "(i) MD/Baltimore member with no prior-term JSON gets exactly one term" do
    let(:maryland) { create(:sway_locale, city: "maryland", state: "maryland", country: "United States") }
    let!(:district_md) { create(:district, name: "MD1", sway_locale: maryland) }

    let(:md_json_no_date) do
      {
        "id" => "ocd-person/no-prior-001",
        "given_name" => "NoPrior",
        "family_name" => "Legislator",
        "party" => ["D"],
        "image" => nil,
        "current_role" => {
          "title" => "State Delegate",
          "district" => "1"
          # No start_date or end_date, on purpose: all 191 live records look like this
        },
        "jurisdiction" => {"name" => "Maryland"},
        "openstates_url" => "https://openstates.org/person/no-prior-001"
      }
    end

    it "creates exactly one term (never fabricates a prior term from the fallback cycle anchor)" do
      SeedLegislator.new(md_json_no_date, maryland, force: true).seed

      leg = Legislator.find_by(external_id: "ocd-person/no-prior-001", sway_locale: maryland) #: Legislator
      expect(leg.legislator_terms.count).to eq(1)
    end
  end

  describe "(j) unsupported executives require official service evidence" do
    let(:congress) { create(:sway_locale, city: "congress", state: "congress", country: "United States") }

    let(:potus_json) do
      {
        "bioguideId" => "POTUS",
        "name" => "Test, President",
        "partyName" => "Republican",
        "state" => "US",
        "currentMember" => true,
        "terms" => {"item" => [{"chamber" => "White House", "startYear" => 2025}, {"chamber" => "White House", "startYear" => 2021}]}
      }
    end

    # @lat: [[lat.md/reference/official-service-evidence-tests#Official service evidence tests#Unsupported President remains absent on a fresh installation]]
    it "does not create a person from the unsupported roster sentinel" do
      expect {
        SeedLegislator.new(potus_json, congress, force: true).seed
      }.not_to change(Legislator, :count)

      expect(Legislator.find_by(external_id: "POTUS", sway_locale: congress)).to be_nil
    end

    context "with an existing migration-synthesized POTUS term" do
      let!(:district_us0) { District.find_or_create_by!(sway_locale: congress, name: "US0") }
      let!(:potus_legislator) do
        create(
          :legislator,
          sway_locale: congress,
          external_id: "POTUS",
          first_name: "Donald",
          last_name: "Trump",
          party: "Republican"
        )
      end
      let!(:potus_identifier) do
        LegislatorIdentifier.record!(
          legislator: potus_legislator,
          identity: LegislatorIdentity.new(source: LegislatorIdentity::BIOGUIDE, value: "POTUS")
        )
      end
      let!(:user) { create(:user) }
      let!(:user_legislator) { create(:user_legislator, user: user, legislator: potus_legislator) }
      let!(:unevidenced_term) do
        create(
          :legislator_term,
          legislator: potus_legislator,
          district: district_us0,
          term_start_year: 2025,
          term_end_year: 2027,
          title: nil,
          seat_id: nil
        )
      end
      let!(:district_score) { create(:legislator_district_score, legislator_term: unevidenced_term) }
      let!(:locale_score) { create(:legislator_locale_score, legislator_term: unevidenced_term) }
      let!(:user_term_score) { create(:user_legislator_term_score, user_legislator: user_legislator, legislator_term: unevidenced_term) }

      before do
        allow(described_class).to receive(:read_legislators).with(congress).and_return([potus_json])
      end

      # @lat: [[lat.md/reference/official-service-evidence-tests#Official service evidence tests#Unevidenced executive terms are retired when official evidence is unsupported#Unevidenced POTUS term in US0 is retired when official evidence is unsupported]]
      it "retires the un-evidenced term and scores while preserving person and identifiers" do
        allow(Sentry).to receive(:capture_exception)
        reg_service = SwayRegistrationService.new(user, nil, congress, invited_by_id: nil, async: false)
        expect(reg_service.send(:locale_wide_candidates)).to be_empty
        expect(reg_service.skipped_resolution_errors).to contain_exactly(an_instance_of(Seats::UnresolvedSeatError))

        described_class.run([congress])

        expect(LegislatorTerm.find_by(id: unevidenced_term.id)).to be_nil
        expect(LegislatorDistrictScore.where(legislator_term_id: unevidenced_term.id)).to be_empty
        expect(LegislatorLocaleScore.where(legislator_term_id: unevidenced_term.id)).to be_empty
        expect(UserLegislatorTermScore.where(legislator_term_id: unevidenced_term.id)).to be_empty

        expect(district_us0.legislator_terms.current).to be_empty

        expect { reg_service.send(:locale_wide_candidates) }.not_to raise_error
        expect(reg_service.send(:locale_wide_candidates)).to be_empty

        expect(Legislator.find_by(id: potus_legislator.id)).to eq(potus_legislator)
        expect(LegislatorIdentifier.where(legislator: potus_legislator, source: LegislatorIdentity::BIOGUIDE, value: "POTUS")).to exist
        expect(UserLegislator.where(user: user, legislator: potus_legislator)).to exist
      end

      # @lat: [[lat.md/reference/official-service-evidence-tests#Official service evidence tests#Unevidenced executive terms are retired when official evidence is unsupported#Evidenced presidential term and seat are preserved when official evidence is supported]]
      it "preserves evidenced presidential term and seat when official service evidence is supported" do
        profile = {
          capability: "supported",
          publisher: "records.example.gov",
          jurisdiction: "example_executive",
          source_url: "https://records.example.gov/service",
          identity_source: LegislatorIdentity::BIOGUIDE,
          office_identity: "us-president",
          fact_type: "executive_service",
          records_path: "records",
          fields: {
            id: "id",
            office_identity: "office_id",
            first_name: "first_name",
            last_name: "last_name",
            title: "title",
            chamber: "chamber",
            district: "district",
            start_date: "start_date",
            end_date: "end_date",
            presence: "presence"
          },
          date_semantics: {start: "inclusive", end: "exclusive"}
        }

        records = [
          {
            id: "POTUS",
            office_id: "us-president",
            first_name: "Donald",
            last_name: "Trump",
            title: "President",
            chamber: "Executive",
            district: "US0",
            start_date: "2025-01-20",
            end_date: "2029-01-20",
            presence: "present"
          }
        ]

        payload = {records: records}.to_json
        stubs = Faraday::Adapter::Test::Stubs.new do |stub|
          stub.get("/service") { [200, {"Content-Type" => "application/json"}, payload] }
        end
        connection = Faraday.new("https://records.example.gov") { |faraday| faraday.adapter :test, stubs }
        supported_result = Legislation::Adapters::GenericRosterAdapter.new(
          {roster_rules: {official_service: profile}},
          connection: connection
        ).fetch_official_service(sway_locale: congress)

        user_term_score.destroy!
        district_score.destroy!
        locale_score.destroy!
        unevidenced_term.destroy!

        allow(described_class).to receive(:official_service_result_for).with(congress).and_return(supported_result)

        described_class.run([congress])

        presidential_term = potus_legislator.reload.legislator_terms.sole
        expect(presidential_term.seat).to be_present
        expect(presidential_term.seat&.seat_identifier).to eq("us-president")
        expect(presidential_term.title).to eq("President")
        expect(presidential_term.began_on).to eq(Date.new(2025, 1, 20))
        expect(presidential_term.ended_on).to eq(Date.new(2029, 1, 20))
        expect(district_us0.seats.where(seat_identifier: "us-president")).to exist

        described_class.run([congress])
        expect(LegislatorTerm.find_by(id: presidential_term.id)).to eq(presidential_term)
        expect(district_us0.seats.where(seat_identifier: "us-president")).to exist
      end
    end
  end

  # ---------------------------------------------------------------------------
  # The preparers themselves: one class per upstream source, each pulling term years
  # out of that source's own data shape.
  # ---------------------------------------------------------------------------
  describe "Preparer term extraction" do
    describe "CongressDotGov preparer" do
      let(:congress) { create(:sway_locale, city: "congress", state: "congress", country: "United States") }

      let(:full_blob) do
        {
          "bioguideId" => "FULL001",
          "firstName" => "Full",
          "lastName" => "Congress",
          "partyName" => "Democrat",
          "state" => "Virginia",
          "currentMember" => true,
          "terms" => {
            "item" => [
              {"startYear" => 2025, "endYear" => 2027, "chamber" => "House of Representatives"}
            ]
          }
        }
      end

      let(:empty_terms_blob) do
        {
          "bioguideId" => "EMPTY001",
          "firstName" => "Empty",
          "lastName" => "Terms",
          "partyName" => "Democrat",
          "state" => "Virginia",
          "currentMember" => true
          # No terms.item
        }
      end

      let(:potus_blob) do
        {
          "bioguideId" => "POTUS",
          "name" => "Trump, Donald",
          "partyName" => "Republican",
          "state" => "New York",
          "currentMember" => true,
          "terms" => {
            "item" => [
              {"startYear" => 2025, "endYear" => 2029, "chamber" => nil},
              {"startYear" => 2021, "endYear" => 2025, "chamber" => nil}
            ]
          }
        }
      end

      let(:oldest_first_blob) do
        full_blob.merge(
          "bioguideId" => "OLDEST001",
          "terms" => {
            "item" => [
              {"startYear" => 2019, "endYear" => 2021, "chamber" => "House of Representatives"},
              {"startYear" => 2025, "endYear" => 2027, "chamber" => "House of Representatives"}
            ]
          }
        )
      end

      let(:senate_mover_blob) do
        full_blob.merge(
          "bioguideId" => "MOVER001",
          "terms" => {
            "item" => [
              {"startYear" => 2001, "endYear" => 2024, "chamber" => "House of Representatives"},
              {"startYear" => 2024, "chamber" => "Senate"} # newest entry, no endYear
            ]
          }
        )
      end

      subject(:preparer) { SeedPreparers::Legislators::CongressDotGov.new(full_blob, congress) }

      it "returns term_start_year from blob" do
        expect(preparer.term_start_year).to eq(2025)
        expect(preparer.term_start_year).not_to be_nil
      end

      it "returns term_end_year from blob" do
        expect(preparer.term_end_year).to eq(2027)
        expect(preparer.term_end_year).not_to be_nil
      end

      it "authoritative_term? is true when startYear is present" do
        expect(preparer.authoritative_term?).to be(true)
      end

      it "(H4) returns non-nil term_start_year even when terms.item absent" do
        prep = SeedPreparers::Legislators::CongressDotGov.new(empty_terms_blob, congress)
        expect(prep.term_start_year).not_to be_nil
        expect(prep.term_start_year).to be_a(Integer)
      end

      it "(H4) returns non-nil term_end_year even when terms.item absent" do
        prep = SeedPreparers::Legislators::CongressDotGov.new(empty_terms_blob, congress)
        expect(prep.term_end_year).not_to be_nil
        expect(prep.term_end_year).to be_a(Integer)
      end

      it "(H4) authoritative_term? is false when terms.item absent" do
        prep = SeedPreparers::Legislators::CongressDotGov.new(empty_terms_blob, congress)
        expect(prep.authoritative_term?).to be(false)
      end

      it "proven_terms is empty when terms.item absent — no fabrication" do
        prep = SeedPreparers::Legislators::CongressDotGov.new(empty_terms_blob, congress)
        expect(prep.proven_terms).to eq([])
      end

      it "(L10) reads newest (max_by startYear) not positional last — POTUS newest-first array" do
        prep = SeedPreparers::Legislators::CongressDotGov.new(potus_blob, congress)
        expect(prep.term_start_year).to eq(2025)
      end

      it "(L10) reads newest for oldest-first array" do
        prep = SeedPreparers::Legislators::CongressDotGov.new(oldest_first_blob, congress)
        expect(prep.term_start_year).to eq(2025)
      end

      it "proven_terms returns one entry per terms.item, oldest-first array" do
        prep = SeedPreparers::Legislators::CongressDotGov.new(oldest_first_blob, congress)
        expect(prep.proven_terms.pluck(:term_start_year)).to contain_exactly(2019, 2025)
      end

      it "proven_terms resolves title per-entry chamber, not the current title" do
        prep = SeedPreparers::Legislators::CongressDotGov.new(senate_mover_blob, congress)
        house_term = prep.proven_terms.find { |t| t[:term_start_year] == 2001 } #: Hash[Symbol, untyped]
        senate_term = prep.proven_terms.find { |t| t[:term_start_year] == 2024 } #: Hash[Symbol, untyped]
        expect(house_term[:title]).to eq("Rep.")
        expect(senate_term[:title]).to eq("Sen.")
      end

      it "proven_terms falls back to chamber term length when endYear is absent" do
        travel_to Date.new(2026, 7, 31) do
          prep = SeedPreparers::Legislators::CongressDotGov.new(senate_mover_blob, congress)
          senate_term = prep.proven_terms.find { |t| t[:term_start_year] == 2024 } #: Hash[Symbol, untyped]
          expect(senate_term[:term_end_year]).to eq(2030) # 2024 plus a 6-year Senate term
        end
      end

      # @lat: [[current-legislator-term#Which term a legislator is serving now#Why a Congress term is rebuilt from published history#An open roster stretch uses the current calendar window]]
      describe "an open stretch of service reports the term running now" do
        let(:long_serving_senator) do
          full_blob.merge(
            "bioguideId" => "SEN2013",
            "terms" => {"item" => [{"startYear" => 2013, "chamber" => "Senate"}]}
          )
        end

        let(:long_serving_house_legislator) do
          full_blob.merge(
            "bioguideId" => "REP2013",
            "terms" => {"item" => [{"startYear" => 2013, "chamber" => "House of Representatives"}]}
          )
        end

        let(:not_yet_seated) do
          full_blob.merge(
            "bioguideId" => "FUTURE1",
            "terms" => {"item" => [{"startYear" => 2029, "chamber" => "Senate"}]}
          )
        end

        it "counts six years at a time to the senator's current term" do
          travel_to Date.new(2026, 7, 31) do
            prep = SeedPreparers::Legislators::CongressDotGov.new(long_serving_senator, congress)

            expect(prep.term_start_year).to eq(2025)
            expect(prep.term_end_year).to eq(2031)
          end
        end

        it "counts two years at a time to the representative's current term" do
          travel_to Date.new(2026, 7, 31) do
            prep = SeedPreparers::Legislators::CongressDotGov.new(long_serving_house_legislator, congress)

            expect(prep.term_start_year).to eq(2025)
            expect(prep.term_end_year).to eq(2027)
          end
        end

        it "moves on to the next term once that one has convened" do
          travel_to Date.new(2027, 3, 1) do
            prep = SeedPreparers::Legislators::CongressDotGov.new(long_serving_house_legislator, congress)

            expect(prep.term_start_year).to eq(2027)
            expect(prep.term_end_year).to eq(2029)
          end
        end

        it "leaves a first year that has not arrived where it is" do
          travel_to Date.new(2026, 7, 31) do
            prep = SeedPreparers::Legislators::CongressDotGov.new(not_yet_seated, congress)

            expect(prep.term_start_year).to eq(2029)
            expect(prep.term_end_year).to eq(2035)
          end
        end

        it "keeps the years a closed stretch recorded" do
          travel_to Date.new(2026, 7, 31) do
            prep = SeedPreparers::Legislators::CongressDotGov.new(senate_mover_blob, congress)
            house_term = prep.proven_terms.find { |t| t[:title] == "Rep." } #: Hash[Symbol, untyped]

            expect(house_term[:term_start_year]).to eq(2001)
            expect(house_term[:term_end_year]).to eq(2024)
          end
        end
      end

      it "(SPEC boundary) executive? is true for POTUS" do
        prep = SeedPreparers::Legislators::CongressDotGov.new(potus_blob, congress)
        expect(prep.executive?).to be(true)
      end

      it "(SPEC boundary) executive? is false for a non-POTUS member" do
        expect(preparer.executive?).to be(false)
      end
    end

    describe "OpenStates preparer" do
      let(:maryland) { create(:sway_locale, city: "maryland", state: "maryland", country: "United States") }

      let(:full_blob) do
        {
          "id" => "ocd-person/full-001",
          "given_name" => "Full",
          "family_name" => "Legislator",
          "party" => ["D"],
          "image" => nil,
          "current_role" => {
            "title" => "State Delegate",
            "district" => "1",
            "start_date" => "2023-01-11",
            "end_date" => "2027-01-10"
          },
          "jurisdiction" => {"name" => "Maryland"},
          "openstates_url" => "https://openstates.org/person/full-001"
        }
      end

      let(:no_date_blob) do
        {
          "id" => "ocd-person/nodate-001",
          "given_name" => "NoDate",
          "family_name" => "Legislator",
          "party" => ["D"],
          "image" => nil,
          "current_role" => {
            "title" => "State Delegate",
            "district" => "1"
            # No start_date / end_date
          },
          "jurisdiction" => {"name" => "Maryland"},
          "openstates_url" => "https://openstates.org/person/nodate-001"
        }
      end

      subject(:preparer) { SeedPreparers::Legislators::OpenStates.new(full_blob, maryland) }

      it "returns term_start_year from current_role.start_date" do
        expect(preparer.term_start_year).to eq(2023)
        expect(preparer.term_start_year).not_to be_nil
      end

      it "returns term_end_year from current_role.end_date" do
        expect(preparer.term_end_year).to eq(2027)
        expect(preparer.term_end_year).not_to be_nil
      end

      it "authoritative_term? is true when start_date present" do
        expect(preparer.authoritative_term?).to be(true)
      end

      it "proven_terms returns exactly one entry when authoritative" do
        expect(preparer.proven_terms).to eq(
          [{term_start_year: 2023, term_end_year: 2027, title: "State Delegate"}]
        )
      end

      it "(H4) returns non-nil term_start_year even when start_date absent" do
        prep = SeedPreparers::Legislators::OpenStates.new(no_date_blob, maryland)
        expect(prep.term_start_year).not_to be_nil
        expect(prep.term_start_year).to be_a(Integer)
      end

      it "(H4) returns non-nil term_end_year even when start_date absent" do
        prep = SeedPreparers::Legislators::OpenStates.new(no_date_blob, maryland)
        expect(prep.term_end_year).not_to be_nil
        expect(prep.term_end_year).to be_a(Integer)
      end

      it "(H4) authoritative_term? is false when start_date absent" do
        prep = SeedPreparers::Legislators::OpenStates.new(no_date_blob, maryland)
        expect(prep.authoritative_term?).to be(false)
      end

      it "proven_terms is empty when start_date absent — no fabrication" do
        prep = SeedPreparers::Legislators::OpenStates.new(no_date_blob, maryland)
        expect(prep.proven_terms).to eq([])
      end

      it "(H7/M12 stability) returns 2023 under travel_to(2024)" do
        travel_to(Time.zone.local(2024, 6, 1)) do
          prep = SeedPreparers::Legislators::OpenStates.new(no_date_blob, maryland)
          expect(prep.term_start_year).to eq(2023)
        end
      end

      it "(H7/M12 stability) returns 2023 under travel_to(2025)" do
        travel_to(Time.zone.local(2025, 6, 1)) do
          prep = SeedPreparers::Legislators::OpenStates.new(no_date_blob, maryland)
          expect(prep.term_start_year).to eq(2023)
        end
      end

      it "(H7/M12 stability) returns 2023 under travel_to(2026)" do
        travel_to(Time.zone.local(2026, 6, 1)) do
          prep = SeedPreparers::Legislators::OpenStates.new(no_date_blob, maryland)
          expect(prep.term_start_year).to eq(2023)
        end
      end

      it "(H7/M12 stability) returns 2027 under travel_to(2027)" do
        travel_to(Time.zone.local(2027, 6, 1)) do
          prep = SeedPreparers::Legislators::OpenStates.new(no_date_blob, maryland)
          expect(prep.term_start_year).to eq(2027)
        end
      end

      context "with a two-year alternate state" do
        it "yields its own declared cycle years rather than Maryland years" do
          alternate_rules = SwayLocale::TermRules.new(
            convening: SwayLocale::FixedDayConvening.new(month: 1, day: 1),
            cycle_anchor_year: 2025,
            cycle_years: 2,
            roster_lists_only_current_legislators: true,
            publishes_term_history: false,
            publishes_exact_term_dates: false,
            identified_by: :person
          )
          alternate_state = instance_double(SwayLocale, name: "virginia-virginia-united_states", term_rules: alternate_rules)
          travel_to(Time.zone.local(2026, 6, 1)) do
            prep = SeedPreparers::Legislators::OpenStates.new(no_date_blob, alternate_state)
            expect(prep.term_start_year).to eq(2025)
            expect(prep.term_end_year).to eq(2027)
          end
        end

        it "retains supplied upstream dates intact" do
          alternate_rules = SwayLocale::TermRules.new(
            convening: SwayLocale::FixedDayConvening.new(month: 1, day: 1),
            cycle_anchor_year: 2025,
            cycle_years: 2,
            roster_lists_only_current_legislators: true,
            publishes_term_history: false,
            publishes_exact_term_dates: false,
            identified_by: :person
          )
          alternate_state = instance_double(SwayLocale, name: "virginia-virginia-united_states", term_rules: alternate_rules)
          prep = SeedPreparers::Legislators::OpenStates.new(full_blob, alternate_state)
          expect(prep.term_start_year).to eq(2023)
          expect(prep.term_end_year).to eq(2027)
        end

        it "does not treat cycle fallback as authoritative service evidence" do
          alternate_rules = SwayLocale::TermRules.new(
            convening: SwayLocale::FixedDayConvening.new(month: 1, day: 1),
            cycle_anchor_year: 2025,
            cycle_years: 2,
            roster_lists_only_current_legislators: true,
            publishes_term_history: false,
            publishes_exact_term_dates: false,
            identified_by: :person
          )
          alternate_state = instance_double(SwayLocale, name: "virginia-virginia-united_states", term_rules: alternate_rules)
          prep = SeedPreparers::Legislators::OpenStates.new(no_date_blob, alternate_state)
          expect(prep.authoritative_term?).to be(false)
          expect(prep.proven_terms).to eq([])
        end
      end
    end

    describe "Sway preparer" do
      let(:baltimore) { create(:sway_locale, city: "baltimore", state: "maryland", country: "United States") }

      let(:full_blob) do
        {
          "externalId" => "council-member-2024",
          "active" => true,
          "party" => "D",
          "district" => "MD1",
          "regionCode" => "MD",
          "title" => "Council Member",
          "first_name" => "Council",
          "last_name" => "Member",
          "zip" => "21201",
          "country" => "united_states",
          "term_start_year" => 2024,
          "term_end_year" => 2028
        }
      end

      let(:no_term_blob) do
        {
          "externalId" => "baltimore-mayor",
          "active" => true,
          "party" => "D",
          "district" => "MD0",
          "regionCode" => "MD",
          "title" => "Mayor",
          "first_name" => "Mayor",
          "last_name" => "Person",
          "zip" => "21202",
          "country" => "united_states"
          # No term_start_year / termStartYear
        }
      end

      subject(:preparer) { SeedPreparers::Legislators::Sway.new(full_blob, baltimore) }

      it "returns term_start_year from blob" do
        expect(preparer.term_start_year).to eq(2024)
        expect(preparer.term_start_year).not_to be_nil
      end

      it "returns term_end_year from blob" do
        expect(preparer.term_end_year).to eq(2028)
        expect(preparer.term_end_year).not_to be_nil
      end

      it "authoritative_term? is true when term_start_year present" do
        expect(preparer.authoritative_term?).to be(true)
      end

      it "proven_terms returns exactly one entry when authoritative" do
        expect(preparer.proven_terms).to eq(
          [{term_start_year: 2024, term_end_year: 2028, title: "Council Member"}]
        )
      end

      it "(H4) returns non-nil term_start_year when blob omits term fields" do
        prep = SeedPreparers::Legislators::Sway.new(no_term_blob, baltimore)
        expect(prep.term_start_year).not_to be_nil
        expect(prep.term_start_year).to be_a(Integer)
      end

      it "(H4) returns non-nil term_end_year when blob omits term fields" do
        prep = SeedPreparers::Legislators::Sway.new(no_term_blob, baltimore)
        expect(prep.term_end_year).not_to be_nil
        expect(prep.term_end_year).to be_a(Integer)
      end

      it "(H4) authoritative_term? is false when blob omits term fields" do
        prep = SeedPreparers::Legislators::Sway.new(no_term_blob, baltimore)
        expect(prep.authoritative_term?).to be(false)
      end

      it "proven_terms is empty when blob omits term fields — no fabrication" do
        prep = SeedPreparers::Legislators::Sway.new(no_term_blob, baltimore)
        expect(prep.proven_terms).to eq([])
      end

      it "names the roster entry's published id as the office of a person-keyed locale" do
        annapolis = create(:sway_locale, city: "annapolis", state: "maryland", country: "United States")
        prep = SeedPreparers::Legislators::Sway.new(no_term_blob.merge("externalId" => "annapolis-mayor"), annapolis)

        expect(prep.current_office_identity).to eq("annapolis-mayor")
      end

      it "(H6 stability) returns 2024 under travel_to(2026)" do
        travel_to(Time.zone.local(2026, 6, 1)) do
          prep = SeedPreparers::Legislators::Sway.new(no_term_blob, baltimore)
          expect(prep.term_start_year).to eq(2024)
        end
      end

      it "(H6 stability) returns 2024 under travel_to(2027)" do
        travel_to(Time.zone.local(2027, 6, 1)) do
          prep = SeedPreparers::Legislators::Sway.new(no_term_blob, baltimore)
          expect(prep.term_start_year).to eq(2024)
        end
      end

      it "(H6 stability) returns 2028 under travel_to(2028)" do
        travel_to(Time.zone.local(2028, 6, 1)) do
          prep = SeedPreparers::Legislators::Sway.new(no_term_blob, baltimore)
          expect(prep.term_start_year).to eq(2028)
        end
      end

      it "external_id is coerced to string (numeric Legistar id)" do
        numeric_blob = no_term_blob.merge("externalId" => 12345)
        prep = SeedPreparers::Legislators::Sway.new(numeric_blob, baltimore)
        expect(prep.external_id).to be_a(String)
        expect(prep.external_id).to eq("12345")
      end

      context "with a two-year alternate locale" do
        it "yields its own declared cycle years rather than Baltimore years" do
          alternate_rules = SwayLocale::TermRules.new(
            convening: SwayLocale::FixedDayConvening.new(month: 1, day: 1),
            cycle_anchor_year: 2025,
            cycle_years: 2,
            roster_lists_only_current_legislators: true,
            publishes_term_history: false,
            publishes_exact_term_dates: false,
            identified_by: :person
          )
          alternate_city = instance_double(SwayLocale, name: "annapolis-maryland-united_states", term_rules: alternate_rules)
          travel_to(Time.zone.local(2026, 6, 1)) do
            prep = SeedPreparers::Legislators::Sway.new(no_term_blob, alternate_city)
            expect(prep.term_start_year).to eq(2025)
            expect(prep.term_end_year).to eq(2027)
          end
        end

        it "retains supplied upstream dates intact" do
          alternate_rules = SwayLocale::TermRules.new(
            convening: SwayLocale::FixedDayConvening.new(month: 1, day: 1),
            cycle_anchor_year: 2025,
            cycle_years: 2,
            roster_lists_only_current_legislators: true,
            publishes_term_history: false,
            publishes_exact_term_dates: false,
            identified_by: :person
          )
          alternate_city = instance_double(SwayLocale, name: "annapolis-maryland-united_states", term_rules: alternate_rules)
          prep = SeedPreparers::Legislators::Sway.new(full_blob, alternate_city)
          expect(prep.term_start_year).to eq(2024)
          expect(prep.term_end_year).to eq(2028)
        end

        it "does not treat cycle fallback as authoritative service evidence" do
          alternate_rules = SwayLocale::TermRules.new(
            convening: SwayLocale::FixedDayConvening.new(month: 1, day: 1),
            cycle_anchor_year: 2025,
            cycle_years: 2,
            roster_lists_only_current_legislators: true,
            publishes_term_history: false,
            publishes_exact_term_dates: false,
            identified_by: :person
          )
          alternate_city = instance_double(SwayLocale, name: "annapolis-maryland-united_states", term_rules: alternate_rules)
          prep = SeedPreparers::Legislators::Sway.new(no_term_blob, alternate_city)
          expect(prep.authoritative_term?).to be(false)
          expect(prep.proven_terms).to eq([])
        end
      end
    end
  end
end
