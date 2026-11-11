# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "seed_preparers", "legislators", "sway")

# A bare subclass of BaseRefresh, used by every example to check what the
# base class promises. Lives at module level, not inside a `let`, so Steep
# can see the class.
module LegislatorsCache
  class TestRefresh < BaseRefresh
    def call
      Result.new(changed_files: {})
    end
  end
end

RSpec.describe LegislatorsCache::BaseRefresh do
  describe "BUCKET_NAME constant" do
    # The bucket isn't named here — it names one person's cloud account and
    # this repo is public — so it comes from deploy/config/sway.env, the
    # tracked fake value under RAILS_ENV=test.
    it "points at the same bucket the app serves assets from" do
      expect(described_class::BUCKET_NAME).to eq(SwayGoogleCloudStorage::BUCKETS[:ASSETS])
      expect(described_class::BUCKET_NAME).to be_present
    end
  end

  describe "Result value object" do
    it "is a Data with a changed_files accessor" do
      result = described_class::Result.new(changed_files: {"some/path" => "{}"})
      expect(result.changed_files).to eq({"some/path" => "{}"})
    end

    it "is frozen (immutable)" do
      result = described_class::Result.new(changed_files: {})
      expect(result).to be_frozen
    end
  end

  describe "#call" do
    let(:sway_locale) { create(:sway_locale, :congress) }
    let(:adapter) { instance_double(Legislation::Adapters::GenericRosterAdapter) }

    before do
      allow(LegislatorsCache::CongressTermHistory).to receive(:fetch).and_return(
        instance_double(LegislatorsCache::CongressTermHistory, terms_for: nil, missing: [])
      )
    end

    context "when publishing a refreshed roster" do
      let(:baseline_file) { Tempfile.new(["stored-roster", ".json"]) }
      let(:output_file) { Tempfile.new(["refreshed-roster", ".json"]) }
      let(:stored_member) do
        {"bioguideId" => "A000001", "depiction" => {"imageUrl" => "stored.jpg"}}
      end
      let(:refresh_service_under_test) { described_class.new(sway_locale, force: true, adapter:) }

      before do
        baseline_file.write(JSON.generate([stored_member]))
        baseline_file.flush

        allow(refresh_service_under_test).to receive(:canonical_seed_path).and_return(baseline_file.path)
        allow(refresh_service_under_test).to receive(:output_json_path).and_return(output_file.path)
        allow(refresh_service_under_test).to receive(:upload_json_to_gcs)
      end

      after do
        baseline_file.close!
        output_file.close!
      end

      # @lat: [[current-legislator-term#Missing source fields preserve stored roster values]]
      it "keeps the stored photo in the published result when the source omits it" do
        allow(adapter).to receive(:fetch_roster).and_return([{"bioguideId" => "A000001", "name" => "Ada Member"}])

        result = refresh_service_under_test.call
        path = "db/seeds/data/#{sway_locale.reversed_name.tr("-", "/")}/legislators.json"
        published_member = JSON.parse(result.changed_files.fetch(path)).first

        expect(published_member.dig("depiction", "imageUrl")).to eq("stored.jpg")
      end

      it "keeps an explicit source photo clear in the published result" do
        allow(adapter).to receive(:fetch_roster).and_return([
          {"bioguideId" => "A000001", "depiction" => {"imageUrl" => nil}}
        ])

        result = refresh_service_under_test.call
        path = "db/seeds/data/#{sway_locale.reversed_name.tr("-", "/")}/legislators.json"
        published_member = JSON.parse(result.changed_files.fetch(path)).first

        expect(published_member.fetch("depiction")).to include("imageUrl" => nil)
      end

      it "does not give a successor the previous member's photo" do
        allow(adapter).to receive(:fetch_roster).and_return([
          {"bioguideId" => "B000002", "name" => "Bea Successor"}
        ])

        result = refresh_service_under_test.call
        path = "db/seeds/data/#{sway_locale.reversed_name.tr("-", "/")}/legislators.json"
        published_member = JSON.parse(result.changed_files.fetch(path)).first

        expect(published_member).not_to have_key("depiction")
      end
    end

    it "fetches roster from GenericRosterAdapter, writes output JSON, and updates fetched_at" do
      member_hash = {"external_id" => "A000360", "bioguideId" => "A000360", "name" => "Alexander, Lamar"}
      allow(adapter).to receive(:fetch_roster).with(sway_locale: sway_locale, connection: nil).and_return([member_hash])
      service = described_class.new(sway_locale, adapter: adapter)
      allow(service).to receive(:upload_file)

      result = service.call
      expect(result).to be_a(described_class::Result)
      expect(sway_locale.reload.legislators_cache_fetched_at).to be_present
    end

    it "returns empty Result without invoking adapter when freshness check fails" do
      sway_locale.update_columns(legislators_cache_fetched_at: 1.day.ago)
      service = described_class.new(sway_locale, adapter: adapter)

      expect(adapter).not_to receive(:fetch_roster)
      result = service.call
      expect(result.changed_files).to eq({})
    end

    it "returns empty Result without network calls when roster engine is unavailable" do
      manual_locale = create(:sway_locale, city: "annapolis", state: "maryland", country: "united_states")
      service = described_class.new(manual_locale, adapter: adapter)

      expect(adapter).not_to receive(:fetch_roster)
      result = service.call
      expect(result.changed_files).to eq({})
    end

    it "returns empty Result when adapter returns an empty roster" do
      allow(adapter).to receive(:fetch_roster).and_return([])
      service = described_class.new(sway_locale, adapter: adapter)

      result = service.call
      expect(result.changed_files).to eq({})
    end

    context "legacy roster_refresher and roster_source decoupling" do
      it "does not check roster_refresher or roster_source on rules" do
        rules = double(
          "JurisdictionRules",
          roster_rules: {engine: "unavailable"},
          roster_retrieval: nil,
          roster_parsing: nil
        )
        expect(rules).not_to receive(:roster_refresher)
        expect(rules).not_to receive(:roster_source)
        allow(sway_locale).to receive(:jurisdiction_rules).and_return(rules)

        service = described_class.new(sway_locale, adapter: adapter)
        result = service.call
        expect(result.changed_files).to eq({})
      end
    end

    it "propagates SwayLocale::JurisdictionRules::Undeclared without referencing RSpec constants" do
      hide_const("RSpec::Mocks::MockExpectationError")
      allow(SwayLocale::JurisdictionRulesRegistry).to receive(:fetch).and_raise(SwayLocale::JurisdictionRules::Undeclared)
      service = described_class.new(sway_locale, adapter: adapter)

      expect { service.call }.to raise_error(SwayLocale::JurisdictionRules::Undeclared)
    end

    context "for the Congress locale" do
      let(:baseline_file) { Tempfile.new(["stored-roster", ".json"]) }
      let(:output_file) { Tempfile.new(["refreshed-roster", ".json"]) }
      let(:service) { described_class.new(sway_locale, force: true, adapter: adapter) }
      let(:path) { "db/seeds/data/#{sway_locale.reversed_name.tr("-", "/")}/legislators.json" }
      let(:potus_entry) do
        {
          "bioguideId" => LegislatorsCache::POTUS_BIOGUIDE_ID,
          "name" => "Biden, Joseph R. Jr.",
          "firstName" => "Joseph",
          "lastName" => "Biden",
          "partyName" => "Democratic",
          "currentMember" => true
        }
      end

      before do
        allow(service).to receive(:canonical_seed_path).and_return(baseline_file.path)
        allow(service).to receive(:output_json_path).and_return(output_file.path)
        allow(service).to receive(:upload_json_to_gcs)
      end

      after do
        baseline_file.close!
        output_file.close!
      end

      # @lat: [[current-legislator-term#Departed members are put back before term history is asked]]
      it "includes a legislator stored as in office who is missing from the fetch, marked currentMember false" do
        baseline_file.write(JSON.generate([{"bioguideId" => "A000001"}, {"bioguideId" => "R000595"}]))
        baseline_file.flush

        legislator = create(:legislator, sway_locale: sway_locale, external_id: "R000595", first_name: "Marco", last_name: "Rubio", party: "R")
        district = District.find_or_create_by!(name: "FL0", sway_locale: sway_locale)
        create(:legislator_term, legislator: legislator, district: district, term_start_year: Date.current.year - 1, term_end_year: Date.current.year + 1)

        allow(adapter).to receive(:fetch_roster).and_return([{"bioguideId" => "A000001", "name" => "Ada Member"}])

        result = service.call
        entries = JSON.parse(result.changed_files.fetch(path))
        departed = entries.find { |m| m["bioguideId"] == "R000595" }

        expect(departed).to be_present
        expect(departed["currentMember"]).to be false
      end

      # @lat: [[current-legislator-term#Why a Congress term is rebuilt from published history]]
      it "stamps every entry except the President with termsSource from term history" do
        baseline_file.write(JSON.generate([potus_entry, {"bioguideId" => "A000001"}]))
        baseline_file.flush

        allow(adapter).to receive(:fetch_roster).and_return([{"bioguideId" => "A000001", "name" => "Ada Member"}])
        sample_terms = [{"chamber" => "House of Representatives", "startYear" => 2023, "endYear" => 2025}]
        history = instance_double(LegislatorsCache::CongressTermHistory, missing: [])
        allow(history).to receive(:terms_for).with("A000001").and_return(sample_terms)
        allow(LegislatorsCache::CongressTermHistory).to receive(:fetch).and_return(history)

        result = service.call
        entries = JSON.parse(result.changed_files.fetch(path))

        non_potus = entries.reject { |m| m["bioguideId"] == LegislatorsCache::POTUS_BIOGUIDE_ID }
        expect(non_potus).not_to be_empty
        expect(non_potus).to all(include("termsSource" => LegislatorsCache::CongressTermHistory::SOURCE_NAME))

        potus_result = entries.find { |m| m["bioguideId"] == LegislatorsCache::POTUS_BIOGUIDE_ID }
        expect(potus_result).to be_present
        expect(potus_result).not_to have_key("termsSource")
      end

      it "preserves a stored President entry first in output, unchanged, with no termsSource and not marked departed" do
        baseline_file.write(JSON.generate([potus_entry, {"bioguideId" => "A000001"}]))
        baseline_file.flush

        potus_legislator = create(:legislator, sway_locale: sway_locale, external_id: LegislatorsCache::POTUS_BIOGUIDE_ID, first_name: "Joseph", last_name: "Biden")
        district = District.find_or_create_by!(name: "US0", sway_locale: sway_locale)
        create(:legislator_term, legislator: potus_legislator, district: district, term_start_year: Date.current.year - 1, term_end_year: Date.current.year + 1)

        allow(adapter).to receive(:fetch_roster).and_return([{"bioguideId" => "A000001", "name" => "Ada Member"}])

        result = service.call
        entries = JSON.parse(result.changed_files.fetch(path))
        first_entry = entries.first

        expect(first_entry["bioguideId"]).to eq(LegislatorsCache::POTUS_BIOGUIDE_ID)
        expect(first_entry).to eq(potus_entry)
        expect(first_entry["currentMember"]).not_to be(false)
        expect(first_entry).not_to have_key("termsSource")
      end
    end
  end

  describe "#merge_stored_fields" do
    let(:sway_locale) { create(:sway_locale, :baltimore) }
    let(:service) { LegislatorsCache::TestRefresh.new(sway_locale) }
    let(:baseline) { Tempfile.new(["stored-roster", ".json"]) }
    let(:baseline_path) { baseline.path || raise("Roster fixture has no path") }
    let(:person) { {"external_id" => "seat-1", "first_name" => "Jane", "last_name" => "Smith"} }
    let(:stored) { [person.merge("photoUrl" => "stored.jpg", "twitter" => "stored", "email" => "old@example.test")] }

    before do
      baseline.write(JSON.generate(stored))
      baseline.flush
      allow(service).to receive(:canonical_seed_path).and_return(baseline_path)
    end

    after { baseline.close! }

    # @lat: [[current-legislator-term#Missing source fields preserve stored roster values]]
    it "preserves every absent field without adding absent people" do
      expect(service.send(:merge_stored_fields, [person])).to eq(stored)
      expect(service.send(:merge_stored_fields, [])).to eq([])
    end

    it "does not call roster_source on rules during roster_identity or stored_fields_for" do
      rules = double(
        "JurisdictionRules",
        roster_rules: {engine: :curated},
        roster_retrieval: nil,
        roster_parsing: nil
      )
      expect(rules).not_to receive(:roster_source)
      allow(sway_locale).to receive(:jurisdiction_rules).and_return(rules)

      service.send(:roster_identity, person)
      service.send(:stored_fields_for, stored.first, person)
    end

    it "resolves identity using rules.roster_parsing before engine" do
      rules = instance_double(
        SwayLocale::JurisdictionRules,
        roster_rules: {parsing: "open_states", engine: "curated"},
        roster_parsing: "open_states"
      )
      allow(sway_locale).to receive(:jurisdiction_rules).and_return(rules)

      identity = service.send(:roster_identity, {"id" => "os-123"})
      expect(identity.value).to eq("os-123")
      expect(identity.source).to eq("openstates")
    end

    it "does not transfer details to a successor or an unnamed seat" do
      successor = person.merge("first_name" => "Other")
      unnamed = person.merge("first_name" => "", "last_name" => "")
      expect(service.send(:merge_stored_fields, [successor, unnamed])).to eq([successor, unnamed])
    end

    it "matches normalized names within the same seat" do
      incoming = person.merge("first_name" => "JANE")
      expect(service.send(:merge_stored_fields, [incoming]).first).to eq(stored.first.merge(incoming))
    end

    it "honors explicit nil, blank, false, and empty arrays" do
      incoming = person.merge("photoUrl" => nil, "twitter" => "", "email" => false, "links" => [])
      expect(service.send(:merge_stored_fields, [incoming]).first).to eq(incoming)
    end

    context "with competing legacy photo aliases" do
      let(:stored) { [person.merge("photoURL" => "old.jpg", "photo_url" => "also-old.jpg")] }

      it "removes aliases when a lower-precedence spelling updates or clears the photo" do
        [nil, "new.jpg"].each do |photo|
          incoming = person.merge("photoUrl" => photo)
          merged = service.send(:merge_stored_fields, [incoming])
          expect(merged).to eq([incoming])
          expect(SeedPreparers::Legislators::Sway.new(merged.first, sway_locale).photo_url).to eq(photo)
        end
      end
    end

    context "with Congress members" do
      let(:sway_locale) { create(:sway_locale, :congress) }
      let(:person) { {"bioguideId" => "A000001"} }
      let(:stored) do
        [person.merge("depiction" => {"imageUrl" => "stored.jpg", "attribution" => "old"},
          "terms" => {"item" => [{"startYear" => 2000}], "source" => "history"}, "twitter" => "stored")]
      end

      it "preserves nested missing fields while replacing emitted arrays and values" do
        incoming = person.merge("depiction" => {"attribution" => "new"}, "terms" => {"item" => []})
        expect(service.send(:merge_stored_fields, [incoming])).to eq([
          person.merge("depiction" => {"imageUrl" => "stored.jpg", "attribution" => "new"},
            "terms" => {"item" => [], "source" => "history"}, "twitter" => "stored")
        ])
      end
    end

    context "with OpenStates members" do
      let(:sway_locale) { create(:sway_locale, :maryland) }
      let(:person) { {"id" => "ocd-person/example", "given_name" => "Jane", "family_name" => "Smith"} }
      let(:stored) { [person.merge("image" => "stored.jpg", "twitter" => "stored")] }

      it "matches the published person ID independently of name changes" do
        incoming = person.merge("name" => "Updated name")
        expect(service.send(:merge_stored_fields, [incoming]).first).to eq(stored.first.merge(incoming))
      end
    end

    it "returns new source entries unchanged when no baseline exists" do
      File.unlink(baseline_path)
      expect(service.send(:merge_stored_fields, [person])).to eq([person])
    end

    it "rejects duplicate stored identities instead of guessing which details to retain" do
      File.write(baseline_path, JSON.generate(stored + stored))
      expect { service.send(:merge_stored_fields, [person]) }.to raise_error(ArgumentError, /duplicate identities/)
    end

    it "rejects malformed baseline JSON instead of replacing it with incomplete data" do
      File.write(baseline_path, "invalid")
      expect { service.send(:merge_stored_fields, [person]) }.to raise_error(JSON::ParserError)
      File.write(baseline_path, "{}")
      expect { service.send(:merge_stored_fields, [person]) }.to raise_error(ArgumentError, /array of objects/)
    end
  end

  describe "#changed? (private)" do
    it "returns true when the existing file does not exist" do
      sway_locale = create(:sway_locale)
      service = LegislatorsCache::TestRefresh.new(sway_locale)
      Tempfile.create("new.json") do |new_file|
        new_file.write('{"a":1}')
        new_file.flush
        missing_path = "/tmp/this_file_does_not_exist_#{SecureRandom.hex}.json"

        expect(service.send(:changed?, new_file.path, missing_path)).to be true
      end
    end

    it "returns false when both files have identical contents" do
      sway_locale = create(:sway_locale)
      service = LegislatorsCache::TestRefresh.new(sway_locale)
      Tempfile.create("new.json") do |new_file|
        Tempfile.create("existing.json") do |existing_file|
          [new_file, existing_file].each { |f|
            f.write('{"same":true}')
            f.flush
          }

          expect(service.send(:changed?, new_file.path, existing_file.path)).to be false
        end
      end
    end

    it "returns true when the files differ" do
      sway_locale = create(:sway_locale)
      service = LegislatorsCache::TestRefresh.new(sway_locale)
      Tempfile.create("new.json") do |new_file|
        Tempfile.create("existing.json") do |existing_file|
          new_file.write('{"new":1}')
          new_file.flush
          existing_file.write('{"old":1}')
          existing_file.flush

          expect(service.send(:changed?, new_file.path, existing_file.path)).to be true
        end
      end
    end

    # The generator writes 2-space JSON.pretty_generate output; repo seed
    # files are prettier-formatted at 4-space. Raw-byte comparison would mark
    # every run changed, so changed? compares parsed data.
    it "returns false when the JSON is semantically identical but formatted differently" do
      sway_locale = create(:sway_locale)
      service = LegislatorsCache::TestRefresh.new(sway_locale)
      Tempfile.create("new.json") do |new_file|
        Tempfile.create("existing.json") do |existing_file|
          data = [{"id" => "x", "nested" => {"a" => 1, "b" => 2}}]
          new_file.write(JSON.generate(data)) # compact
          new_file.flush
          existing_file.write(JSON.pretty_generate(data).gsub("  ", "    ")) # 4-space pretty
          existing_file.flush

          expect(service.send(:changed?, new_file.path, existing_file.path)).to be false
        end
      end
    end

    it "returns false when member hashes differ only by updateDate under congress_dot_gov parsing" do
      sway_locale = create(:sway_locale, :congress)
      service = described_class.new(sway_locale)
      Tempfile.create("new.json") do |new_file|
        Tempfile.create("existing.json") do |existing_file|
          new_data = [{"bioguideId" => "A0001", "name" => "Alice", "updateDate" => "2026-10-14"}]
          existing_data = [{"bioguideId" => "A0001", "name" => "Alice", "updateDate" => "2026-10-07"}]

          new_file.write(JSON.generate(new_data))
          new_file.flush
          existing_file.write(JSON.generate(existing_data))
          existing_file.flush

          expect(service.send(:changed?, new_file.path, existing_file.path)).to be false
        end
      end
    end
  end

  describe "#freshness_check_passes? (private)" do
    it "returns true when legislators_cache_fetched_at is nil (never fetched)" do
      sway_locale = create(:sway_locale)
      sway_locale.update_columns(legislators_cache_fetched_at: nil)
      service = LegislatorsCache::TestRefresh.new(sway_locale)
      expect(service.send(:freshness_check_passes?)).to be true
    end

    it "returns false when fetched recently (within the staleness window)" do
      sway_locale = create(:sway_locale)
      sway_locale.update_columns(legislators_cache_fetched_at: 2.days.ago)
      service = LegislatorsCache::TestRefresh.new(sway_locale)
      expect(service.send(:freshness_check_passes?)).to be false
    end

    it "returns true when fetched older than the staleness window" do
      sway_locale = create(:sway_locale)
      sway_locale.update_columns(legislators_cache_fetched_at: 8.days.ago)
      service = LegislatorsCache::TestRefresh.new(sway_locale)
      expect(service.send(:freshness_check_passes?)).to be true
    end

    # A locale stamped last week is a few seconds short of 7 days old when
    # the next weekly run starts. The 6-day window has to let it through, or
    # the schedule quietly becomes every other week.
    it "returns true for a locale fetched just under a week ago (weekly cadence)" do
      sway_locale = create(:sway_locale)
      sway_locale.update_columns(legislators_cache_fetched_at: (7.days - 1.minute).ago)
      service = LegislatorsCache::TestRefresh.new(sway_locale)
      expect(service.send(:freshness_check_passes?)).to be true
    end

    it "returns true when force: true regardless of fetched_at" do
      sway_locale = create(:sway_locale)
      sway_locale.update_columns(legislators_cache_fetched_at: 1.hour.ago)
      service = LegislatorsCache::TestRefresh.new(sway_locale, force: true)
      expect(service.send(:freshness_check_passes?)).to be true
    end
  end

  describe "#upload_json_to_gcs (private)" do
    # @lat: [[jurisdiction-rules-design#Why JurisdictionRules exists, and how it is organized#Why the legislators-cache GCS upload path is named from the locale]]
    it "uploads to both canonical and archive GCS paths, named for the locale" do
      sway_locale = create(:sway_locale, :congress)
      service = LegislatorsCache::TestRefresh.new(sway_locale)
      json_file = Tempfile.new(["test", ".json"])
      begin
        json_file.write('{"test":true}')
        json_file.flush

        uploaded = [] #: Array[Hash[Symbol, String]]
        allow(service).to receive(:upload_file) do |**kwargs|
          captured = kwargs #: Hash[Symbol, String]
          uploaded << captured
        end

        service.send(:upload_json_to_gcs, json_file.path)

        expect(uploaded.size).to eq(2)
        canonical = uploaded.find { |u| !u[:bucket_file_path].include?("archive") }
        archive = uploaded.find { |u| u[:bucket_file_path].include?("archive") }

        expect(canonical).not_to be_nil
        expect(canonical[:bucket_file_path]).to eq("seeds/legislators/#{sway_locale.name}.json") if canonical
        expect(canonical[:bucket_name]).to eq(SwayGoogleCloudStorage::BUCKETS[:ASSETS]) if canonical

        expect(archive).not_to be_nil
        if archive
          expect(archive[:bucket_file_path])
            .to match(%r{\Aseeds/legislators/archive/#{Regexp.escape(sway_locale.name)}-\d{8}T\d{6}Z\.json\z})
        end
      ensure
        json_file.unlink
      end
    end
  end
end
