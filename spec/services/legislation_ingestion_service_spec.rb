require "rails_helper"

# Exercises #upsert_bill_payload, the per-bill save FetchBillsService
# drives, against parsed BillPayload fixtures — ActiveRecord writes only.
# The old batch #call and Python path are gone.

RSpec.describe LegislationIngestionService, :vcr do
  # The ingestion service defaults to Baltimore when the payload omits
  # `sway_locale_external_id`. Tests therefore seed that locale so
  # `SwayLocale.all.find { |l| l.name == ... }` has a match.
  let!(:baltimore) do
    create(
      :sway_locale,
      city: "baltimore",
      state: "maryland",
      country: "United States"
    )
  end
  # The Council President stands in as sponsor for bills with none. A
  # legislator's title now comes from their term, so this needs a matching
  # legislator_term for the fallback lookup.
  let!(:council_president) do
    district = create(:district, sway_locale: baltimore)
    legislator =
      create(
        :legislator,
        district: district,
        title: "Council President",
        active: true,
        first_name: "Zeke",
        last_name: "Cohen"
      )
    create(:legislator_term, legislator:, district:, title: "Council President")
    legislator
  end

  describe "#upsert_bill_payload" do
    let(:run) { LegislationPipelineRun.create!(remote_run_id: "abc", stages: ["fetch-bills"]) }

    # Flat BillPayload shape: bill attributes at top level, provisioning
    # nested — matches build_payloads.py. sway_locale_id is NOT on the wire;
    # Rails resolves it from locale context.
    let(:payload) do
      {
        "run_id" => "abc",
        "bills" => [
          {
            "external_id" => "24-0001",
            "title" => "Test Bill",
            "chamber" => "council",
            "category" => "Ordinance",
            "status" => "committee",
            "link" => "https://baltimore.legistar.com/LegislationDetail.aspx?ID=1",
            "summary" => "Summary pending",
            "introduced_date_time_utc" => "2026-01-01T00:00:00Z",
            "active" => true,
            "provisioning" => {
              "diff_content" => "fixture diff",
              "hearings_fetched_at" => "2026-04-15T00:00:00Z"
            }
          }
        ]
      }
    end

    it "wraps all writes in an ActiveRecord transaction" do
      # at_least(:once): the new Bill's after_create_commit hook runs
      # create_default_bill_score, whose create_or_find_by! opens its own
      # nested transaction underneath the service's.
      expect(ActiveRecord::Base).to receive(:transaction).at_least(:once).and_call_original
      described_class.new(run: run).upsert_bill_payload(payload["bills"].first)
    end

    it "creates a Bill when one does not exist, using the Council President fallback" do
      expect { described_class.new(run: run).upsert_bill_payload(payload["bills"].first) }
        .to change { Bill.count }.by(1)

      bill = Bill.find_by(external_id: "24-0001", sway_locale: baltimore)
      expect(bill.title).to eq("Test Bill")
      expect(bill.legislator).to eq(council_president)
    end

    it "updates an existing Bill's title without creating a new row" do
      existing_bill = create(:bill, external_id: "24-0001", sway_locale: baltimore)
      expect { described_class.new(run: run).upsert_bill_payload(payload["bills"].first) }
        .not_to change { Bill.count }
      expect(existing_bill.reload.title).to eq("Test Bill")
    end

    it "updates BillLlmProvisioning diff_content and hearings_fetched_at without touching llm_summary" do
      bill = create(:bill, external_id: "24-0001", sway_locale: baltimore)
      create(:bill_llm_provisioning, bill: bill, llm_summary: "existing")
      described_class.new(run: run).upsert_bill_payload(payload["bills"].first)
      bill.bill_llm_provisioning.reload
      expect(bill.bill_llm_provisioning.diff_content).to eq("fixture diff")
      expect(bill.bill_llm_provisioning.llm_summary).to eq("existing")
    end

    # @lat: [[legistar-matter-status-mapping#Ingestion pipeline status boundary]]
    it "persists the supplied status when the payload specifies a canonical status" do
      passed_payload = payload["bills"].first.merge(
        "external_id" => "24-PASS",
        "status" => "passed",
        "link" => "https://baltimore.legistar.com/LegislationDetail.aspx?ID=24-PASS"
      )
      failed_payload = payload["bills"].first.merge(
        "external_id" => "24-FAIL",
        "status" => "failed",
        "link" => "https://baltimore.legistar.com/LegislationDetail.aspx?ID=24-FAIL"
      )

      described_class.new(run: run).upsert_bill_payload(passed_payload)
      described_class.new(run: run).upsert_bill_payload(failed_payload)

      expect(Bill.find_by!(external_id: "24-PASS", sway_locale: baltimore).status).to eq("passed")
      expect(Bill.find_by!(external_id: "24-FAIL", sway_locale: baltimore).status).to eq("failed")
    end

    it "updates an existing Bill's status when the payload brings an updated status" do
      existing = create(:bill, external_id: "24-STATUS-UPDATE", sway_locale: baltimore, status: "committee")
      update_payload = payload["bills"].first.merge(
        "external_id" => "24-STATUS-UPDATE",
        "status" => "passed"
      )

      described_class.new(run: run).upsert_bill_payload(update_payload)
      expect(existing.reload.status).to eq("passed")
    end

    it "does not overwrite an existing non-committee status when payload status is nil" do
      existing = create(:bill, external_id: "24-PRESERVE-STATUS", sway_locale: baltimore, status: "passed")
      unsourced_payload = payload["bills"].first.merge(
        "external_id" => "24-PRESERVE-STATUS",
        "status" => nil
      )

      described_class.new(run: run).upsert_bill_payload(unsourced_payload)
      expect(existing.reload.status).to eq("passed")
    end
  end

  describe "cross-boundary BillPayload round-trip contract" do
    # The exact shape build_payloads.py::BillPayload.model_dump(mode='json')
    # emits. Any change here must be mirrored in that Python class and its
    # test_payload_contracts.py fixture.
    let(:python_bill_payload_json) do
      {
        "run_id" => "round-trip-test",
        "bills" => [
          {
            "external_id" => "24-ROUNDTRIP",
            "title" => "Round Trip Test Bill",
            "chamber" => "council",
            "category" => "Ordinance",
            "status" => "committee",
            "link" => "https://baltimore.legistar.com/LegislationDetail.aspx?ID=2",
            "summary" => "Summary pending",
            "introduced_date_time_utc" => "2026-01-01T00:00:00Z",
            "active" => true,
            "provisioning" => {
              "diff_content" => "round-trip diff",
              "hearings_fetched_at" => "2026-04-15T00:00:00Z"
            }
          }
        ]
      }
    end
    let(:roundtrip_run) { LegislationPipelineRun.create!(remote_run_id: "rt", stages: ["fetch-bills"]) }

    it "upsert_bill reads title from top-level bill_data (flat shape) and resolves locale server-side" do
      deserialized = JSON.parse(python_bill_payload_json.to_json)

      # These checks guard against the BillPayload shape changing. If the Python
      # side renames these keys, the spec fails loudly here instead of quietly
      # saving nils further downstream.
      expect(deserialized).to have_key("run_id")
      expect(deserialized).to have_key("bills")
      expect(deserialized["bills"].first).to have_key("external_id")

      described_class.new(run: roundtrip_run).upsert_bill_payload(deserialized["bills"].first)

      bill = Bill.find_by(external_id: "24-ROUNDTRIP", sway_locale: baltimore)
      expect(bill).to be_present,
        "upsert_bill failed to resolve Baltimore locale — flat shape contract broke"
      expect(bill.title).to eq("Round Trip Test Bill"),
        "upsert_bill read bill_data['title'] as nil — BillPayload is probably nesting under 'bill'"
    end

    it "upsert_provisioning reads diff_content from nested provisioning sub-dict" do
      deserialized = JSON.parse(python_bill_payload_json.to_json)
      described_class.new(run: roundtrip_run).upsert_bill_payload(deserialized["bills"].first)

      bill = Bill.find_by(external_id: "24-ROUNDTRIP", sway_locale: baltimore) #: Bill
      expect(bill.bill_llm_provisioning.diff_content).to eq("round-trip diff"),
        "upsert_provisioning failed to read bill_data['provisioning']['diff_content'] — provisioning nesting contract broke"
    end
  end

  describe "NOT NULL defaults on create" do
    let(:run) { LegislationPipelineRun.create!(remote_run_id: "nn", stages: ["fetch-bills"]) }
    # Minimal payload — omits every NOT NULL column except external_id.
    # Mirrors the fixture_mode=True path on the Python side.
    let(:minimal_payload) do
      {
        "bills" => [
          {
            "external_id" => "24-MIN",
            "provisioning" => {"diff_content" => "d"}
          }
        ]
      }
    end

    it "fills in NOT NULL / validates-presence columns when the payload omits them" do
      expect { described_class.new(run: run).upsert_bill_payload(minimal_payload["bills"].first) }
        .to change { Bill.count }.by(1)

      bill = Bill.find_by!(external_id: "24-MIN", sway_locale: baltimore)
      expect(bill.category).to eq("Ordinance")
      expect(bill.chamber).to eq("council")
      expect(bill.title).to eq("24-MIN")
      expect(bill.summary).to eq("Summary pending")
      expect(bill.status).to eq("committee")
      expect(bill.link).to be_nil
      expect(bill.introduced_date_time_utc).to be_within(5.seconds).of(Time.current)
    end
  end

  describe "concurrent upsert race recovery" do
    let(:run) { LegislationPipelineRun.create!(remote_run_id: "rc", stages: ["fetch-bills"]) }
    let(:payload) do
      {
        "bills" => [
          {
            "external_id" => "24-RACE",
            "title" => "Updated Title from Worker B"
          }
        ]
      }
    end

    # @lat: [[bill-session-archiving-tests#Bill session archive tests#Ingestion recovery checks the archive once]]
    it "checks the retained archive identity once during live uniqueness recovery" do
      existing = create(:bill, external_id: "24-RACE", sway_locale: baltimore, title: "Original Title")
      service = described_class.new(run: run)
      bill_data = payload["bills"].first
      identity = {external_id: "24-RACE", sway_locale: baltimore}
      expect(Bill).to receive(:find_or_initialize_by).with(identity).once
        .and_raise(ActiveRecord::RecordNotUnique, "UNIQUE constraint failed: bills.external_id")

      archive_reads = [] #: Array[String]
      result = nil #: Bill?
      subscriber = lambda do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        sql = event.payload[:sql]
        next unless sql.match?(/SELECT 1 AS one FROM "bills"/) && sql.include?('"bills"."archived_at" IS NOT NULL')

        binds = event.payload[:binds].to_h { |bind| [bind.name, bind.value_for_database] }
        next unless binds["external_id"] == bill_data["external_id"] && binds["sway_locale_id"] == baltimore.id

        archive_reads << sql
      end

      PipelineLocaleLock.with_locale(baltimore.id) do
        Bill.uncached do
          ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
            result = service.upsert_bill_payload(bill_data)
          end
        end
      end

      expect(archive_reads.length).to eq(1)
      expect(result).to eq(existing)
      expect(Bill.unscoped.where(identity).count).to eq(1)
      expect(existing.reload.archived_at).to be_nil
      expect(existing.title).to eq("Updated Title from Worker B")
    end

    it "rescues RecordNotUnique and updates the row the other worker just inserted" do
      # Worker A already inserted this row; worker B is about to lose the race.
      existing = create(
        :bill,
        external_id: "24-RACE",
        sway_locale: baltimore,
        title: "Original Title from Worker A"
      )

      # Stands in for worker B's stale read: find_or_initialize_by hands back
      # a new, unsaved record. Production raises RecordNotUnique at INSERT;
      # save! is stubbed to raise that directly.
      stale = Bill.new(external_id: "24-RACE", sway_locale: baltimore)
      allow(stale).to receive(:save!)
        .and_raise(ActiveRecord::RecordNotUnique, "UNIQUE constraint failed: bills.external_id")
      allow(Bill).to receive(:find_or_initialize_by)
        .with(external_id: "24-RACE", sway_locale: baltimore)
        .and_return(stale)

      expect { described_class.new(run: run).upsert_bill_payload(payload["bills"].first) }
        .not_to raise_error

      expect(Bill.where(external_id: "24-RACE", sway_locale: baltimore).count).to eq(1)
      expect(existing.reload.title).to eq("Updated Title from Worker B")
    end
  end

  describe "fallback legislator safety" do
    # Override the outer `let!(:council_president)` by NOT pre-seeding one.
    let!(:council_president) { nil }
    let(:run) { LegislationPipelineRun.create!(remote_run_id: "cp", stages: ["fetch-bills"]) }
    let(:payload) do
      {
        "bills" => [
          {"external_id" => "24-NO-CP", "title" => "Test Bill"}
        ]
      }
    end

    it "raises IngestionError rather than silently picking legislators.first" do
      # Seed a non-council-president legislator so `legislators.first` would
      # have returned something if the old fallback still existed.
      district = create(:district, sway_locale: baltimore)
      create(:legislator, district: district, title: "Council Member", active: true)

      expect { described_class.new(run: run).upsert_bill_payload(payload["bills"].first) }
        .to raise_error(LegislationIngestionService::IngestionError, /Council President/)
    end
  end

  # Written as a failing test first.
  describe "activity log emission from upsert_bill_payload rescue" do
    let!(:baltimore) do
      create(:sway_locale, city: "baltimore", state: "maryland", country: "United States")
    end
    let(:run) { create(:legislation_pipeline_run, :running) }
    let(:service) do
      described_class.new(run: run)
    end

    it "emits ingestion_failure entry and re-raises IngestionError when RecordInvalid is raised" do
      bill_data = {"external_id" => "24-FAIL-01", "title" => nil}
      # Force a RecordInvalid from upsert_bill by having the locale present
      # but an invalid bill (title is required).
      allow_any_instance_of(described_class).to receive(:upsert_bill)
        .and_raise(ActiveRecord::RecordInvalid.new(Bill.new))

      expect {
        expect {
          service.upsert_bill_payload(bill_data)
        }.to change { PipelineActivityLogEntry.where(event_type: "ingestion_failure").count }.by(1)
      }.to raise_error(LegislationIngestionService::IngestionError)
    end
  end

  # @lat: [[unlinked-bill-presentation#The absent shape eliminates sentinel leakage]]
  # @lat: [[legistar-detail-url-resolution#Ingestion pipeline integration and fallback elimination]]
  describe "#upsert_bill_payload — link persistence and fallback elimination" do
    let(:run) { LegislationPipelineRun.create!(remote_run_id: "link-test", stages: ["fetch-bills"]) }

    base_bill_data = {
      "external_id" => "24-LINK-TEST",
      "title" => "Link Test Bill",
      "chamber" => "council",
      "category" => "Ordinance",
      "status" => "committee",
      "introduced_date_time_utc" => "2026-01-01T00:00:00Z",
      "active" => true
    }.freeze

    it "persists canonical detail URL when payload provides a verified link" do
      canonical_link = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
      payload = base_bill_data.merge("link" => canonical_link)

      described_class.new(run: run).upsert_bill_payload(payload)

      bill = Bill.find_by!(external_id: "24-LINK-TEST", sway_locale: baltimore)
      expect(bill.link).to eq(canonical_link)
      expect(bill).to be_valid
    end

    it "persists nil link when payload provides explicit nil and never writes generic search address" do
      payload = base_bill_data.merge("link" => nil)

      described_class.new(run: run).upsert_bill_payload(payload)

      bill = Bill.find_by!(external_id: "24-LINK-TEST", sway_locale: baltimore)
      expect(bill.link).to be_nil
      expect(bill.link).not_to eq("https://baltimore.legistar.com/LegislationSearch.aspx")
      expect(bill).to be_valid
    end

    it "persists nil link when payload omits link key completely" do
      payload = base_bill_data.except("link")

      described_class.new(run: run).upsert_bill_payload(payload)

      bill = Bill.find_by!(external_id: "24-LINK-TEST", sway_locale: baltimore)
      expect(bill.link).to be_nil
      expect(bill).to be_valid
    end

    it "does not overwrite an existing bill's real link when update payload has link: nil" do
      canonical_link = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
      existing = create(:bill, external_id: "24-LINK-PRESERVE", sway_locale: baltimore, link: canonical_link)

      update_payload = base_bill_data.merge(
        "external_id" => "24-LINK-PRESERVE",
        "link" => nil
      )

      described_class.new(run: run).upsert_bill_payload(update_payload)
      expect(existing.reload.link).to eq(canonical_link)
    end

    it "updates an existing bill's link when update payload carries a new valid link" do
      old_link = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=101&GUID=OLD-GUID"
      new_link = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=202&GUID=NEW-GUID"
      existing = create(:bill, external_id: "24-LINK-UPDATE", sway_locale: baltimore, link: old_link)

      update_payload = base_bill_data.merge(
        "external_id" => "24-LINK-UPDATE",
        "link" => new_link
      )

      described_class.new(run: run).upsert_bill_payload(update_payload)
      expect(existing.reload.link).to eq(new_link)
    end

    it "saves multiple bills with link: nil or omitted link without collision while enforcing uniqueness on non-nil links" do
      service = described_class.new(run: run)

      (1..3).each do |i|
        service.upsert_bill_payload(base_bill_data.merge("external_id" => "CCB-UNLINKED-#{i}", "link" => nil))
        service.upsert_bill_payload(base_bill_data.except("link").merge("external_id" => "CCB-OMITTED-#{i}"))
      end

      expect(Bill.where(external_id: %w[CCB-UNLINKED-1 CCB-UNLINKED-2 CCB-UNLINKED-3 CCB-OMITTED-1 CCB-OMITTED-2 CCB-OMITTED-3]).pluck(:link)).to all(be_nil)

      shared_link = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=55555&GUID=SHARED-GUID"
      create(:bill, external_id: "CCB-DUPE-1", sway_locale: baltimore, link: shared_link)

      expect {
        service.upsert_bill_payload(base_bill_data.merge("external_id" => "CCB-DUPE-2", "link" => shared_link))
      }.to raise_error(LegislationIngestionService::IngestionError) do |err|
        expect(err.cause).to be_a(ActiveRecord::RecordInvalid)
        expect(err.cause.message).to include("Link has already been taken")
      end
    end

    it "strips legacy LegislationSearch.aspx links from on-disk metadata to nil on FetchBillsService#read_disk_metadatas" do
      Dir.mktmpdir("legacy_disk_meta") do |tmp|
        allow(Legislation::Paths).to receive(:root).and_return(Pathname.new(tmp))
        bill_dir = Legislation::Paths.bill_artifact_dir("CCB-LEGACY-DISK", sway_locale: baltimore.name)
        FileUtils.mkdir_p(bill_dir)
        File.write(bill_dir.join("metadata.json"), JSON.generate({
          external_id: "CCB-LEGACY-DISK",
          matter_id: 8888,
          title: "Legacy Disk Bill",
          introduction_date: "2025-01-15T00:00:00",
          bill_number: "CCB-LEGACY-DISK",
          matter_type: "Ordinance",
          status: "In Committee",
          link: "https://baltimore.legistar.com/LegislationSearch.aspx"
        }))

        disk_metadatas = FetchBillsService.new(run: run, mode: :reingest).send(:read_disk_metadatas)
        disk_metadata = disk_metadatas.find { |m| m[:external_id] == "CCB-LEGACY-DISK" }
        expect(disk_metadata).not_to be_nil
        expect(disk_metadata[:link]).to be_nil
      end
    end

    context "session mapping" do
      it "assigns the active legislative session when introduced date falls within active session bounds" do
        active_session = create(
          :legislative_session,
          :active,
          sway_locale: baltimore,
          name: "2024-2028 Council",
          start_date: Date.new(2024, 12, 5),
          end_date: Date.new(2028, 12, 5)
        )
        payload_item = {
          "external_id" => "24-0001",
          "title" => "Test Bill",
          "chamber" => "council",
          "category" => "Ordinance",
          "status" => "committee",
          "link" => "https://baltimore.legistar.com/LegislationDetail.aspx?ID=1",
          "summary" => "Summary pending",
          "introduced_date_time_utc" => "2025-06-01T00:00:00Z",
          "active" => true
        }
        described_class.new(run:).upsert_bill_payload(payload_item)
        bill = Bill.find_by!(external_id: "24-0001", sway_locale: baltimore)

        expect(bill.legislative_session).to eq(active_session)
        expect(bill.active).to be true
      end

      it "assigns a historical legislative session when introduced date falls within past session bounds" do
        past_session = create(
          :legislative_session,
          active: false,
          sway_locale: baltimore,
          name: "2020-2024 Council",
          start_date: Date.new(2020, 12, 5),
          end_date: Date.new(2024, 12, 4)
        )
        payload_item = {
          "external_id" => "24-0001",
          "title" => "Test Bill",
          "chamber" => "council",
          "category" => "Ordinance",
          "status" => "committee",
          "link" => "https://baltimore.legistar.com/LegislationDetail.aspx?ID=1",
          "summary" => "Summary pending",
          "introduced_date_time_utc" => "2022-03-15T00:00:00Z",
          "active" => true
        }
        described_class.new(run:).upsert_bill_payload(payload_item)
        bill = Bill.find_by!(external_id: "24-0001", sway_locale: baltimore)

        expect(bill.legislative_session).to eq(past_session)
        expect(bill.active).to be false
      end

      it "leaves legislative_session nil when introduced date falls outside all known session bounds" do
        payload_item = {
          "external_id" => "24-0001",
          "title" => "Test Bill",
          "chamber" => "council",
          "category" => "Ordinance",
          "status" => "committee",
          "link" => "https://baltimore.legistar.com/LegislationDetail.aspx?ID=1",
          "summary" => "Summary pending",
          "introduced_date_time_utc" => "2018-01-01T00:00:00Z",
          "active" => true
        }
        described_class.new(run:).upsert_bill_payload(payload_item)
        bill = Bill.find_by!(external_id: "24-0001", sway_locale: baltimore)

        expect(bill.legislative_session).to be_nil
      end

      it "persists an explicit legislative_session_id when provided in payload" do
        past_session = create(
          :legislative_session,
          active: false,
          sway_locale: baltimore,
          name: "2020-2024 Council",
          start_date: Date.new(2020, 12, 5),
          end_date: Date.new(2024, 12, 4)
        )
        payload_item = {
          "external_id" => "24-0001",
          "title" => "Test Bill",
          "chamber" => "council",
          "category" => "Ordinance",
          "status" => "committee",
          "link" => "https://baltimore.legistar.com/LegislationDetail.aspx?ID=1",
          "summary" => "Summary pending",
          "introduced_date_time_utc" => "2026-01-01T00:00:00Z",
          "legislative_session_id" => past_session.id,
          "active" => true
        }
        described_class.new(run:).upsert_bill_payload(payload_item)
        bill = Bill.find_by!(external_id: "24-0001", sway_locale: baltimore)

        expect(bill.legislative_session_id).to eq(past_session.id)
      end

      it "automatically infers and assigns legislative session from introduced_date_time_utc when legislative_session_id is blank" do
        active_session = create(
          :legislative_session,
          :active,
          sway_locale: baltimore,
          name: "2024-2028 Council",
          start_date: Date.new(2024, 12, 5),
          end_date: Date.new(2028, 12, 5)
        )

        [nil, "", "   "].each_with_index do |blank_val, idx|
          payload_item = {
            "external_id" => "24-BLANK-STR-#{idx}",
            "title" => "Blank Session Bill String Key #{idx}",
            "chamber" => "council",
            "category" => "Ordinance",
            "status" => "committee",
            "link" => "https://baltimore.legistar.com/LegislationDetail.aspx?ID=#{idx}",
            "summary" => "Summary pending",
            "introduced_date_time_utc" => "2025-06-01T00:00:00Z",
            "legislative_session_id" => blank_val,
            "active" => true
          }
          described_class.new(run:).upsert_bill_payload(payload_item)
          bill = Bill.find_by!(external_id: "24-BLANK-STR-#{idx}", sway_locale: baltimore)

          expect(bill.legislative_session).to eq(active_session)
          expect(bill.legislative_session_id).to eq(active_session.id)
        end

        # Also verify when legislative_session_id is passed as a blank symbol key or omitted
        [nil, ""].each_with_index do |blank_val, idx|
          payload_item = {
            "external_id" => "24-BLANK-SYM-#{idx}",
            "title" => "Blank Session Bill Symbol Key #{idx}",
            "chamber" => "council",
            "category" => "Ordinance",
            "status" => "committee",
            "link" => "https://baltimore.legistar.com/LegislationDetail.aspx?ID=10#{idx}",
            "summary" => "Summary pending",
            "introduced_date_time_utc" => "2025-06-01T00:00:00Z",
            :legislative_session_id => blank_val,
            "active" => true
          }
          described_class.new(run:).upsert_bill_payload(payload_item)
          bill = Bill.find_by!(external_id: "24-BLANK-SYM-#{idx}", sway_locale: baltimore)

          expect(bill.legislative_session).to eq(active_session)
          expect(bill.legislative_session_id).to eq(active_session.id)
        end

        # And verify when legislative_session_id key is omitted completely
        omitted_payload = {
          "external_id" => "24-BLANK-OMITTED",
          "title" => "Omitted Session Bill",
          "chamber" => "council",
          "category" => "Ordinance",
          "status" => "committee",
          "link" => "https://baltimore.legistar.com/LegislationDetail.aspx?ID=999",
          "summary" => "Summary pending",
          "introduced_date_time_utc" => "2025-06-01T00:00:00Z",
          "active" => true
        }
        described_class.new(run:).upsert_bill_payload(omitted_payload)
        omitted_bill = Bill.find_by!(external_id: "24-BLANK-OMITTED", sway_locale: baltimore)
        expect(omitted_bill.legislative_session).to eq(active_session)
        expect(omitted_bill.legislative_session_id).to eq(active_session.id)
      end

      it "falls back to Time.current and assigns current session when introduced_date_time_utc is invalid or nil" do
        active_session = create(
          :legislative_session,
          :active,
          sway_locale: baltimore,
          name: "Current Session",
          start_date: 1.year.ago.to_date,
          end_date: 1.year.from_now.to_date
        )

        ["not-a-valid-date", nil].each_with_index do |bad_date, idx|
          payload_item = {
            "external_id" => "24-BAD-DATE-#{idx}",
            "title" => "Bad Date Bill #{idx}",
            "chamber" => "council",
            "category" => "Ordinance",
            "status" => "committee",
            "link" => "https://baltimore.legistar.com/LegislationDetail.aspx?ID=#{900 + idx}",
            "summary" => "Summary pending",
            "introduced_date_time_utc" => bad_date,
            "active" => true
          }
          described_class.new(run:).upsert_bill_payload(payload_item)
          bill = Bill.find_by!(external_id: "24-BAD-DATE-#{idx}", sway_locale: baltimore)

          expect(bill.legislative_session).to eq(active_session)
          expect(bill.introduced_date_time_utc).to be_present
        end
      end

      it "updates an existing bill's session when introduced date changes across session boundary" do
        active_session = create(
          :legislative_session,
          :active,
          sway_locale: baltimore,
          name: "2024-2028 Council",
          start_date: Date.new(2024, 12, 5),
          end_date: Date.new(2028, 12, 5)
        )
        past_session = create(
          :legislative_session,
          active: false,
          sway_locale: baltimore,
          name: "2020-2024 Council",
          start_date: Date.new(2020, 12, 5),
          end_date: Date.new(2024, 12, 4)
        )
        payload_item = {
          "external_id" => "24-0001",
          "title" => "Test Bill",
          "chamber" => "council",
          "category" => "Ordinance",
          "status" => "committee",
          "link" => "https://baltimore.legistar.com/LegislationDetail.aspx?ID=1",
          "summary" => "Summary pending",
          "introduced_date_time_utc" => "2022-03-15T00:00:00Z",
          "active" => true
        }
        described_class.new(run:).upsert_bill_payload(payload_item)
        bill = Bill.find_by!(external_id: "24-0001", sway_locale: baltimore)
        expect(bill.legislative_session).to eq(past_session)

        updated_item = payload_item.merge(
          "introduced_date_time_utc" => "2025-06-01T00:00:00Z"
        )
        described_class.new(run:).upsert_bill_payload(updated_item)
        expect(bill.reload.legislative_session).to eq(active_session)
      end

      it "maps bill introduced exactly on session start_date boundary (00:00:00 and 23:59:59)" do
        session = create(
          :legislative_session,
          :active,
          sway_locale: baltimore,
          name: "2024-2028 Council",
          start_date: Date.new(2024, 12, 5),
          end_date: Date.new(2028, 12, 5)
        )

        payload_start_00 = {
          "external_id" => "CH-START-00",
          "title" => "Start 00",
          "introduced_date_time_utc" => "2024-12-05T00:00:00Z"
        }
        described_class.new(run:).upsert_bill_payload(payload_start_00)
        bill_00 = Bill.find_by!(external_id: "CH-START-00", sway_locale: baltimore)
        expect(bill_00.legislative_session).to eq(session)
        expect(bill_00.active).to be true

        payload_start_23 = {
          "external_id" => "CH-START-23",
          "title" => "Start 23",
          "introduced_date_time_utc" => "2024-12-05T23:59:59Z"
        }
        described_class.new(run:).upsert_bill_payload(payload_start_23)
        bill_23 = Bill.find_by!(external_id: "CH-START-23", sway_locale: baltimore)
        expect(bill_23.legislative_session).to eq(session)
      end

      it "maps bill introduced exactly on session end_date boundary (00:00:00 and 23:59:59)" do
        session = create(
          :legislative_session,
          :active,
          sway_locale: baltimore,
          name: "2024-2028 Council",
          start_date: Date.new(2024, 12, 5),
          end_date: Date.new(2028, 12, 5)
        )

        payload_end_00 = {
          "external_id" => "CH-END-00",
          "title" => "End 00",
          "introduced_date_time_utc" => "2028-12-05T00:00:00Z"
        }
        described_class.new(run:).upsert_bill_payload(payload_end_00)
        bill_00 = Bill.find_by!(external_id: "CH-END-00", sway_locale: baltimore)
        expect(bill_00.legislative_session).to eq(session)

        payload_end_23 = {
          "external_id" => "CH-END-23",
          "title" => "End 23",
          "introduced_date_time_utc" => "2028-12-05T23:59:59Z"
        }
        described_class.new(run:).upsert_bill_payload(payload_end_23)
        bill_23 = Bill.find_by!(external_id: "CH-END-23", sway_locale: baltimore)
        expect(bill_23.legislative_session).to eq(session)
      end

      it "leaves legislative_session nil for bill introduced 1 day before start_date" do
        create(
          :legislative_session,
          :active,
          sway_locale: baltimore,
          name: "2024-2028 Council",
          start_date: Date.new(2024, 12, 5),
          end_date: Date.new(2028, 12, 5)
        )

        payload_item = {
          "external_id" => "CH-BEFORE-START",
          "title" => "Before Start",
          "introduced_date_time_utc" => "2024-12-04T23:59:59Z"
        }
        described_class.new(run:).upsert_bill_payload(payload_item)
        bill = Bill.find_by!(external_id: "CH-BEFORE-START", sway_locale: baltimore)
        expect(bill.legislative_session).to be_nil
        expect(bill.legislative_session_id).to be_nil
      end

      it "leaves legislative_session nil for bill introduced 1 day after end_date" do
        create(
          :legislative_session,
          :active,
          sway_locale: baltimore,
          name: "2024-2028 Council",
          start_date: Date.new(2024, 12, 5),
          end_date: Date.new(2028, 12, 5)
        )

        payload_item = {
          "external_id" => "CH-AFTER-END",
          "title" => "After End",
          "introduced_date_time_utc" => "2028-12-06T00:00:00Z"
        }
        described_class.new(run:).upsert_bill_payload(payload_item)
        bill = Bill.find_by!(external_id: "CH-AFTER-END", sway_locale: baltimore)
        expect(bill.legislative_session).to be_nil
        expect(bill.legislative_session_id).to be_nil
      end

      it "honors explicit legislative_session_id override even when introduced date falls in another session" do
        past_session = create(
          :legislative_session,
          active: false,
          sway_locale: baltimore,
          name: "2020-2024 Council",
          start_date: Date.new(2020, 12, 5),
          end_date: Date.new(2024, 12, 4)
        )
        create(
          :legislative_session,
          :active,
          sway_locale: baltimore,
          name: "2024-2028 Council",
          start_date: Date.new(2024, 12, 5),
          end_date: Date.new(2028, 12, 5)
        )

        payload_item = {
          "external_id" => "CH-OVERRIDE",
          "title" => "Override",
          "introduced_date_time_utc" => "2025-06-01T00:00:00Z",
          "legislative_session_id" => past_session.id
        }
        described_class.new(run:).upsert_bill_payload(payload_item)
        bill = Bill.find_by!(external_id: "CH-OVERRIDE", sway_locale: baltimore)
        expect(bill.legislative_session_id).to eq(past_session.id)
        expect(bill.legislative_session).to eq(past_session)
        expect(bill.active).to be false
      end

      it "correctly resolves consecutive sessions at all boundaries and midpoints" do
        s1 = create(
          :legislative_session,
          active: false,
          sway_locale: baltimore,
          name: "Term 2016-2020",
          start_date: Date.new(2016, 12, 5),
          end_date: Date.new(2020, 12, 4)
        )
        s2 = create(
          :legislative_session,
          active: false,
          sway_locale: baltimore,
          name: "Term 2020-2024",
          start_date: Date.new(2020, 12, 5),
          end_date: Date.new(2024, 12, 4)
        )
        s3 = create(
          :legislative_session,
          :active,
          sway_locale: baltimore,
          name: "Term 2024-2028",
          start_date: Date.new(2024, 12, 5),
          end_date: Date.new(2028, 12, 5)
        )

        test_cases = [
          {date: "2016-12-05T00:00:00Z", expected: s1, ext_id: "T1-START"},
          {date: "2018-06-15T12:00:00Z", expected: s1, ext_id: "T1-MID"},
          {date: "2020-12-04T23:59:59Z", expected: s1, ext_id: "T1-END"},
          {date: "2020-12-05T00:00:00Z", expected: s2, ext_id: "T2-START"},
          {date: "2022-07-04T12:00:00Z", expected: s2, ext_id: "T2-MID"},
          {date: "2024-12-04T23:59:59Z", expected: s2, ext_id: "T2-END"},
          {date: "2024-12-05T00:00:00Z", expected: s3, ext_id: "T3-START"},
          {date: "2026-03-01T12:00:00Z", expected: s3, ext_id: "T3-MID"},
          {date: "2028-12-05T23:59:59Z", expected: s3, ext_id: "T3-END"}
        ]

        test_cases.each do |tc|
          described_class.new(run:).upsert_bill_payload({
            "external_id" => tc[:ext_id],
            "title" => "Bill #{tc[:ext_id]}",
            "introduced_date_time_utc" => tc[:date]
          })
          bill = Bill.find_by!(external_id: tc[:ext_id], sway_locale: baltimore)
          expect(bill.legislative_session).to eq(tc[:expected])
        end
      end

      it "gracefully sets legislative_session to nil without error when locale has no sessions" do
        payload_item = {
          "external_id" => "CH-ZERO-SESSIONS",
          "title" => "No Sessions Bill",
          "introduced_date_time_utc" => "2025-06-01T00:00:00Z"
        }
        described_class.new(run:).upsert_bill_payload(payload_item)
        bill = Bill.find_by!(external_id: "CH-ZERO-SESSIONS", sway_locale: baltimore)
        expect(bill.legislative_session).to be_nil
        expect(bill.legislative_session_id).to be_nil
      end

      it "isolates session mapping strictly to the bill's sway_locale" do
        state_locale = create(:sway_locale, :maryland)
        delegate_district = create(:district, sway_locale: state_locale)
        delegate_leg = create(:legislator, district: delegate_district, title: "Delegate", active: true)
        create(:legislator_term, legislator: delegate_leg, district: delegate_district, title: "Delegate")

        allow(SwayLocale::PipelineSponsorRegistry).to receive(:for).and_call_original
        allow(SwayLocale::PipelineSponsorRegistry).to receive(:for).with(state_locale.name, any_args).and_return({
          term_title: "Delegate",
          role: "delegate"
        })

        state_session = create(
          :legislative_session,
          :active,
          sway_locale: state_locale,
          name: "Maryland State Session 2023-2027",
          start_date: Date.new(2023, 1, 1),
          end_date: Date.new(2027, 1, 1)
        )

        described_class.new(run:).upsert_bill_payload({
          "external_id" => "CH-BALT-OUTSIDE",
          "sway_locale_external_id" => baltimore.name,
          "introduced_date_time_utc" => "2023-06-01T00:00:00Z"
        })
        balt_bill = Bill.find_by!(external_id: "CH-BALT-OUTSIDE", sway_locale: baltimore)
        expect(balt_bill.legislative_session).to be_nil

        described_class.new(run:).upsert_bill_payload({
          "external_id" => "CH-STATE-INSIDE",
          "sway_locale_external_id" => state_locale.name,
          "introduced_date_time_utc" => "2023-06-01T00:00:00Z"
        })
        state_bill = Bill.find_by!(external_id: "CH-STATE-INSIDE", sway_locale: state_locale)
        expect(state_bill.legislative_session).to eq(state_session)
      end
    end
  end

  describe "#resolve_chamber" do
    let(:service) { described_class.new }
    let(:maryland) do
      create(
        :sway_locale,
        city: "maryland",
        state: "maryland",
        country: "United States"
      )
    end

    context "when locale defines declarative chamber_patterns" do
      it "resolves house chamber for matching bill external_id" do
        expect(service.send(:resolve_chamber, {"external_id" => "HB 101"}, maryland)).to eq("house")
        expect(service.send(:resolve_chamber, {"external_id" => "HJ 1"}, maryland)).to eq("house")
        expect(service.send(:resolve_chamber, {"external_id" => "hb101"}, maryland)).to eq("house")
      end

      it "resolves senate chamber for matching bill external_id" do
        expect(service.send(:resolve_chamber, {"external_id" => "SB 202"}, maryland)).to eq("senate")
        expect(service.send(:resolve_chamber, {"external_id" => "SJ 5"}, maryland)).to eq("senate")
        expect(service.send(:resolve_chamber, {"external_id" => "sb202"}, maryland)).to eq("senate")
      end

      it "falls back to default_bill_chamber when external_id does not match any pattern" do
        expect(service.send(:resolve_chamber, {"external_id" => "UNKNOWN-999"}, maryland)).to eq("house")
      end

      it "falls back to default_bill_chamber when external_id is blank" do
        expect(service.send(:resolve_chamber, {"external_id" => ""}, maryland)).to eq("house")
      end
    end

    context "when locale does not define chamber_patterns" do
      it "falls back to default_bill_chamber" do
        expect(service.send(:resolve_chamber, {"external_id" => "24-0001"}, baltimore)).to eq("council")
      end
    end
  end
end
