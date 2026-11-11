# frozen_string_literal: true

require "rails_helper"

# Specs for FetchHearingsService. Like fetch_bills_service_spec.rb, overrides
# VCR's cassette dir here in the spec rather than globally.
module FetchHearingsServiceSpecHelpers
  HEARINGS_ROOT = LegislationTestArtifacts.root_for("fetch_hearings_service").freeze
  BILLS_RAW_ROOT = LegislationTestArtifacts.root_for("fetch_hearings_bills_raw").freeze
  # Keeps the download/extraction loop's attachment writes inside tmp/, not
  # the repo's own legislation/attachments/ dir — one level down, under the
  # bill's sway_locale.
  ATTACHMENTS_ROOT = LegislationTestArtifacts.root_for("fetch_hearings_attachments").freeze
  CASSETTE_DIR = Rails.root.join("spec", "fixtures", "vcr_cassettes").to_s.freeze
  LEGISTAR_BASE_URL = "https://webapi.legistar.com/v1"
  MATTER_ID = 12_345

  # Takes the BILL, not its external_id alone: metadata.json sits at
  # bills/raw/<sway_locale>/<external_id>/, since a Bill is unique on
  # (external_id, sway_locale_id) together.
  def self.write_bill_metadata(bill, matter_id)
    path = Legislation::Paths.bill_metadata_file(bill.external_id, sway_locale: bill.sway_locale.name)
    path.dirname.mkpath
    path.write(
      JSON.pretty_generate({"external_id" => bill.external_id, "matter_id" => matter_id})
    )
  end

  # Where FetchHearingsService#write_artifact puts one bill's hearings JSON.
  def self.hearings_path(bill)
    Legislation::Paths.hearings_file(bill.external_id, sway_locale: bill.sway_locale.name)
  end
end

RSpec.describe FetchHearingsService do
  include ActiveSupport::Testing::TimeHelpers

  let(:bill) { create(:bill, external_id: "TEST-100", sway_locale: create(:sway_locale, :baltimore)) }
  let(:matter_id_int) { FetchHearingsServiceSpecHelpers::MATTER_ID }

  # The path segment keeping this bill's files apart from another
  # jurisdiction's, read off the bill rather than hard-coded, so a
  # different-locale example gets that locale's directory.
  let(:sway_locale_name) { bill.sway_locale.name }

  # Where #write_artifact puts this bill's hearings JSON:
  # hearings/<sway_locale>/<external_id>.json.
  let(:hearings_artifact) { FetchHearingsServiceSpecHelpers.hearings_path(bill) }

  # This bill's attachment directory: attachments/<sway_locale>/.
  let(:attachment_dir) { Legislation::Paths.attachment_dir(sway_locale: sway_locale_name) }

  # Shared helpers, declared at the top level so the "attachment discovery",
  # "attachment download" and "attachment extraction" describe blocks below can
  # all reuse them.
  def matter_attachment(id:, name:, filename: nil, last_modified: "2025-01-01T00:00:00")
    {
      "MatterAttachmentId" => id,
      "MatterAttachmentName" => name,
      "MatterAttachmentFileName" => filename || "#{name.parameterize}.pdf",
      "MatterAttachmentHyperlink" => "https://baltimore.legistar1.com/baltimore/attachments/#{id}.pdf",
      "MatterAttachmentLastModifiedUtc" => last_modified
    }
  end

  # NOTE: no /o flag — that tells Ruby to build the interpolated regex once
  # and reuse it, so a later call with a different matter_id would keep
  # matching the first call's id.
  def stub_matter_attachments(body, status: 200, matter_id: matter_id_int)
    stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/#{matter_id}/Attachments})
      .to_return(status: status, body: body.to_json, headers: {"Content-Type" => "application/json"})
  end

  # The parent record, Matters/<id>: sub-collections answer 200 empty for any
  # well-formed but nonexistent id, so asking the parent is the ONLY way to
  # tell no hearings from no such matter.
  def stub_matter(matter_id: matter_id_int, status: 200)
    stub_request(:get, "https://webapi.legistar.com/v1/baltimore/Matters/#{matter_id}")
      .to_return(
        status: status,
        body: (status == 200) ? {"MatterId" => matter_id, "MatterFile" => "25-0064"}.to_json : "Not Found",
        headers: {"Content-Type" => "application/json"}
      )
  end

  # @lat: [[hearing-testimony-census#Event ids come only from a matter's histories]]
  def stub_matter_histories(event_ids, status: 200, matter_id: matter_id_int)
    body = event_ids.map { |eid| {"MatterHistoryEventId" => eid} }
    stub_matter(matter_id: matter_id)
    event_ids.each do |eid|
      stub_hearing_event({"EventId" => eid})
      stub_event_items(eid, [])
    end
    stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/#{matter_id}/Histories})
      .to_return(status: status, body: body.to_json, headers: {"Content-Type" => "application/json"})
  end

  # One Events/<id> record, the hearing's display details — NOT
  # Events/<id>/EventItems, the attachment list, which #stub_event_items
  # covers separately with its own query.
  def stub_hearing_event(event, status: 200)
    stub_request(:get, "https://webapi.legistar.com/v1/baltimore/Events/#{event["EventId"]}")
      .to_return(status: status, body: event.to_json, headers: {"Content-Type" => "application/json"})
  end

  # Declares a matter's whole set of hearings: Histories rows naming event
  # ids, plus each event's display record. The later WebMock stub wins,
  # replacing the placeholders registered here.
  def stub_hearing_events(events, matter_id: matter_id_int)
    stub_matter_histories(events.map { |e| e["EventId"] }, matter_id: matter_id)
    events.each { |event| stub_hearing_event(event) }
  end

  # The query key is the STRING Attachments with value 1 — WebMock matches
  # only an exact query match, so a $-prefixed spelling would fail loudly as
  # unstubbed rather than passing quietly.
  def stub_event_items(event_id, items, status: 200)
    stub_request(:get, "https://webapi.legistar.com/v1/baltimore/Events/#{event_id}/EventItems")
      .with(query: {"Attachments" => "1"})
      .to_return(status: status, body: items.to_json, headers: {"Content-Type" => "application/json"})
  end

  # Wraps the whole example (not just before/after) because with_app_config
  # needs a block: the settings swap must still be installed while every
  # before hook below runs, since #attachment_dir reads through it too.
  around do |example|
    FileUtils.rm_rf(FetchHearingsServiceSpecHelpers::HEARINGS_ROOT)
    FileUtils.rm_rf(FetchHearingsServiceSpecHelpers::BILLS_RAW_ROOT)
    FileUtils.rm_rf(FetchHearingsServiceSpecHelpers::ATTACHMENTS_ROOT)
    FileUtils.mkdir_p(FetchHearingsServiceSpecHelpers::HEARINGS_ROOT)
    FileUtils.mkdir_p(FetchHearingsServiceSpecHelpers::ATTACHMENTS_ROOT)
    with_app_config(:legislation,
      legislation_hearings_root: FetchHearingsServiceSpecHelpers::HEARINGS_ROOT,
      legislation_bills_raw_root: FetchHearingsServiceSpecHelpers::BILLS_RAW_ROOT,
      legislation_attachments_root: FetchHearingsServiceSpecHelpers::ATTACHMENTS_ROOT) {
      example.run
    }
  ensure
    FileUtils.rm_rf(FetchHearingsServiceSpecHelpers::HEARINGS_ROOT)
    FileUtils.rm_rf(FetchHearingsServiceSpecHelpers::BILLS_RAW_ROOT)
    FileUtils.rm_rf(FetchHearingsServiceSpecHelpers::ATTACHMENTS_ROOT)
  end

  before do
    FetchHearingsServiceSpecHelpers.write_bill_metadata(bill, FetchHearingsServiceSpecHelpers::MATTER_ID)
    # The attachment files sit one level below the root, under this bill's
    # sway_locale — many examples drive extraction directly with no download
    # step to create the directory.
    attachment_dir.mkpath
    # call_discover also calls #discover_attachments, and every example below
    # reaches that point once Events resolves. These default empty-candidate
    # stubs keep those examples passing.
    stub_matter_attachments([])
    stub_matter_histories([])
  end

  # @lat: [[hearing-testimony-census#Event ids come only from a matter's histories]]
  describe "#call — hearing events come from Histories" do
    # The real shape, taken from a live call against matter 10122.
    let(:live_events) do
      [
        {"EventId" => 5065, "EventDate" => "2025-09-18T00:00:00", "EventTime" => "10:00 AM",
         "EventLocation" => "Du Burns Council Chamber", "EventBodyName" => "Land Use & Transportation Committee"},
        {"EventId" => 5107, "EventDate" => "2025-10-16T00:00:00", "EventTime" => "9:00 AM",
         "EventLocation" => "Du Burns Council Chamber", "EventBodyName" => "Land Use & Transportation Committee"}
      ]
    end

    it "derives EventIds from Histories and fetches each Events/<id> for the display metadata" do
      stub_hearing_events(live_events)

      results = described_class.new(bill: bill).call

      expect(results.pluck("EventId")).to eq([5065, 5107])
      expect(results.first["EventBodyName"]).to eq("Land Use & Transportation Committee")
      expect(results.first["EventLocation"]).to eq("Du Burns Council Chamber")
      expect(results.last["EventDate"]).to eq("2025-10-16T00:00:00")
    end

    it "never requests the nonexistent Matters/<id>/Events sub-resource" do
      stub_hearing_events(live_events)

      described_class.new(bill: bill).call

      expect(a_request(:get, %r{/v1/baltimore/Matters/#{matter_id_int}/Events})).not_to have_been_made
    end

    # Both users of event ids — hearings and attachment discovery — ask the
    # same question about the same matter. Without memoizing, every bill
    # sends the identical GET twice.
    it "fetches Histories exactly once even though the hearings array and attachment discovery both need the EventIds" do
      stub_hearing_events(live_events)

      described_class.new(bill: bill).call

      expect(a_request(:get, %r{/v1/baltimore/Matters/#{matter_id_int}/Histories})).to have_been_made.once
    end

    # Each event is handled on its own, the same way
    # #fetch_event_item_matter_attachments does it. A bill's other hearings are
    # real data and must survive one bad event.
    it "keeps the hearings whose event fetch succeeded when a sibling event fetch fails" do
      stub_hearing_events(live_events)
      stub_hearing_event({"EventId" => 5107}, status: 500)

      results = described_class.new(bill: bill).call

      expect(results.pluck("EventId")).to eq([5065])
    end

    # A test recording existing behavior, passing both before and after a
    # dead branch's removal on purpose: it pins WHY that branch could never
    # run, so the type check isn't quietly pushed downstream.
    it "drops a non-object Events/<id> payload rather than emitting a placeholder hearing" do
      stub_hearing_events(live_events)
      stub_request(:get, "https://webapi.legistar.com/v1/baltimore/Events/5107")
        .to_return(status: 200, body: "\"just a string\"", headers: {"Content-Type" => "application/json"})

      results = described_class.new(bill: bill).call

      expect(results.pluck("EventId")).to eq([5065])
      expect(results).not_to include({})
    end
  end

  describe "#call — happy path with two hearing events" do
    it "returns the mapped hearings array and writes the per-bill JSON artifact" do
      stub_hearing_events([
        {
          "EventId" => 1,
          "EventDate" => "2026-04-10T00:00:00",
          "EventTime" => "10:00 AM",
          "EventLocation" => "City Hall",
          "EventBodyName" => "Ways & Means"
        },
        {
          "EventId" => 2,
          "EventDate" => "2026-04-17T00:00:00",
          "EventTime" => "2:00 PM",
          "EventLocation" => "City Hall",
          "EventBodyName" => "Ways & Means"
        }
      ])

      results = described_class.new(bill: bill).call

      expect(results).to be_an(Array)
      expect(results.length).to eq(2)
      expect(results.first["EventId"]).to eq(1)
      expect(results.first["EventBodyName"]).to eq("Ways & Means")

      artifact = hearings_artifact
      expect(File.exist?(artifact)).to be(true)
      written = JSON.parse(File.read(artifact))
      # The artifact is now {"events" => [...], "attachments" => [...]}, not a
      # bare array.
      expect(written["events"].length).to eq(2)
      expect(written["events"].first["EventDate"]).to eq("2026-04-10T00:00:00")
      expect(written["attachments"]).to eq([])
    end
  end

  describe "#call — empty hearings" do
    it "writes an empty-array JSON artifact" do
      # The top-level `before` block already stubs Histories as [], and a matter
      # with no history rows has no events.
      results = described_class.new(bill: bill).call

      expect(results).to eq([])
      artifact = hearings_artifact
      expect(File.exist?(artifact)).to be(true)
      expect(JSON.parse(File.read(artifact))).to eq({"events" => [], "attachments" => [], "attachment_discovery" => {"found" => 0, "kept" => 0, "recorded" => 0, "truncated" => false, "events_unswept" => [], "collections_unswept" => []}})
    end
  end

  # Since the move to Legistar::Client, a non-JSON success body raises
  # ParseError instead of the old parse-to-nil. The service reads that as no
  # usable hearings, not a bill failure.
  describe "#call — 2xx non-JSON body" do
    # The empty artifact itself is unchanged — what changed is that it now
    # SAYS the Histories list went unread, rather than presenting the
    # resulting empty count as something this run established.
    it "writes an empty artifact that records the unread collection, and returns [] (does NOT raise)" do
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/#{FetchHearingsServiceSpecHelpers::MATTER_ID}/Histories}o)
        .to_return(status: 200, body: "<html>maintenance</html>", headers: {"Content-Type" => "text/html"})

      results = described_class.new(bill: bill).call

      expect(results).to eq([])
      artifact = hearings_artifact
      expect(File.exist?(artifact)).to be(true)
      expect(JSON.parse(File.read(artifact))).to eq(
        {
          "events" => [],
          "attachments" => [],
          "attachment_discovery" => {
            "found" => 0, "kept" => 0, "recorded" => 0, "truncated" => false, "events_unswept" => [],
            "collections_unswept" => ["Matters/#{FetchHearingsServiceSpecHelpers::MATTER_ID}/Histories (ParseError on a 2xx body)"]
          }
        }
      )
    end
  end

  # A live check turned the original finding on its head: sub-collections
  # never 404 for a well-formed id, so that branch was dead code aimed the
  # wrong way. The real defect is on the SUCCESS path.
  describe "#call — an empty Histories collection is not evidence on its own (A1-WR-01)" do
    let(:artifact) { hearings_artifact }

    # THE CASE THAT HAD TO FAIL FIRST: a 200 with an empty list from a
    # nonexistent matter is the silent evidence loss this pipeline must
    # prevent.
    it "raises BillProcessingError and records NOTHING when the parent matter 404s" do
      stub_matter_histories([])
      stub_matter(status: 404)

      expect { described_class.new(bill: bill).call }
        .to raise_error(BillProcessingError, /matter_id #{FetchHearingsServiceSpecHelpers::MATTER_ID} does not exist/o)

      expect(File.exist?(artifact)).to be(false)
    end

    it "records the empty artifact when the parent matter does exist" do
      stub_matter_histories([])
      stub_matter(status: 200)

      results = described_class.new(bill: bill).call

      expect(results).to eq([])
      expect(JSON.parse(File.read(artifact)))
        .to eq({"events" => [], "attachments" => [], "attachment_discovery" => {"found" => 0, "kept" => 0, "recorded" => 0, "truncated" => false, "events_unswept" => [], "collections_unswept" => []}})
    end

    # The extra GET only happens when the list came back empty. A matter with
    # hearings has already proved it exists.
    it "does not probe the parent when Histories returned rows" do
      stub_hearing_events([{"EventId" => 5001, "EventDate" => "2026-04-10T00:00:00"}])
      probe = stub_matter

      described_class.new(bill: bill).call

      expect(probe).not_to have_been_requested
    end

    it "probes the parent at most once per matter_id" do
      probe = stub_matter
      service = described_class.new(bill: bill)

      2.times { service.send(:matter_exists?, matter_id_int) }

      expect(probe).to have_been_requested.once
    end

    # A 404 on this route can't mean no hearings yet, since a sub-collection
    # doesn't 404 for a well-formed id — it means something is broken, so it
    # gets a per-bill failure.
    it "treats a 404 from Histories itself as a per-bill error, not as 'no hearings'" do
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/#{FetchHearingsServiceSpecHelpers::MATTER_ID}/Histories}o)
        .to_return(status: 404, body: "Not Found")

      expect { described_class.new(bill: bill).call }
        .to raise_error(BillProcessingError, /HTTP 404/)

      expect(File.exist?(artifact)).to be(false)
    end

    # A check that cannot answer is not an answer. Writing an authoritative empty
    # artifact when the parent could not be reached would be the same defect
    # wearing a different exception class.
    it "raises rather than recording an artifact when the probe itself fails" do
      stub_matter_histories([])
      stub_request(:get, "https://webapi.legistar.com/v1/baltimore/Matters/#{FetchHearingsServiceSpecHelpers::MATTER_ID}")
        .to_return(status: 503, body: "Service Unavailable")

      expect { described_class.new(bill: bill).call }
        .to raise_error(BillProcessingError, /HTTP 503/)

      expect(File.exist?(artifact)).to be(false)
    end

    # Attachment discovery runs AFTER this check inside call_discover, so
    # Matters/<id>/Attachments, which 200s empty for a bogus id the same way,
    # is never reached with an unchecked matter_id.
    it "never reaches attachment discovery for a matter that does not exist" do
      stub_matter_histories([])
      stub_matter(status: 404)
      attachments = stub_matter_attachments([])

      expect { described_class.new(bill: bill).call }.to raise_error(BillProcessingError)

      expect(attachments).not_to have_been_requested
    end
  end

  # @lat: [[hearing-testimony-census#A run that could not read something is not authoritative]]
  describe "#call — an unreadable event makes the sweep non-authoritative" do
    let(:artifact) { hearings_artifact }

    # THE CASE THAT HAD TO FAIL FIRST: the second run sees one attachment now
    # judged bill text, so records is empty while discovery_found is 1 — what
    # nothing_qualified? looks for.
    it "does not retract testimony when an event in Histories does not exist upstream" do
      provisioning = bill.bill_llm_provisioning || bill.create_bill_llm_provisioning!
      provisioning.update!(
        extracted_testimony: "Testimony captured from event 5065 by a healthy earlier run.",
        draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}]
      )

      stub_matter_attachments([matter_attachment(id: 990, name: "cc25-0064(1)~1st (Gray)")])
      stub_matter_histories([5065])
      stub_hearing_event({"EventId" => 5065}, status: 404)

      described_class.new(bill: bill).call

      provisioning.reload
      expect(provisioning.extracted_testimony)
        .to eq("Testimony captured from event 5065 by a healthy earlier run.")
      expect(provisioning.draft_org_positions.first)
        .not_to have_key(BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY)
    end

    # The rule, applied here: the admin screen explaining missing testimony
    # must not disagree with the column it explains. Quietly keeping the text
    # while the screen shows empty is the defect.
    it "says on the admin mirror which events went unread" do
      provisioning = bill.bill_llm_provisioning || bill.create_bill_llm_provisioning!
      provisioning.update!(extracted_testimony: "Prior run testimony.")

      stub_matter_attachments([matter_attachment(id: 991, name: "cc25-0064(1)~1st (Gray)")])
      stub_matter_histories([5065])
      stub_hearing_event({"EventId" => 5065}, status: 404)

      described_class.new(bill: bill).call

      notice = provisioning.reload.testimony_attachments.last
      expect(notice["download_status"]).to eq("not_attempted")
      expect(notice["error"]).to match(/5065/)
      expect(notice["error"]).to match(/does not resolve upstream|no longer resolve/)
    end

    # The part that outlives the run: the artifact is what every later reader
    # looks at, and it used to claim a complete events array and attachment
    # count with nothing recording an unread event.
    it "records the unswept event ids on the artifact census" do
      stub_matter_attachments([])
      stub_matter_histories([5065, 5107])
      stub_hearing_event({"EventId" => 5065}, status: 404)

      described_class.new(bill: bill).call

      expect(JSON.parse(File.read(artifact))["attachment_discovery"])
        .to include("events_unswept" => [5065])
    end

    # fetch_hearing_event already GETs Events/<id> per event, learning for
    # free whether it exists. An event proven absent must not then be asked
    # for its EventItems.
    it "does not ask a proven-absent event for its EventItems" do
      stub_matter_attachments([])
      stub_matter_histories([5065])
      stub_hearing_event({"EventId" => 5065}, status: 404)
      items = stub_event_items(5065, [])

      described_class.new(bill: bill).call

      expect(items).not_to have_been_requested
    end

    # The matching second site: fetch_event_item_matter_attachments rescues
    # its OWN fetch to an empty list, the same half-read set wearing a
    # different exception.
    it "does not retract testimony when an event's EventItems fetch itself fails" do
      provisioning = bill.bill_llm_provisioning || bill.create_bill_llm_provisioning!
      provisioning.update!(extracted_testimony: "Prior run testimony.")

      stub_matter_attachments([matter_attachment(id: 992, name: "cc25-0064(1)~1st (Gray)")])
      stub_matter_histories([5065])
      stub_event_items(5065, [], status: 500)

      described_class.new(bill: bill).call

      expect(provisioning.reload.extracted_testimony).to eq("Prior run testimony.")
    end

    # And the other direction: a COMPLETE read still retracts. Without this, the
    # fix would look the same as deleting #nothing_qualified? altogether.
    it "still retracts when every event was swept and nothing qualified" do
      provisioning = bill.bill_llm_provisioning || bill.create_bill_llm_provisioning!
      provisioning.update!(extracted_testimony: "Pre-phase-63 text that was really the bill.")

      stub_matter_attachments([matter_attachment(id: 993, name: "cc25-0064(1)~1st (Gray)")])
      stub_matter_histories([5065])

      described_class.new(bill: bill).call

      expect(provisioning.reload.extracted_testimony).to be_nil
    end
  end

  # @lat: [[hearing-testimony-census#A run that could not read something is not authoritative]]
  describe "#call — an unread COLLECTION makes the sweep non-authoritative (A-CR-01)" do
    let(:artifact) { hearings_artifact }

    # Uses a name the classifier judges to be bill text, so the candidate set
    # ends up empty while @discovery_found stays above zero — exactly what
    # #nothing_qualified? looks for.
    def stub_bill_text_event_item(event_id, attachment_id)
      stub_event_items(event_id, [
        {
          "EventItemId" => 9000 + attachment_id,
          "EventItemMatterId" => matter_id_int,
          "EventItemMatterAttachments" => [
            matter_attachment(id: attachment_id, name: "cc25-0064(1)~1st (Gray)")
          ]
        }
      ])
    end

    def seed_prior_evidence
      provisioning = bill.bill_llm_provisioning || bill.create_bill_llm_provisioning!
      provisioning.update!(
        extracted_testimony: "Testimony captured by a healthy earlier run.",
        draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}]
      )
      provisioning
    end

    # THE CASE THAT HAD TO FAIL FIRST, and the easiest to hit in production: one
    # HTTP 500 on the matter's own attachment list. The event-items half still
    # answers, so discovery LOOKS complete.
    it "does not retract when the matter attachment collection 500s" do
      provisioning = seed_prior_evidence

      stub_matter_attachments([], status: 500)
      stub_matter_histories([5065])
      stub_bill_text_event_item(5065, 771)

      described_class.new(bill: bill).call

      provisioning.reload
      expect(provisioning.extracted_testimony).to eq("Testimony captured by a healthy earlier run.")
      expect(provisioning.draft_org_positions.first)
        .not_to have_key(BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY)
    end

    # Same collection, the OTHER way it degrades: a success body that's not
    # an Array. A 200 error object isn't hypothetical, and the is_a?(Array)
    # guard turns it into this matter has no attachments.
    it "does not retract when the matter attachment collection returns a non-Array 2xx body" do
      provisioning = seed_prior_evidence

      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/#{matter_id_int}/Attachments})
        .to_return(status: 200, body: {"Error" => "temporarily unavailable"}.to_json,
          headers: {"Content-Type" => "application/json"})
      stub_matter_histories([5065])
      stub_bill_text_event_item(5065, 772)

      described_class.new(bill: bill).call

      provisioning.reload
      expect(provisioning.extracted_testimony).to eq("Testimony captured by a healthy earlier run.")
      expect(provisioning.draft_org_positions.first)
        .not_to have_key(BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY)
    end

    # The other list that degrades to empty, more destructive: a non-JSON
    # success body from Histories concludes no hearing events and skips the
    # entire event-items half of the census.
    it "does not retract when the Histories collection returns an unparseable 2xx body" do
      provisioning = seed_prior_evidence

      stub_matter_attachments([matter_attachment(id: 773, name: "cc25-0064(1)~1st (Gray)")])
      stub_matter(matter_id: matter_id_int)
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/#{matter_id_int}/Histories})
        .to_return(status: 200, body: "<html>gateway</html>", headers: {"Content-Type" => "text/html"})

      described_class.new(bill: bill).call

      provisioning.reload
      expect(provisioning.extracted_testimony).to eq("Testimony captured by a healthy earlier run.")
      expect(provisioning.draft_org_positions.first)
        .not_to have_key(BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY)
    end

    # Its twin, unnamed by the review: a body that PARSES but isn't an Array
    # takes event_ids_for_matter!'s else-branch to the same no hearing events
    # conclusion, with no rescue involved at all.
    it "does not retract when the Histories collection returns a non-Array 2xx body" do
      provisioning = seed_prior_evidence

      stub_matter_attachments([matter_attachment(id: 774, name: "cc25-0064(1)~1st (Gray)")])
      stub_matter(matter_id: matter_id_int)
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/#{matter_id_int}/Histories})
        .to_return(status: 200, body: {"Error" => "temporarily unavailable"}.to_json,
          headers: {"Content-Type" => "application/json"})

      described_class.new(bill: bill).call

      provisioning.reload
      expect(provisioning.extracted_testimony).to eq("Testimony captured by a healthy earlier run.")
      expect(provisioning.draft_org_positions.first)
        .not_to have_key(BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY)
    end

    # @lat: [[hearing-testimony-census#A run that could not read something is not authoritative]]
    it "does not retract when an event's EventItems returns a non-Array 2xx body" do
      provisioning = seed_prior_evidence

      stub_matter_attachments([matter_attachment(id: 775, name: "cc25-0064(1)~1st (Gray)")])
      stub_matter_histories([5065])
      stub_request(:get, "https://webapi.legistar.com/v1/baltimore/Events/5065/EventItems")
        .with(query: {"Attachments" => "1"})
        .to_return(status: 200, body: {"Error" => "temporarily unavailable"}.to_json,
          headers: {"Content-Type" => "application/json"})

      described_class.new(bill: bill).call

      provisioning.reload
      expect(provisioning.extracted_testimony).to eq("Testimony captured by a healthy earlier run.")
      expect(provisioning.draft_org_positions.first)
        .not_to have_key(BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY)
    end

    # The part that outlives the run: the artifact is either a complete
    # account of what this run read or no account at all — events_unswept
    # alone can't say the matter's own list was never read.
    it "records the unswept collections on the artifact census" do
      stub_matter_attachments([], status: 500)
      stub_matter_histories([5065])
      stub_bill_text_event_item(5065, 776)

      described_class.new(bill: bill).call

      census = JSON.parse(File.read(artifact))["attachment_discovery"]
      expect(census["collections_unswept"]).to include(a_string_matching(%r{Matters/#{matter_id_int}/Attachments}))
      expect(census["events_unswept"]).to eq([])
    end

    # collections_unswept is always written, exactly as events_unswept is — a
    # reader must never guess whether a missing key means nothing went unread
    # or this artifact predates the key.
    it "records an empty collections list on a clean run" do
      stub_matter_attachments([])
      stub_matter_histories([])

      described_class.new(bill: bill).call

      expect(JSON.parse(File.read(artifact))["attachment_discovery"])
        .to include("collections_unswept" => [])
    end

    # The rule again: the admin screen explaining missing testimony must not
    # disagree with the column it explains. Quietly keeping the text while
    # the screen shows empty is exactly the defect.
    it "says on the admin mirror which collection went unread" do
      provisioning = seed_prior_evidence

      stub_matter_attachments([], status: 500)
      stub_matter_histories([5065])
      stub_bill_text_event_item(5065, 777)

      described_class.new(bill: bill).call

      notice = provisioning.reload.testimony_attachments.to_a.last

      expect(notice).to include("download_status" => "not_attempted")
      expect(notice).to include("error" => a_string_matching(%r{Matters/#{matter_id_int}/Attachments}))
    end

    # The control case, matching the one in the block above. Without it the fix
    # would look the same as deleting #nothing_qualified? altogether.
    it "still retracts when every collection was read and nothing qualified" do
      provisioning = seed_prior_evidence

      stub_matter_attachments([matter_attachment(id: 778, name: "cc25-0064(1)~1st (Gray)")])
      stub_matter_histories([5065])

      described_class.new(bill: bill).call

      provisioning.reload
      expect(provisioning.extracted_testimony).to be_nil
      expect(provisioning.draft_org_positions.first)
        .to have_key(BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY)
    end
  end

  # Every other error status (5xx, and 4xx other than 404) is still a real error.
  describe "#call — HTTP 500" do
    it "raises BillProcessingError" do
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/#{FetchHearingsServiceSpecHelpers::MATTER_ID}/Histories}o)
        .to_return(status: 500, body: "Internal Server Error")

      expect { described_class.new(bill: bill).call }
        .to raise_error(BillProcessingError, /HTTP 500/)
    end
  end

  describe "#call — Faraday::TimeoutError" do
    it "raises BillProcessingError with truncated message" do
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/#{FetchHearingsServiceSpecHelpers::MATTER_ID}/Histories}o)
        .to_raise(Faraday::TimeoutError.new("x" * 1000))

      expect { described_class.new(bill: bill).call }
        .to raise_error(BillProcessingError) do |err|
          expect(err.message).to include("Faraday::TimeoutError")
          expect(err.message.length).to be <= ("fetch_hearings: Faraday::TimeoutError: ".length + 500)
        end
    end
  end

  describe "#call — missing metadata.json" do
    it "raises BillProcessingError naming the missing path" do
      FileUtils.rm_rf(FetchHearingsServiceSpecHelpers::BILLS_RAW_ROOT)
      expect { described_class.new(bill: bill).call }
        .to raise_error(BillProcessingError, /no metadata\.json/)
    end

    # @lat: [[hearing-testimony-census#An error names the stage that writes the file it wanted]]
    it "names the stage that writes the file it could not find" do
      FileUtils.rm_rf(FetchHearingsServiceSpecHelpers::BILLS_RAW_ROOT)
      expect { described_class.new(bill: bill).call }
        .to raise_error(BillProcessingError, /fetch-bills stage writes that file/)
    end
  end

  describe "mode validation" do
    let(:baltimore) { create(:sway_locale, :baltimore) }
    let(:run) { create(:legislation_pipeline_run) }
    let(:bill_with_hearings) { create(:bill, sway_locale: baltimore, external_id: "BFH-001") }

    it "defaults to :discover when no mode kwarg given (back-compat)" do
      service = described_class.new(bill: bill_with_hearings)
      expect(service.instance_variable_get(:@mode)).to eq(:discover)
    end

    it "raises StageError when defunct :backfill_missing mode is specified" do
      expect {
        described_class.new(run: run, mode: :backfill_missing).call
      }.to raise_error(StageError, /unknown mode :backfill_missing/)
    end

    it "raises StageError on an unknown mode" do
      expect {
        described_class.new(run: run, mode: :bogus).call
      }.to raise_error(StageError, /unknown mode :bogus/)
    end
  end

  # Finding testimony attachments across both collections.
  # discover_attachments is called directly via #send, since it wasn't yet
  # wired into call_discover's saved flow when this was written.
  describe "attachment discovery" do
    let(:service) { described_class.new(bill: bill) }

    it "unions both collections, deduping by id and preferring the event-associated record" do
      stub_matter_attachments([matter_attachment(id: 111, name: "10.16.25 Public Testimony 25-0001")])
      stub_matter_histories([5001])
      stub_event_items(5001, [
        {
          "EventItemId" => 9001,
          "EventItemMatterId" => matter_id_int,
          "EventItemMatterAttachments" => [matter_attachment(id: 111, name: "10.16.25 Public Testimony 25-0001")]
        }
      ])

      records = service.send(:discover_attachments, matter_id_int, sway_locale_id: bill.sway_locale_id)

      expect(records.length).to eq(1)
      expect(records.first["id"]).to eq(111)
      expect(records.first["source_endpoint"]).to eq("event_item_matter_attachments")
      expect(records.first["event_id"]).to eq(5001)
      expect(records.first["event_item_id"]).to eq(9001)
      expect(records.first["download_status"]).to eq("pending")
      expect(records.first["extraction_status"]).to eq("pending")
      expect(records.first["error"]).to be_nil
    end

    # Deduping used to group on the RAW MatterAttachmentId while the verdict
    # map used the CONVERTED id — two raw values converting the same way
    # fought over one attachment file pair.
    it "dedupes on the coerced id, so a String and an Integer id collapse to one record" do
      stub_matter_attachments([matter_attachment(id: 111, name: "10.16.25 Public Testimony 25-0001")])
      stub_matter_histories([5001])
      stub_event_items(5001, [
        {
          "EventItemId" => 9001,
          "EventItemMatterId" => matter_id_int,
          # Same document, id sent as a JSON string this time.
          "EventItemMatterAttachments" => [matter_attachment(id: "111", name: "10.16.25 Public Testimony 25-0001")]
        }
      ])

      records = service.send(:discover_attachments, matter_id_int, sway_locale_id: bill.sway_locale_id)

      expect(records.length).to eq(1)
      expect(records.map { |r| service.send(:attachment_pdf_path, r, sway_locale: sway_locale_name) }.uniq.length).to eq(1)
    end

    # ...but an id that won't convert identifies nothing, so those entries
    # mustn't all collapse into one nil group. Each has to survive as its own
    # record so it can report as a failed download.
    it "keeps every uncoercible-id entry distinct rather than collapsing them on a nil key" do
      entries = [
        {raw: {"MatterAttachmentId" => "not-an-id", "MatterAttachmentName" => "A"}, source_endpoint: "matter_attachments", event_id: nil, event_item_id: nil},
        {raw: {"MatterAttachmentId" => nil, "MatterAttachmentName" => "B"}, source_endpoint: "matter_attachments", event_id: nil, event_item_id: nil},
        {raw: {"MatterAttachmentId" => -4, "MatterAttachmentName" => "C"}, source_endpoint: "matter_attachments", event_id: nil, event_item_id: nil}
      ]

      deduped = service.send(:dedupe_attachment_entries, entries)

      expect(deduped.length).to eq(3)
      expect(deduped.map { |e| e[:raw]["MatterAttachmentName"] }).to contain_exactly("A", "B", "C")
    end

    # The ranking used to score a missing event_item_id as 0, so an entry
    # with NO event item beat one WITH one — the entry that knew less won. It
    # must sort LAST within its event instead.
    it "prefers the sibling that carries an event_item_id over one that does not" do
      raw = {"MatterAttachmentId" => 111, "MatterAttachmentName" => "10.16.25 Public Testimony"}
      without_item = {raw: raw, source_endpoint: "event_item_matter_attachments", event_id: 5001, event_item_id: nil}
      with_item = {raw: raw, source_endpoint: "event_item_matter_attachments", event_id: 5001, event_item_id: 9001}

      deduped = service.send(:dedupe_attachment_entries, [without_item, with_item])

      expect(deduped.length).to eq(1)
      expect(deduped.first[:event_item_id]).to eq(9001)
    end

    it "carries nil event ids for matter-attachment-only records" do
      stub_matter_attachments([matter_attachment(id: 200, name: "DOF 25-0001.pdf")])
      stub_matter_histories([])

      records = service.send(:discover_attachments, matter_id_int, sway_locale_id: bill.sway_locale_id)

      expect(records.length).to eq(1)
      expect(records.first["source_endpoint"]).to eq("matter_attachments")
      expect(records.first["event_id"]).to be_nil
      expect(records.first["event_item_id"]).to be_nil
    end

    # The same setup fetch_bills_service_spec.rb uses when a matter has no
    # Reader attachment: the testimony PDF select_primary_attachment picks
    # must still show up here as a testimony candidate.
    it "keeps the Reader-less fallback testimony PDF as a candidate" do
      stub_matter_attachments([
        matter_attachment(id: 301, name: "BDC 25-0099.pdf", filename: "bdc-25-0099.pdf", last_modified: "2025-09-04T12:51:49"),
        matter_attachment(id: 302, name: "10.16.25 Public Testimony 25-0099", filename: "testimony-25-0099.pdf", last_modified: "2026-01-29T18:06:36")
      ])
      stub_matter_histories([])

      records = service.send(:discover_attachments, matter_id_int, sway_locale_id: bill.sway_locale_id)

      expect(records.pluck("id")).to contain_exactly(301, 302)
      expect(records.first).not_to have_key("primary")
    end

    it "excludes the Reader attachment when one exists" do
      stub_matter_attachments([
        matter_attachment(id: 401, name: "25-0064~3rd Reader", filename: "25-0064-3rd-reader.pdf", last_modified: "2025-10-27T15:23:28"),
        matter_attachment(id: 402, name: "10.16.25 Public Testimony 25-0064", filename: "testimony-25-0064.pdf", last_modified: "2026-01-29T18:01:25")
      ])
      stub_matter_histories([])

      records = service.send(:discover_attachments, matter_id_int, sway_locale_id: bill.sway_locale_id)

      expect(records.pluck("id")).to eq([402])
    end

    # fetch_matter_attachments checks the CONTAINER but not the ITEMS —
    # dedupe_key reads a raw hash key with no type check, before the .pdf
    # filter runs, raising past the never-fail-the-bill promise.
    it "drops non-Hash elements from the matter Attachments array instead of raising" do
      stub_matter_attachments([nil, matter_attachment(id: 610, name: "Good Testimony"), 42])
      stub_matter_histories([])

      # Not raising IS the check: discover_attachments promises it can never
      # fail the bill, so a NoMethodError fails this example on its own. A
      # plain call also keeps Steep from treating records as nil.
      records = service.send(:discover_attachments, matter_id_int, sway_locale_id: bill.sway_locale_id)
      expect(records.pluck("id")).to eq([610])
    end

    it "excludes non-.pdf attachments" do
      stub_matter_attachments([matter_attachment(id: 501, name: "Some Link", filename: "not-a-pdf.docx")])
      stub_matter_histories([])

      records = service.send(:discover_attachments, matter_id_int, sway_locale_id: bill.sway_locale_id)

      expect(records).to eq([])
    end

    it "records a malformed attachment id as failed and continues with the remaining attachments" do
      stub_matter_attachments([
        matter_attachment(id: "not-a-number", name: "Bad Id Testimony"),
        matter_attachment(id: 601, name: "Good Testimony")
      ])
      stub_matter_histories([])

      records = service.send(:discover_attachments, matter_id_int, sway_locale_id: bill.sway_locale_id)

      expect(records.length).to eq(2)
      bad = records.find { |r| r["id"].nil? }
      good = records.find { |r| r["id"] == 601 }
      expect(bad["download_status"]).to eq("failed")
      expect(bad["error"]).to be_present
      expect(good["download_status"]).to eq("pending")
    end

    it "degrades to matter-attachments-only when an EventItems fetch 404s" do
      stub_matter_attachments([matter_attachment(id: 701, name: "Fallback Testimony")])
      stub_matter_histories([5002])
      stub_event_items(5002, [], status: 404)

      records = service.send(:discover_attachments, matter_id_int, sway_locale_id: bill.sway_locale_id)

      expect(records.pluck("id")).to eq([701])
    end

    it "returns an empty array without raising when both collections fail entirely" do
      stub_matter_attachments([], status: 500)
      stub_matter_histories([], status: 500)

      records = nil
      expect { records = service.send(:discover_attachments, matter_id_int, sway_locale_id: bill.sway_locale_id) }.not_to raise_error
      expect(records).to eq([])
    end

    # Events/<id>/EventItems returns EVERY matter heard at that event, not
    # just ours. Without the EventItemMatterId filter, one bill would pull in
    # 106 attachments belonging to three other bills.
    it "ingests only the requested matter's attachments from a shared hearing event" do
      stub_matter_attachments([])
      stub_matter_histories([5065])
      stub_event_items(5065, [
        {
          "EventItemId" => 7001,
          "EventItemMatterId" => matter_id_int,
          "EventItemMatterAttachments" => [matter_attachment(id: 1001, name: "Testimony for our bill")]
        },
        {
          "EventItemId" => 7002,
          "EventItemMatterId" => matter_id_int + 1,
          "EventItemMatterAttachments" => [matter_attachment(id: 1002, name: "Testimony for a different bill")]
        },
        {
          "EventItemId" => 7003,
          "EventItemMatterId" => matter_id_int + 2,
          "EventItemMatterAttachments" => [
            matter_attachment(id: 1003, name: "Testimony for a third bill"),
            matter_attachment(id: 1004, name: "More testimony for a third bill")
          ]
        }
      ])

      records = service.send(:discover_attachments, matter_id_int, sway_locale_id: bill.sway_locale_id)

      expect(records.pluck("id")).to eq([1001])
    end

    # The old filter let through 87% of ALL attachments on real Legistar
    # data. Every name below is a real Baltimore attachment that slipped past
    # it and reached the org-positions prompt as bill text.
    it "excludes bill-text attachments that the Reader-name regex never caught" do
      stub_matter_attachments([
        matter_attachment(id: 1101, name: "Ord.25-063 tc", filename: "ord-25-063-tc.pdf"),
        matter_attachment(id: 1102, name: "25-0064 Signed", filename: "25-0064-signed.pdf"),
        matter_attachment(id: 1103, name: "cc25-0064(1)~1st (LUT)", filename: "cc25-0064-1-1st-lut.pdf"),
        matter_attachment(id: 1104, name: "cc25-0064(1)~1st (Gray)", filename: "cc25-0064-1-1st-gray.pdf"),
        matter_attachment(id: 1105, name: "10.16.25 Public Testimony 25-0064", filename: "testimony-25-0064.pdf")
      ])
      stub_matter_histories([])

      records = service.send(:discover_attachments, matter_id_int, sway_locale_id: bill.sway_locale_id)

      expect(records.pluck("id")).to eq([1105])
    end

    it "excludes procedural attachments while keeping stance documents that never say 'testimony'" do
      stub_matter_attachments([
        matter_attachment(id: 1110, name: "Voting Record 25-0064", filename: "voting-record.pdf"),
        matter_attachment(id: 1111, name: "25-0064 Attendance", filename: "attendance.pdf"),
        matter_attachment(id: 1112, name: "100 Holliday Street - Community Letter of Support", filename: "holliday-support.pdf"),
        matter_attachment(id: 1113, name: "2025-0060 Alex Morgan Oppose", filename: "morgan-oppose.pdf"),
        matter_attachment(id: 1114, name: "MG Opposition 25-0065.pdf", filename: "mg-opposition.pdf")
      ])
      stub_matter_histories([])

      records = service.send(:discover_attachments, matter_id_int, sway_locale_id: bill.sway_locale_id)

      expect(records.pluck("id")).to contain_exactly(1112, 1113, 1114)
    end

    # With no model wired up (the test default) a name nobody could judge is
    # KEPT — safe, since bill text was already removed earlier and can't come
    # back; keeping the rest only costs precision.
    it "keeps an undecided agency document when no classifier adapter is available" do
      stub_matter_attachments([matter_attachment(id: 1120, name: "DOF 25-0064", filename: "dof-25-0064.pdf")])
      stub_matter_histories([])

      records = service.send(:discover_attachments, matter_id_int, sway_locale_id: bill.sway_locale_id)

      expect(records.pluck("id")).to eq([1120])
    end

    # Law 25-0064 is the Law Department's report, not bill text — the enacted
    # law is Ord.25-063 tc. The design counts the Law Department in scope,
    # reaching the last classification stage.
    it "routes the Law Department's report to stage 3 while still denying the enacted ordinance" do
      stub_matter_attachments([
        matter_attachment(id: 1130, name: "Law 25-0064", filename: "law-25-0064.pdf"),
        matter_attachment(id: 1131, name: "Ord.25-063 tc", filename: "ord-25-063-tc.pdf")
      ])
      stub_matter_histories([])

      records = service.send(:discover_attachments, matter_id_int, sway_locale_id: bill.sway_locale_id)

      expect(records.pluck("id")).to eq([1130])
    end

    it "keeps event items whose EventItemMatterId is absent or non-numeric out of the candidate set" do
      stub_matter_attachments([])
      stub_matter_histories([5066])
      stub_event_items(5066, [
        {
          "EventItemId" => 7004,
          "EventItemMatterAttachments" => [matter_attachment(id: 1005, name: "Testimony with no matter id")]
        },
        {
          "EventItemId" => 7005,
          "EventItemMatterId" => matter_id_int.to_s,
          "EventItemMatterAttachments" => [matter_attachment(id: 1006, name: "Testimony with a string matter id")]
        }
      ])

      records = service.send(:discover_attachments, matter_id_int, sway_locale_id: bill.sway_locale_id)

      expect(records).to eq([])
    end
  end

  # Downloading attachments: checking the body starts with PDF bytes, keeping
  # one bad attachment from taking others down. download_attachments! is
  # called directly via #send for behavior examples.
  describe "attachment download" do
    let(:service) { described_class.new(bill: bill) }

    def pending_record(id:, url:, source_endpoint: "matter_attachments", filename: nil)
      {
        "id" => id,
        "filename" => filename || "testimony-#{id}.pdf",
        "url" => url,
        "source_endpoint" => source_endpoint,
        "event_id" => nil,
        "event_item_id" => nil,
        "download_status" => "pending",
        "extraction_status" => "pending",
        "error" => nil
      }
    end

    it "writes a 200 PDF-magic-byte body to the locale's attachment directory and records download_status succeeded" do
      record = pending_record(id: 900, url: "https://baltimore.legistar1.com/baltimore/attachments/900.pdf")
      stub_request(:get, record["url"]).to_return(status: 200, body: "%PDF-1.4 fake pdf bytes")

      service.send(:download_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["download_status"]).to eq("succeeded")
      expect(record["error"]).to be_nil
      written_path = attachment_dir.join("attachment-900.pdf")
      expect(File.exist?(written_path)).to be(true)
      expect(File.read(written_path)).to eq("%PDF-1.4 fake pdf bytes")
    end

    it "rejects a non-2xx response, writes no file, records failed, and continues the loop" do
      good = pending_record(id: 901, url: "https://baltimore.legistar1.com/baltimore/attachments/901.pdf")
      bad = pending_record(id: 902, url: "https://baltimore.legistar1.com/baltimore/attachments/902.pdf")
      stub_request(:get, good["url"]).to_return(status: 200, body: "%PDF-1.4 ok")
      stub_request(:get, bad["url"]).to_return(status: 404, body: "Not Found")

      service.send(:download_attachments!, [bad, good], sway_locale: sway_locale_name)

      expect(bad["download_status"]).to eq("failed")
      expect(bad["error"]).to be_present
      expect(File.exist?(attachment_dir.join("attachment-902.pdf"))).to be(false)
      expect(good["download_status"]).to eq("succeeded")
      expect(File.exist?(attachment_dir.join("attachment-901.pdf"))).to be(true)
    end

    # FaradayStack.legistar sets a 30s TIMEOUT, limiting time not SIZE —
    # plenty to pull hundreds of MB into a Ruby String on the Pi. This
    # project has already been burned by exactly that shape.
    it "rejects a body whose advertised Content-Length is over the cap, without reading it" do
      record = pending_record(id: 920, url: "https://baltimore.legistar1.com/baltimore/attachments/920.pdf")
      stub_request(:get, record["url"]).to_return(
        status: 200,
        body: "%PDF-1.4 small body, enormous claim",
        headers: {"Content-Length" => (512 * 1024 * 1024).to_s}
      )

      service.send(:download_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["download_status"]).to eq("failed")
      expect(record["error"]).to match(/cap/i)
      expect(File.exist?(attachment_dir.join("attachment-920.pdf"))).to be(false)
    end

    # The size limit now lives on Legistar::AttachmentFetch, the one place
    # BOTH download sites go through. These examples check what THIS caller
    # must do: mark one attachment failed, keep going.
    it "rejects an over-cap body that advertised no Content-Length" do
      record = pending_record(id: 921, url: "https://baltimore.legistar1.com/baltimore/attachments/921.pdf")
      stub_const("Legistar::AttachmentFetch::MAX_ATTACHMENT_BYTES", 16)
      stub_request(:get, record["url"]).to_return(status: 200, body: "%PDF-1.4 this body is well over sixteen bytes")

      service.send(:download_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["download_status"]).to eq("failed")
      expect(record["error"]).to match(/cap/i)
      expect(File.exist?(attachment_dir.join("attachment-921.pdf"))).to be(false)
    end

    it "rejects a 200 body that does not start with the PDF magic bytes" do
      record = pending_record(id: 903, url: "https://baltimore.legistar1.com/baltimore/attachments/903.pdf")
      stub_request(:get, record["url"]).to_return(status: 200, body: "<html>not a pdf</html>")

      service.send(:download_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["download_status"]).to eq("failed")
      expect(record["error"]).to match(/not a PDF/)
      expect(File.exist?(attachment_dir.join("attachment-903.pdf"))).to be(false)
    end

    it "rescues a Faraday transport error narrowly and never re-raises out of the loop" do
      record = pending_record(id: 904, url: "https://baltimore.legistar1.com/baltimore/attachments/904.pdf")
      stub_request(:get, record["url"]).to_raise(Faraday::ConnectionFailed.new("boom"))

      expect { service.send(:download_attachments!, [record], sway_locale: sway_locale_name) }.not_to raise_error
      expect(record["download_status"]).to eq("failed")
      expect(record["error"]).to include("Faraday::ConnectionFailed")
    end

    # Server-side request forgery: the download target is whatever the
    # hyperlink says, and Faraday treats a full URL as replacing the
    # connection's prefix. The allowlist must run BEFORE the GET.
    it "never issues a request to a host outside the Legistar allowlist" do
      record = pending_record(id: 906, url: "http://169.254.169.254/latest/meta-data/iam/security-credentials/")
      probe = stub_request(:get, "http://169.254.169.254/latest/meta-data/iam/security-credentials/")

      service.send(:download_attachments!, [record], sway_locale: sway_locale_name)

      expect(probe).not_to have_been_requested
      expect(record["download_status"]).to eq("failed")
      expect(record["error"]).to include("169.254.169.254")
    end

    # A redirect used to be recorded as a permanent failure for that
    # attachment, so one CDN or login hop in front of the host would quietly
    # stop all testimony capture while the old value stayed put.
    it "follows a redirect to an allowed Legistar host instead of recording HTTP 302" do
      record = pending_record(id: 909, url: "https://baltimore.legistar1.com/baltimore/attachments/909.pdf")
      hop = "https://baltimore.legistar1.com/cdn/909.pdf"
      stub_request(:get, record["url"]).to_return(status: 302, headers: {"Location" => hop})
      stub_request(:get, hop).to_return(status: 200, body: "%PDF-1.4 redirected")

      service.send(:download_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["download_status"]).to eq("succeeded")
      expect(record["error"]).to be_nil
      expect(File.read(attachment_dir.join("attachment-909.pdf"))).to eq("%PDF-1.4 redirected")
    end

    it "re-applies the allowlist on the redirect target, not just the initial url" do
      record = pending_record(id: 910, url: "https://baltimore.legistar1.com/baltimore/attachments/910.pdf")
      stub_request(:get, record["url"])
        .to_return(status: 302, headers: {"Location" => "http://169.254.169.254/latest/meta-data/"})
      probe = stub_request(:get, "http://169.254.169.254/latest/meta-data/")

      expect { service.send(:download_attachments!, [record], sway_locale: sway_locale_name) }.not_to raise_error

      expect(probe).not_to have_been_requested
      expect(record["download_status"]).to eq("failed")
      expect(record["error"]).to include("169.254.169.254")
    end

    it "degrades a rejected url per-attachment — its siblings still download (PROD-CR-02)" do
      blocked = pending_record(id: 907, url: "http://127.0.0.1:9292/")
      good = pending_record(id: 908, url: "https://baltimore.legistar1.com/baltimore/attachments/908.pdf")
      stub_request(:get, good["url"]).to_return(status: 200, body: "%PDF-1.4 ok")

      expect { service.send(:download_attachments!, [blocked, good], sway_locale: sway_locale_name) }.not_to raise_error

      expect(blocked["download_status"]).to eq("failed")
      expect(good["download_status"]).to eq("succeeded")
      expect(File.exist?(attachment_dir.join("attachment-908.pdf"))).to be(true)
    end

    # @lat: [[download-bounds#Download bounds]]
    it "degrades an attachment exceeding the elapsed ceiling per-attachment — siblings still download" do
      slow = pending_record(id: 950, url: "https://baltimore.legistar1.com/baltimore/attachments/950.pdf")
      healthy = pending_record(id: 951, url: "https://baltimore.legistar1.com/baltimore/attachments/951.pdf")

      current_time = 1_000.0
      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { current_time }

      stub_request(:get, slow["url"]).to_return do
        current_time += 35.0
        {status: 200, body: "%PDF-1.4 slow"}
      end
      stub_request(:get, healthy["url"]).to_return do
        current_time += 2.0
        {status: 200, body: "%PDF-1.4 healthy"}
      end

      expect {
        service.send(:download_attachments!, [slow, healthy], sway_locale: sway_locale_name)
      }.not_to raise_error

      expect(slow["download_status"]).to eq("failed")
      expect(slow["error"]).to match(/ceiling|elapsed/i)
      expect(File.exist?(attachment_dir.join("attachment-950.pdf"))).to be(false)

      expect(healthy["download_status"]).to eq("succeeded")
      expect(healthy["error"]).to be_nil
      written_path = attachment_dir.join("attachment-951.pdf")
      expect(File.exist?(written_path)).to be(true)
      expect(File.read(written_path)).to eq("%PDF-1.4 healthy")
    end

    it "makes exactly 2 attempts when an attachment fails with a transport error" do
      record = pending_record(id: 998, url: "https://baltimore.legistar1.com/baltimore/attachments/998.pdf")
      req_stub = stub_request(:get, record["url"]).to_raise(Faraday::ConnectionFailed.new("connection dropped"))

      service.send(:download_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["download_status"]).to eq("failed")
      expect(req_stub).to have_been_made.times(2)
    end

    # extract_attachments! has an overall deadline; this loop, six lines
    # EARLIER in the same chain, had none — a CDN that swallows requests
    # costs ~27 hours for one bill, with no watchdog.
    it "stops downloading when the per-bill time budget is exhausted and records the remainder" do
      records = [
        pending_record(id: 990, url: "https://baltimore.legistar1.com/baltimore/attachments/990.pdf"),
        pending_record(id: 991, url: "https://baltimore.legistar1.com/baltimore/attachments/991.pdf")
      ]
      stub_const("#{described_class}::DOWNLOAD_BUDGET_SECONDS", 0.0)
      probe = stub_request(:get, %r{baltimore\.legistar1\.com/baltimore/attachments/99[01]\.pdf})

      service.send(:download_attachments!, records, sway_locale: sway_locale_name)

      # Not one byte of network was spent past the deadline.
      expect(probe).not_to have_been_requested
      # And what is left over is RECORDED, not quietly dropped: the admin status
      # list is the only place an operator learns there is work left to do.
      expect(records.pluck("download_status")).to all(eq("skipped_time_budget"))
      expect(records.first["error"]).to match(/download budget was exhausted/)
      expect(records.first["error"]).to match(/re-run fetch_hearings/)
    end

    it "downloads normally while budget remains" do
      record = pending_record(id: 992, url: "https://baltimore.legistar1.com/baltimore/attachments/992.pdf")
      stub_request(:get, record["url"]).to_return(status: 200, body: "%PDF-1.4 in budget")

      service.send(:download_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["download_status"]).to eq("succeeded")
      expect(record["error"]).to be_nil
    end

    # Legistar's two attachment collections share ONE id set —
    # EventItemMatterAttachments is a view onto MatterAttachments, so both
    # must land on the SAME pair of saved files.
    it "resolves one sidecar path per attachment id whichever collection surfaced it" do
      matter_record = pending_record(
        id: 905, source_endpoint: "matter_attachments",
        url: "https://baltimore.legistar1.com/baltimore/attachments/matter-905.pdf"
      )
      event_item_record = pending_record(
        id: 905, source_endpoint: "event_item_matter_attachments",
        url: "https://baltimore.legistar1.com/baltimore/attachments/eventitem-905.pdf"
      )

      expect(service.send(:attachment_pdf_path, matter_record, sway_locale: sway_locale_name))
        .to eq(service.send(:attachment_pdf_path, event_item_record, sway_locale: sway_locale_name))
      expect(service.send(:attachment_txt_path, matter_record, sway_locale: sway_locale_name))
        .to eq(service.send(:attachment_txt_path, event_item_record, sway_locale: sway_locale_name))
      expect(service.send(:attachment_pdf_path, matter_record, sway_locale: sway_locale_name))
        .to eq(attachment_dir.join("attachment-905.pdf"))
    end

    it "leaves the other attachment downloaded when one of two 404s, and the service call returns without raising" do
      stub_matter_attachments([
        matter_attachment(id: 910, name: "Good Testimony"),
        matter_attachment(id: 911, name: "Bad Testimony")
      ])
      stub_matter_histories([])
      stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/910.pdf")
        .to_return(status: 200, body: "%PDF-1.4 good")
      stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/911.pdf")
        .to_return(status: 404, body: "Not Found")

      result = nil
      expect { result = described_class.new(bill: bill).call }.not_to raise_error
      expect(result).to eq([])

      artifact = JSON.parse(File.read(hearings_artifact))
      good = artifact["attachments"].find { |r| r["id"] == 910 }
      bad = artifact["attachments"].find { |r| r["id"] == 911 }
      expect(good["download_status"]).to eq("succeeded")
      expect(bad["download_status"]).to eq("failed")
      expect(File.exist?(attachment_dir.join("attachment-910.pdf"))).to be(true)
      expect(File.exist?(attachment_dir.join("attachment-911.pdf"))).to be(false)
    end

    # @lat: [[attachment-attempts#Attachment download attempts]]
    describe "attachment attempt history recording" do
      let(:service) { described_class.new(bill: bill) }

      before do
        allow(PipelineActivityLogger::Transport).to receive(:dispatch)
      end

      it "records exactly one PipelineActivityLogEntry per attempt with all required attributes across mixed outcomes" do
        rec_success = pending_record(id: 971, url: "https://baltimore.legistar1.com/baltimore/attachments/971.pdf")
        rec_failed = pending_record(id: 972, url: "https://baltimore.legistar1.com/baltimore/attachments/972.pdf")
        rec_budget = pending_record(id: 973, url: "https://baltimore.legistar1.com/baltimore/attachments/973.pdf")

        current_time = 1_000.0
        allow(Process).to receive(:clock_gettime).and_call_original
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) do
          if rec_failed["download_status"] == "failed"
            current_time + described_class.const_get(:DOWNLOAD_BUDGET_SECONDS) + 10.0
          else
            current_time
          end
        end

        stub_request(:get, rec_success["url"]).to_return(status: 200, body: "%PDF-1.4 success bytes")
        stub_request(:get, rec_failed["url"]).to_return(status: 404, body: "Not Found")

        service.send(:download_attachments!, [rec_success, rec_failed, rec_budget], sway_locale: sway_locale_name)

        entries = PipelineActivityLogEntry.where(
          subject_type: "Bill",
          subject_id: bill.id.to_s,
          event_type: "attachment_download_attempt"
        ).order(:id)

        expect(entries.count).to eq(3)

        success_entry = entries.find { |e| e.payload["attachment_id"] == 971 }
        expect(success_entry).not_to be_nil
        expect(success_entry.payload["url"]).to eq(rec_success["url"])
        expect(success_entry.payload["outcome"]).to eq("succeeded")
        expect(success_entry.payload["error"]).to be_nil
        expect(success_entry.payload["bill_external_id"]).to eq(bill.external_id)
        expect(success_entry.payload["sway_locale_id"]).to eq(bill.sway_locale_id)
        expect(success_entry&.severity).to eq("info")

        failed_entry = entries.find { |e| e.payload["attachment_id"] == 972 }
        expect(failed_entry).not_to be_nil
        expect(failed_entry.payload["url"]).to eq(rec_failed["url"])
        expect(failed_entry.payload["outcome"]).to eq("failed")
        expect(failed_entry.payload["error"]).to include("HTTP 404")
        expect(failed_entry&.severity).to eq("info")

        budget_entry = entries.find { |e| e.payload["attachment_id"] == 973 }
        expect(budget_entry).not_to be_nil
        expect(budget_entry.payload["url"]).to eq(rec_budget["url"])
        expect(budget_entry.payload["outcome"]).to eq("skipped_time_budget")
        expect(budget_entry.payload["error"]).to match(/download budget was exhausted/)
        expect(budget_entry&.severity).to eq("info")
      end

      it "appends new attempt rows on subsequent runs rather than replacing or updating prior records" do
        rec1 = pending_record(id: 974, url: "https://baltimore.legistar1.com/baltimore/attachments/974.pdf")
        stub_request(:get, rec1["url"]).to_return(status: 500, body: "Error")

        service.send(:download_attachments!, [rec1], sway_locale: sway_locale_name)
        initial_entries = PipelineActivityLogEntry.where(subject: bill, event_type: "attachment_download_attempt").to_a
        expect(initial_entries.count).to eq(1)
        first_entry = initial_entries.first

        rec1_retry = pending_record(id: 974, url: "https://baltimore.legistar1.com/baltimore/attachments/974.pdf")
        stub_request(:get, rec1_retry["url"]).to_return(status: 200, body: "%PDF-1.4 retried")

        service.send(:download_attachments!, [rec1_retry], sway_locale: sway_locale_name)

        all_entries = PipelineActivityLogEntry.where(subject: bill, event_type: "attachment_download_attempt").order(:id)
        expect(all_entries.count).to eq(2)

        expect(all_entries.first&.id).to eq(first_entry&.id)
        expect(all_entries.first.payload["outcome"]).to eq("failed")
        expect(all_entries.second.payload["outcome"]).to eq("succeeded")
      end

      it "preserves testimony_attachments shape and keys with zero activity log pollution" do
        records = [
          pending_record(id: 975, url: "https://baltimore.legistar1.com/baltimore/attachments/975.pdf")
        ]
        stub_request(:get, records.first["url"]).to_return(status: 200, body: "%PDF-1.4 ok")

        service.send(:download_attachments!, records, sway_locale: sway_locale_name)
        service.send(:persist_testimony!, bill, records)

        provisioning = bill.reload.bill_llm_provisioning
        expect(provisioning).to be_present

        attachments = provisioning.testimony_attachments
        expect(attachments).to be_an(Array)
        expect(attachments).not_to be_empty

        entry = attachments.first
        expected_keys = %w[filename attachment_id download_status extraction_status error].sort
        expect(entry.keys.sort).to eq(expected_keys)

        forbidden_keys = %w[pipeline_activity_log_id attempt_count attempted_at payload url]
        forbidden_keys.each do |key|
          expect(entry).not_to have_key(key)
        end
      end

      it "isolates writer failures so a database raise does not interrupt the download loop" do
        healthy = pending_record(id: 976, url: "https://baltimore.legistar1.com/baltimore/attachments/976.pdf")
        stub_request(:get, healthy["url"]).to_return(status: 200, body: "%PDF-1.4 ok")

        allow(PipelineActivityLogEntry).to receive(:create!).and_raise(ActiveRecord::ActiveRecordError.new("disk error"))
        allow(SwayLogging).to receive(:warn)

        expect {
          service.send(:download_attachments!, [healthy], sway_locale: sway_locale_name)
        }.not_to raise_error

        expect(healthy["download_status"]).to eq("succeeded")
        expect(healthy["error"]).to be_nil
        written_file = attachment_dir.join("attachment-976.pdf")
        expect(File.exist?(written_file)).to be(true)
        expect(File.read(written_file)).to eq("%PDF-1.4 ok")
        expect(SwayLogging).to have_received(:warn).with(/attachment download attempt/i)
      end

      it "adversarially survives PipelineActivityLogger raising an unhandled error and still updates testimony_attachments" do
        healthy = pending_record(id: 977, url: "https://baltimore.legistar1.com/baltimore/attachments/977.pdf")
        stub_request(:get, healthy["url"]).to_return(status: 200, body: "%PDF-1.4 ok")

        allow(PipelineActivityLogger).to receive(:log_attachment_download_attempt!).and_raise(
          RuntimeError.new("simulated logger outage")
        )
        allow(SwayLogging).to receive(:warn)

        expect {
          service.send(:download_attachments!, [healthy], sway_locale: sway_locale_name)
        }.not_to raise_error

        expect(healthy["download_status"]).to eq("succeeded")
        expect(File.exist?(attachment_dir.join("attachment-977.pdf"))).to be(true)
        expect(SwayLogging).to have_received(:warn).with(/failed to record attachment download attempt/i)

        service.send(:persist_testimony!, bill, [healthy])
        attachments = bill.reload.bill_llm_provisioning.testimony_attachments
        expect(attachments.any? { |a| a["attachment_id"] == "977" && a["download_status"] == "succeeded" }).to be(true)
      end

      it "adversarially verifies that multiple runs across multiple attachments append rows without overwriting" do
        rec_a = pending_record(id: 981, url: "https://baltimore.legistar1.com/baltimore/attachments/981.pdf")
        rec_b = pending_record(id: 982, url: "https://baltimore.legistar1.com/baltimore/attachments/982.pdf")

        stub_request(:get, rec_a["url"]).to_return(status: 500, body: "Error 500")
        stub_request(:get, rec_b["url"]).to_return(status: 200, body: "%PDF-1.4 rec_b")

        service.send(:download_attachments!, [rec_a, rec_b], sway_locale: sway_locale_name)
        run1_entries = PipelineActivityLogEntry.where(subject: bill, event_type: "attachment_download_attempt").order(:id).to_a
        expect(run1_entries.count).to eq(2)
        expect(run1_entries.map { |e| [e.payload["attachment_id"], e.payload["outcome"]] }).to eq(
          [[981, "failed"], [982, "succeeded"]]
        )

        rec_a_retry = pending_record(id: 981, url: "https://baltimore.legistar1.com/baltimore/attachments/981.pdf")
        rec_c = pending_record(id: 983, url: "https://baltimore.legistar1.com/baltimore/attachments/983.pdf")
        stub_request(:get, rec_a_retry["url"]).to_return(status: 502, body: "Bad Gateway")
        stub_request(:get, rec_c["url"]).to_return(status: 200, body: "%PDF-1.4 rec_c")

        service.send(:download_attachments!, [rec_a_retry, rec_c], sway_locale: sway_locale_name)
        run2_entries = PipelineActivityLogEntry.where(subject: bill, event_type: "attachment_download_attempt").order(:id).to_a
        expect(run2_entries.count).to eq(4)

        rec_a_retry2 = pending_record(id: 981, url: "https://baltimore.legistar1.com/baltimore/attachments/981.pdf")
        stub_request(:get, rec_a_retry2["url"]).to_return(status: 200, body: "%PDF-1.4 rec_a final")

        service.send(:download_attachments!, [rec_a_retry2], sway_locale: sway_locale_name)
        run3_entries = PipelineActivityLogEntry.where(subject: bill, event_type: "attachment_download_attempt").order(:id).to_a
        expect(run3_entries.count).to eq(5)

        expect(run3_entries[0].id).to eq(run1_entries[0].id)
        expect(run3_entries[1].id).to eq(run1_entries[1].id)
        expect(run3_entries.map { |e| [e.payload["attachment_id"], e.payload["outcome"]] }).to eq(
          [
            [981, "failed"],
            [982, "succeeded"],
            [981, "failed"],
            [983, "succeeded"],
            [981, "succeeded"]
          ]
        )

        expect { run3_entries[0].update!(message: "mutated") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      end

      it "demonstrates that omitting record_download_attempt during budget skip causes the attempt count expectation to fail RED (in-process mutation check)" do
        rec_success = pending_record(id: 971, url: "https://baltimore.legistar1.com/baltimore/attachments/971.pdf")
        rec_failed = pending_record(id: 972, url: "https://baltimore.legistar1.com/baltimore/attachments/972.pdf")
        rec_budget = pending_record(id: 973, url: "https://baltimore.legistar1.com/baltimore/attachments/973.pdf")

        current_time = 1_000.0
        allow(Process).to receive(:clock_gettime).and_call_original
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) do
          if rec_failed["download_status"] == "failed"
            current_time + described_class.const_get(:DOWNLOAD_BUDGET_SECONDS) + 10.0
          else
            current_time
          end
        end

        stub_request(:get, rec_success["url"]).to_return(status: 200, body: "%PDF-1.4 success bytes")
        stub_request(:get, rec_failed["url"]).to_return(status: 404, body: "Not Found")

        allow(service).to receive(:record_download_attempt).and_wrap_original do |original_method, rec, **kwargs|
          unless rec["download_status"] == described_class.const_get(:DOWNLOAD_STATUS_SKIPPED_BUDGET)
            original_method.call(rec, **kwargs)
          end
        end

        service.send(:download_attachments!, [rec_success, rec_failed, rec_budget], sway_locale: sway_locale_name)

        entries = PipelineActivityLogEntry.where(
          subject_type: "Bill",
          subject_id: bill.id.to_s,
          event_type: "attachment_download_attempt"
        ).order(:id)

        expect {
          expect(entries.count).to eq(3)
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /expected: 3.*got: 2/m)

        expect(entries.count).to eq(2)
        expect(entries.map { |e| e.payload["attachment_id"] }).to contain_exactly(971, 972)
      end

      it "records a PipelineActivityLogEntry with skipped_time_budget outcome when download budget is exhausted before starting" do
        record = pending_record(id: 978, url: "https://baltimore.legistar1.com/baltimore/attachments/978.pdf")

        current_time = 1_000.0
        allow(Process).to receive(:clock_gettime).and_call_original
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(
          current_time,
          current_time + described_class.const_get(:DOWNLOAD_BUDGET_SECONDS) + 5.0
        )

        service.send(:download_attachments!, [record], sway_locale: sway_locale_name)

        expect(record["download_status"]).to eq("skipped_time_budget")
        expect(record["error"]).to match(/download budget was exhausted/)

        entry = PipelineActivityLogEntry.find_by!(
          subject: bill,
          event_type: "attachment_download_attempt"
        )
        expect(entry.payload["attachment_id"]).to eq(978)
        expect(entry.payload["outcome"]).to eq("skipped_time_budget")
        expect(entry.payload["error"]).to match(/download budget was exhausted/)
        expect(entry.payload["url"]).to eq(record["url"])
        expect(entry.severity).to eq("info")
      end

      it "records a PipelineActivityLogEntry with failed outcome when attachment has no download url" do
        record = pending_record(id: 984, url: "https://example.com/attachment.pdf").tap { |r| r["url"] = nil }

        service.send(:download_attachments!, [record], sway_locale: sway_locale_name)

        expect(record["download_status"]).to eq("failed")
        expect(record["error"]).to eq("attachment has no download url")

        entry = PipelineActivityLogEntry.find_by!(
          subject: bill,
          event_type: "attachment_download_attempt"
        )
        expect(entry.payload["attachment_id"]).to eq(984)
        expect(entry.payload["outcome"]).to eq("failed")
        expect(entry.payload["error"]).to eq("attachment has no download url")
        expect(entry.payload["url"]).to be_nil
        expect(entry.severity).to eq("info")
      end

      it "records a PipelineActivityLogEntry with failed outcome when magic-byte check fails" do
        record = pending_record(id: 985, url: "https://baltimore.legistar1.com/baltimore/attachments/985.pdf")
        stub_request(:get, record["url"]).to_return(status: 200, body: "NOT A PDF FILE")

        service.send(:download_attachments!, [record], sway_locale: sway_locale_name)

        expect(record["download_status"]).to eq("failed")
        expect(record["error"]).to match(/magic-byte check failed/)

        entry = PipelineActivityLogEntry.find_by!(
          subject: bill,
          event_type: "attachment_download_attempt"
        )
        expect(entry.payload["attachment_id"]).to eq(985)
        expect(entry.payload["outcome"]).to eq("failed")
        expect(entry.payload["error"]).to match(/magic-byte check failed/)
        expect(entry.severity).to eq("info")
      end

      it "records a PipelineActivityLogEntry with failed outcome on Faraday network errors" do
        record = pending_record(id: 986, url: "https://baltimore.legistar1.com/baltimore/attachments/986.pdf")
        stub_request(:get, record["url"]).to_raise(Faraday::ConnectionFailed.new("connection refused"))

        service.send(:download_attachments!, [record], sway_locale: sway_locale_name)

        expect(record["download_status"]).to eq("failed")
        expect(record["error"]).to include("Faraday::ConnectionFailed")

        entry = PipelineActivityLogEntry.find_by!(
          subject: bill,
          event_type: "attachment_download_attempt"
        )
        expect(entry.payload["attachment_id"]).to eq(986)
        expect(entry.payload["outcome"]).to eq("failed")
        expect(entry.payload["error"]).to include("Faraday::ConnectionFailed")
        expect(entry.severity).to eq("info")
      end
    end
  end

  # Pulling text out of the downloaded PDFs: one retry per attachment, the
  # records written into the artifact, and testimony column writes that never
  # destroy what an earlier run captured.
  describe "attachment extraction" do
    let(:service) { described_class.new(bill: bill) }

    def succeeded_record(id:, source_endpoint: "matter_attachments", name: nil)
      {
        "id" => id,
        "name" => name,
        "filename" => "testimony-#{id}.pdf",
        "url" => "https://baltimore.legistar1.com/baltimore/attachments/#{id}.pdf",
        "source_endpoint" => source_endpoint,
        "event_id" => nil,
        "event_item_id" => nil,
        "download_status" => "succeeded",
        "extraction_status" => "pending",
        "error" => nil
      }
    end

    it "extracts a successfully-downloaded PDF once, writes the .txt sibling, and records extraction_status succeeded" do
      record = succeeded_record(id: 950)
      extractor = instance_double(TestimonyTextExtractor, call: "Dear Council Members, I support this bill.")
      allow(TestimonyTextExtractor).to receive(:new).and_return(extractor)

      service.send(:extract_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["extraction_status"]).to eq("succeeded")
      expect(record["error"]).to be_nil
      txt_path = attachment_dir.join("attachment-950.txt")
      expect(File.exist?(txt_path)).to be(true)
      expect(File.read(txt_path)).to eq("Dear Council Members, I support this bill.")
    end

    # TestimonyTextExtractor returns whatever mutool prints, no size limit —
    # written to a companion file then joined into a column.
    # BillPositionsPromptBuilder.max_testimony_chars limits the PROMPT only, not memory or disk.
    it "caps a single attachment's extracted text and records the truncation on the record" do
      record = succeeded_record(id: 954)
      stub_const("#{described_class}::MAX_ATTACHMENT_TEXT_CHARS", 100)
      extractor = instance_double(TestimonyTextExtractor, call: "T" * 5_000)
      allow(TestimonyTextExtractor).to receive(:new).and_return(extractor)

      service.send(:extract_attachments!, [record], sway_locale: sway_locale_name)

      written = File.read(attachment_dir.join("attachment-954.txt"))
      expect(written.length).to be < 5_000
      expect(written).to start_with("T" * 100)
      expect(written).to include("truncated")
      expect(record["extraction_status"]).to eq("succeeded")
      expect(record["error"]).to match(/truncated/i)
    end

    it "caps the composed testimony across attachments before it reaches the column" do
      records = [succeeded_record(id: 955), succeeded_record(id: 956)]
      stub_const("#{described_class}::MAX_COMPOSED_TESTIMONY_CHARS", 120)
      attachment_dir.mkpath
      records.each_with_index do |record, index|
        File.write(attachment_dir.join("attachment-#{record["id"]}.txt"), (index + 1).to_s * 200)
      end

      composed = service.send(:compose_testimony_from_disk, records, sway_locale: sway_locale_name)

      expect(composed.length).to be < 400
      expect(composed).to start_with("1" * 120)
      expect(composed).to include("truncated")
    end

    # The limit above bounded the COLUMN, not memory: every companion file
    # was read fully and joined BEFORE the limit was checked — ~100 million
    # characters resident.
    it "stops reading sidecars once the composed cap is reached" do
      records = (960..964).map { |id| succeeded_record(id: id) }
      stub_const("#{described_class}::MAX_COMPOSED_TESTIMONY_CHARS", 50)
      attachment_dir.mkpath
      records.each do |record|
        File.write(attachment_dir.join("attachment-#{record["id"]}.txt"), "x" * 100)
      end

      read_ids = []
      allow(service).to receive(:read_attachment_txt).and_wrap_original do |original, record, **kwargs|
        read_ids << record["id"]
        original.call(record, **kwargs)
      end

      composed = service.send(:compose_testimony_from_disk, records, sway_locale: sway_locale_name)

      expect(composed).to include("truncated")
      # One file is enough to blow past the 50-character limit; the other four
      # are never opened, let alone held in memory.
      expect(read_ids).to eq([960])
    end

    # The other half: .txt files from before cap_extracted_text existed can
    # be any size on disk, so the per-attachment limit doesn't protect a
    # rebuild. Limit the READ, not just the write.
    it "bounds the read of a legacy sidecar that predates the per-attachment cap" do
      record = succeeded_record(id: 965)
      stub_const("#{described_class}::MAX_ATTACHMENT_TEXT_CHARS", 100)
      attachment_dir.mkpath
      File.write(attachment_dir.join("attachment-965.txt"), "L" * 10_000)

      text = service.send(:read_attachment_txt, record, sway_locale: sway_locale_name)

      expect(text.length).to be <= 200
      expect(text).to start_with("L" * 100)
    end

    # @lat: [[testimony-attachment-rules#Filename rule boundaries]]
    describe "the higher cap for name-confirmed testimony" do
      before do
        stub_const("#{described_class}::MAX_ATTACHMENT_TEXT_CHARS", 100)
        stub_const("#{described_class}::MAX_TESTIMONY_ATTACHMENT_TEXT_CHARS", 300)
      end

      it "uses the base cap for the same testimony filename outside Baltimore" do
        record = succeeded_record(id: 972, name: "Public Testimony.pdf")
        expect(service.send(:attachment_text_char_cap, record, sway_locale: sway_locale_name)).to eq(300)
        expect(service.send(:attachment_text_char_cap, record, sway_locale: "maryland-maryland-united_states")).to eq(100)
        expect(service.send(:attachment_text_char_cap, record, sway_locale: nil)).to eq(100)
      end

      it "does not cut a testimony-named attachment's extracted text at the base cap" do
        record = succeeded_record(id: 972, name: "Community Testimony in Support of 25-0064.pdf")
        extractor = instance_double(TestimonyTextExtractor, call: "T" * 250)
        allow(TestimonyTextExtractor).to receive(:new).and_return(extractor)

        service.send(:extract_attachments!, [record], sway_locale: sway_locale_name)

        written = File.read(attachment_dir.join("attachment-972.txt"))
        expect(written).to eq("T" * 250)
        expect(record["error"]).to be_nil
      end

      it "still cuts a non-testimony-named attachment's extracted text at the base cap" do
        record = succeeded_record(id: 973, name: "Hearing Notice.pdf")
        extractor = instance_double(TestimonyTextExtractor, call: "T" * 250)
        allow(TestimonyTextExtractor).to receive(:new).and_return(extractor)

        service.send(:extract_attachments!, [record], sway_locale: sway_locale_name)

        written = File.read(attachment_dir.join("attachment-973.txt"))
        expect(written.length).to be < 250
        expect(written).to start_with("T" * 100)
        expect(record["error"]).to match(/truncated to 100 chars/)
      end

      # The naive fix: raise the write-time cap and leave the read-time
      # default alone. #read_attachment_txt's default max_bytes and its call
      # into #cap_extracted_text must route through the same per-record cap
      # as the write, or a sidecar the write allowed to grow past the base
      # cap gets truncated straight back down to it on the very next read —
      # which is what #compose_testimony_from_disk always does.
      it "reads a testimony-named sidecar back past the base cap instead of re-truncating it" do
        record = succeeded_record(id: 974, name: "Public Testimony.pdf")
        attachment_dir.mkpath
        File.write(attachment_dir.join("attachment-974.txt"), "L" * 250)

        text = service.send(:read_attachment_txt, record, sway_locale: sway_locale_name)

        expect(text).to eq("L" * 250)
      end

      it "still re-truncates a non-testimony-named sidecar on read even when it exceeds the base cap" do
        record = succeeded_record(id: 975, name: "Attendance Sheet.pdf")
        attachment_dir.mkpath
        File.write(attachment_dir.join("attachment-975.txt"), "L" * 250)

        text = service.send(:read_attachment_txt, record, sway_locale: sway_locale_name)

        expect(text.length).to be <= 200
        expect(text).to start_with("L" * 100)
      end
    end

    # @lat: [[untrusted-text-in-prompts#Why character caps stand in for token budgets]]
    describe "the composed cap boundary" do
      it "does not truncate composed testimony that lands exactly at the composed cap" do
        record = succeeded_record(id: 976)
        stub_const("#{described_class}::MAX_COMPOSED_TESTIMONY_CHARS", 50)
        attachment_dir.mkpath
        File.write(attachment_dir.join("attachment-976.txt"), "x" * 50)

        composed = service.send(:compose_testimony_from_disk, [record], sway_locale: sway_locale_name)

        expect(composed.length).to eq(50)
        expect(composed).not_to include("truncated")
      end

      it "truncates composed testimony that lands one character past the composed cap" do
        record = succeeded_record(id: 977)
        stub_const("#{described_class}::MAX_COMPOSED_TESTIMONY_CHARS", 50)
        attachment_dir.mkpath
        File.write(attachment_dir.join("attachment-977.txt"), "x" * 51)

        composed = service.send(:compose_testimony_from_disk, [record], sway_locale: sway_locale_name)

        expect(composed).to start_with("x" * 50)
        expect(composed).not_to include("x" * 51)
        expect(composed).to include("truncated")
      end
    end

    it "retries exactly once on ExtractionFailed, then records extraction_failed on a second failure" do
      record = succeeded_record(id: 951)
      extractor = instance_double(TestimonyTextExtractor)
      allow(TestimonyTextExtractor).to receive(:new).and_return(extractor)
      allow(extractor).to receive(:call)
        .and_raise(TestimonyTextExtractor::ExtractionFailed, "mutool failed: corrupt xref")
        .twice

      service.send(:extract_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["extraction_status"]).to eq("extraction_failed")
      expect(record["error"]).to include("ExtractionFailed")
      expect(File.exist?(attachment_dir.join("attachment-951.txt"))).to be(false)
    end

    it "retries once and succeeds on the second attempt" do
      record = succeeded_record(id: 952)
      extractor = instance_double(TestimonyTextExtractor)
      allow(TestimonyTextExtractor).to receive(:new).and_return(extractor)
      call_count = 0
      allow(extractor).to receive(:call) do
        call_count += 1
        raise TestimonyTextExtractor::ExtractionFailed, "transient" if call_count == 1

        "Recovered on retry."
      end

      service.send(:extract_attachments!, [record], sway_locale: sway_locale_name)

      expect(call_count).to eq(2)
      expect(record["extraction_status"]).to eq("succeeded")
      expect(File.read(attachment_dir.join("attachment-952.txt"))).to eq("Recovered on retry.")
    end

    it "treats a blank/whitespace-only extraction result as extraction_failed with a no-text-layer error, no retry beyond the one" do
      record = succeeded_record(id: 953)
      extractor = instance_double(TestimonyTextExtractor, call: "   \n  ")
      allow(TestimonyTextExtractor).to receive(:new).and_return(extractor)

      service.send(:extract_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["extraction_status"]).to eq("extraction_failed")
      expect(record["error"]).to match(/no text layer/)
      expect(TestimonyTextExtractor).to have_received(:new).once
    end

    # This used to check extraction_status == pending, making the DEFECT the
    # rule — nothing is pending on a failed download. What matters is
    # unchanged: no extractor runs, no text comes back.
    it "skips extraction for a record whose download did not succeed" do
      record = succeeded_record(id: 954).merge("download_status" => "failed")
      allow(TestimonyTextExtractor).to receive(:new)

      service.send(:extract_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["extraction_status"]).to eq("skipped_download_failed")
      expect(TestimonyTextExtractor).not_to have_received(:new)
    end

    # The same skip, but an earlier run's .txt file is on disk, so
    # compose_testimony_from_disk WILL pick it up — that must not read as
    # pending or as nothing here.
    it "marks a skipped record as reusing a prior run when its sidecar is on disk" do
      record = succeeded_record(id: 955).merge("download_status" => "failed")
      allow(TestimonyTextExtractor).to receive(:new)
      FileUtils.mkdir_p(FetchHearingsServiceSpecHelpers::ATTACHMENTS_ROOT)
      File.write(
        attachment_dir.join("attachment-955.txt"),
        "Testimony captured on an earlier run."
      )

      service.send(:extract_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["extraction_status"]).to eq("reused_prior_run")
      expect(TestimonyTextExtractor).not_to have_received(:new)
      # And it really is the text that reaches the prompt.
      expect(service.send(:compose_testimony_from_disk, [record], sway_locale: sway_locale_name))
        .to eq("Testimony captured on an earlier run.")
    end

    # The third place this wording problem shows up: once the skip budget
    # existed, the loop still labeled every non-succeeded status as a
    # download FAILURE, even one the budget simply never got to.
    it "records a budget-skipped download as not_attempted, not as a download failure" do
      record = succeeded_record(id: 986)
        .merge("download_status" => "skipped_time_budget", "error" => "download budget was exhausted")
      allow(TestimonyTextExtractor).to receive(:new)

      service.send(:extract_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["extraction_status"]).to eq("not_attempted")
      expect(record["error"]).to match(/download budget was exhausted/)
      expect(TestimonyTextExtractor).not_to have_received(:new)
    end

    it "still records a genuinely failed download as skipped_download_failed" do
      record = succeeded_record(id: 987).merge("download_status" => "failed", "error" => "HTTP 404")
      allow(TestimonyTextExtractor).to receive(:new)

      service.send(:extract_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["extraction_status"]).to eq("skipped_download_failed")
    end

    # attachment_txt_present? only checked path.exist?, while composition
    # skips any blank .txt file — a comment papered over the gap with a rule
    # that only held for files THIS version wrote.
    it "does not claim prior-run reuse for a whitespace-only sidecar" do
      record = succeeded_record(id: 957).merge("download_status" => "failed")
      allow(TestimonyTextExtractor).to receive(:new)
      FileUtils.mkdir_p(FetchHearingsServiceSpecHelpers::ATTACHMENTS_ROOT)
      File.write(attachment_dir.join("attachment-957.txt"), "  \n\t \n")

      service.send(:extract_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["extraction_status"]).to eq("skipped_download_failed")
      expect(service.send(:compose_testimony_from_disk, [record], sway_locale: sway_locale_name)).to eq("")
    end

    it "does not claim prior-run reuse for a zero-byte sidecar" do
      record = succeeded_record(id: 958).merge("download_status" => "failed")
      allow(TestimonyTextExtractor).to receive(:new)
      FileUtils.mkdir_p(FetchHearingsServiceSpecHelpers::ATTACHMENTS_ROOT)
      File.write(attachment_dir.join("attachment-958.txt"), "")

      service.send(:extract_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["extraction_status"]).to eq("skipped_download_failed")
      expect(service.send(:compose_testimony_from_disk, [record], sway_locale: sway_locale_name)).to eq("")
    end

    # Sway::Subprocess caps each CALL at 300s plus a grace period; retries
    # once; up to 200 attachments run sequentially — ~34 hours worst case for
    # ONE bill, with nothing above watching the clock.
    it "stops extracting when the per-bill time budget is exhausted and records the remainder" do
      records = [succeeded_record(id: 980), succeeded_record(id: 981), succeeded_record(id: 982)]
      stub_const("#{described_class}::EXTRACTION_BUDGET_SECONDS", 0.0)
      allow(TestimonyTextExtractor).to receive(:new)

      service.send(:extract_attachments!, records, sway_locale: sway_locale_name)

      expect(records.pluck("extraction_status")).to all(eq("skipped_time_budget"))
      expect(records.first["error"]).to match(/extraction budget was exhausted/)
      expect(TestimonyTextExtractor).not_to have_received(:new)
    end

    it "extracts normally while budget remains" do
      records = [succeeded_record(id: 983)]
      extractor = instance_double(TestimonyTextExtractor, call: "Real testimony.")
      allow(TestimonyTextExtractor).to receive(:new).and_return(extractor)

      service.send(:extract_attachments!, records, sway_locale: sway_locale_name)

      expect(records.first["extraction_status"]).to eq("succeeded")
    end

    # The reuse branch overwrote extraction_status but left this run's
    # failure message in error, so the admin list showed reused_prior_run
    # beside a contradictory failure message.
    it "rewrites the error on the reuse branch so the row does not contradict itself" do
      record = succeeded_record(id: 956)
      extractor = instance_double(TestimonyTextExtractor, call: "   ")
      allow(TestimonyTextExtractor).to receive(:new).and_return(extractor)
      FileUtils.mkdir_p(FetchHearingsServiceSpecHelpers::ATTACHMENTS_ROOT)
      File.write(
        attachment_dir.join("attachment-956.txt"),
        "Testimony captured on an earlier run."
      )

      service.send(:extract_attachments!, [record], sway_locale: sway_locale_name)

      expect(record["extraction_status"]).to eq("reused_prior_run")
      expect(record["error"]).to include("could not re-extract")
      expect(record["error"]).to include("no text layer")
      expect(record["error"]).to include("previous run")
    end

    describe "#persist_testimony! (non-destructive re-fetch — REVIEWS C12)" do
      it "self-provisions BillLlmProvisioning, writes testimony_attachments always, and sets extracted_testimony/testimony_fetched_at only when a text succeeded" do
        expect(bill.bill_llm_provisioning).to be_nil
        record = succeeded_record(id: 960).merge("extraction_status" => "succeeded")
        # The .txt file on disk is the source of truth for extracted_testimony,
        # so a successful extraction is represented by that file — not by the
        # texts argument held in memory.
        File.write(
          attachment_dir.join("attachment-960.txt"),
          "Some testimony text."
        )

        service.send(:persist_testimony!, bill, [record])

        provisioning = bill.reload.bill_llm_provisioning
        expect(provisioning).to be_present
        expect(provisioning.extracted_testimony).to eq("Some testimony text.")
        expect(provisioning.testimony_fetched_at).to be_present
        expect(provisioning.testimony_attachments).to eq([
          # attachment_id is the identity evidence_withdrawn?
          # compares run to run; filename stays the label shown in the
          # browser, a String, so the element type stays Hash[String,
          # String?].
          {"filename" => record["filename"], "attachment_id" => record["id"].to_s,
           "download_status" => "succeeded", "extraction_status" => "succeeded", "error" => nil}
        ])
      end

      # Discovery cuts the combined candidate list to the first 200 in
      # arrival order — an accident of loop order, not a judgment call — with
      # only a warn log as the sole trace of dropped evidence.
      it "records candidate truncation durably, in the artifact and on the admin mirror" do
        stub_const("#{described_class}::MAX_ATTACHMENT_CANDIDATES", 2)
        stub_matter_attachments([
          matter_attachment(id: 980, name: "Testimony One"),
          matter_attachment(id: 981, name: "Testimony Two"),
          matter_attachment(id: 982, name: "Testimony Three")
        ])
        stub_matter_histories([])
        [980, 981, 982].each do |id|
          stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/#{id}.pdf")
            .to_return(status: 200, body: "%PDF-1.4 x")
        end
        allow(TestimonyTextExtractor).to receive(:new)
          .and_return(instance_double(TestimonyTextExtractor, call: "Some testimony."))

        described_class.new(bill: bill).call

        artifact = JSON.parse(
          File.read(hearings_artifact)
        )
        expect(artifact["attachment_discovery"]).to include(
          "found" => 3, "kept" => 2, "truncated" => true
        )

        mirror = bill.reload.bill_llm_provisioning.testimony_attachments
        truncation_note = mirror.find { |a| a["download_status"] == "not_attempted" }
        expect(truncation_note).to be_present
        expect(truncation_note["error"]).to include("3")
        expect(truncation_note["error"]).to include("2")
        # Both fields must agree nothing was attempted — this row used to
        # borrow a download-failure status while download_status said
        # not_attempted, blaming an attachment never fetched.
        expect(truncation_note["extraction_status"]).to eq("not_attempted")
      end

      # MAX_ATTACHMENT_CANDIDATES cut the list BEFORE the .pdf filter ran, so
      # non-PDF rows pushed real testimony off the end, while also reporting
      # truncated: true for a set that would fit.
      it "spends the candidate budget on PDFs only, not on images that will be filtered out" do
        stub_const("#{described_class}::MAX_ATTACHMENT_CANDIDATES", 2)
        stub_matter_attachments([
          matter_attachment(id: 990, name: "Cover Photo", filename: "scene.jpg"),
          matter_attachment(id: 991, name: "Testimony One", filename: "testimony-one.pdf"),
          matter_attachment(id: 992, name: "Testimony Two", filename: "testimony-two.pdf")
        ])
        stub_matter_histories([])
        [991, 992].each do |id|
          stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/#{id}.pdf")
            .to_return(status: 200, body: "%PDF-1.4 x")
        end
        allow(TestimonyTextExtractor).to receive(:new)
          .and_return(instance_double(TestimonyTextExtractor, call: "Some testimony."))

        described_class.new(bill: bill).call

        artifact = JSON.parse(
          File.read(hearings_artifact)
        )
        expect(artifact["attachments"].pluck("id")).to contain_exactly(991, 992)

        # found stays the size of the combined list before filtering, since
        # nothing_qualified? relies on that meaning: discovery saw the real
        # list and judged every row not-testimony.
        expect(artifact["attachment_discovery"]).to eq(
          {"found" => 3, "kept" => 2, "recorded" => 2, "truncated" => false, "events_unswept" => [],
           "collections_unswept" => []}
        )

        mirror = bill.reload.bill_llm_provisioning.testimony_attachments
        expect(mirror.pluck("download_status")).not_to include("not_attempted")
      end

      it "records no truncation entry when the candidate set fits" do
        stub_matter_attachments([matter_attachment(id: 983, name: "Testimony One")])
        stub_matter_histories([])
        stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/983.pdf")
          .to_return(status: 200, body: "%PDF-1.4 x")
        allow(TestimonyTextExtractor).to receive(:new)
          .and_return(instance_double(TestimonyTextExtractor, call: "Some testimony."))

        described_class.new(bill: bill).call

        artifact = JSON.parse(
          File.read(hearings_artifact)
        )
        expect(artifact["attachment_discovery"]).to include("truncated" => false)

        mirror = bill.reload.bill_llm_provisioning.testimony_attachments
        expect(mirror.pluck("download_status")).not_to include("not_attempted")
      end

      # The admin status list used to be labelled with a random GUID instead
      # of the human-readable name — a helper hid this behind a parameterized
      # name, so no example caught it.
      it "labels the status mirror with the human-readable attachment name, not the Legistar GUID" do
        stub_matter_attachments([
          matter_attachment(
            id: 992,
            name: "BCFD 25-0064.pdf",
            filename: "17b4a1c3-3b40-40e0-a9d1-622d9b150764.pdf"
          )
        ])
        stub_matter_histories([])
        stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/992.pdf")
          .to_return(status: 404, body: "Not Found")

        described_class.new(bill: bill).call

        mirror = bill.reload.bill_llm_provisioning.testimony_attachments
        expect(mirror.length).to eq(1)
        expect(mirror.first["filename"]).to eq("BCFD 25-0064.pdf")
        expect(mirror.first["filename"]).not_to include("17b4a1c3")
        expect(mirror.first["download_status"]).to eq("failed")
      end

      # A .txt file from before the extractor started cleaning bytes can
      # still hold invalid UTF-8, later raising ArgumentError on a regex
      # applied to extracted_testimony.
      it "scrubs invalid UTF-8 out of a sidecar before composing extracted_testimony" do
        record = succeeded_record(id: 962).merge("extraction_status" => "succeeded")
        File.binwrite(
          attachment_dir.join("attachment-962.txt"),
          "Sidecar testimony \xC3\x28 body."
        )

        service.send(:persist_testimony!, bill, [record])

        composed = bill.reload.bill_llm_provisioning.extracted_testimony
        expect(composed.valid_encoding?).to be(true)
        expect(composed).to include("Sidecar testimony")
        expect(composed).to include("body.")
      end

      it "does not assign extracted_testimony/testimony_fetched_at when zero extractions succeeded" do
        record = succeeded_record(id: 961).merge("extraction_status" => "extraction_failed", "error" => "no text layer")

        service.send(:persist_testimony!, bill, [record])

        provisioning = bill.reload.bill_llm_provisioning
        expect(provisioning.extracted_testimony).to be_nil
        expect(provisioning.testimony_fetched_at).to be_nil
        expect(provisioning.testimony_attachments.first["extraction_status"]).to eq("extraction_failed")
      end

      # Run the service twice: the first succeeds, the second 404s every
      # download. The first run's extracted_testimony must stay UNTOUCHED;
      # only testimony_attachments shows the failures.
      it "leaves a prior run's extracted_testimony and testimony_fetched_at intact when a later re-fetch captures zero testimony" do
        stub_matter_attachments([matter_attachment(id: 970, name: "Public Testimony")])
        stub_matter_histories([])
        pdf_url = "https://baltimore.legistar1.com/baltimore/attachments/970.pdf"
        stub_request(:get, pdf_url).to_return(status: 200, body: "%PDF-1.4 first run")
        extractor = instance_double(TestimonyTextExtractor, call: "First run testimony captured.")
        allow(TestimonyTextExtractor).to receive(:new).and_return(extractor)

        described_class.new(bill: bill).call

        provisioning = bill.reload.bill_llm_provisioning
        expect(provisioning.extracted_testimony).to eq("First run testimony captured.")
        first_fetched_at = provisioning.testimony_fetched_at
        expect(first_fetched_at).to be_present

        # Second run: every download 404s — zero successful extractions.
        travel 1.hour do
          WebMock.reset!
          stub_matter_attachments([matter_attachment(id: 970, name: "Public Testimony")])
          stub_matter_histories([])
          stub_request(:get, pdf_url).to_return(status: 404, body: "Not Found")

          described_class.new(bill: bill).call
        end

        provisioning.reload
        expect(provisioning.extracted_testimony).to eq("First run testimony captured.")
        expect(provisioning.testimony_fetched_at).to eq(first_fetched_at)
        expect(provisioning.testimony_attachments.first["download_status"]).to eq("failed")
      end

      # Keeping the old text is right for a TEMPORARY re-fetch failure and
      # wrong here: a bill whose attachments are ALL re-judged as bill text
      # composes to empty, so old text must not persist.
      it "clears a stale extracted_testimony when discovery found attachments and none qualified as testimony" do
        stub_matter_attachments([matter_attachment(id: 970, name: "Public Testimony")])
        stub_matter_histories([])
        pdf_url = "https://baltimore.legistar1.com/baltimore/attachments/970.pdf"
        stub_request(:get, pdf_url).to_return(status: 200, body: "%PDF-1.4 first run")
        extractor = instance_double(TestimonyTextExtractor, call: "First run testimony captured.")
        allow(TestimonyTextExtractor).to receive(:new).and_return(extractor)

        described_class.new(bill: bill).call

        provisioning = bill.reload.bill_llm_provisioning
        expect(provisioning.extracted_testimony).to eq("First run testimony captured.")

        # Second run: the same attachment is now named as bill text, so the
        # name rules exclude it and the candidate set is empty.
        travel 1.hour do
          WebMock.reset!
          stub_matter_attachments([matter_attachment(id: 970, name: "cc25-0064(1)~1st (Gray)")])
          stub_matter_histories([])

          described_class.new(bill: bill).call
        end

        provisioning.reload
        expect(provisioning.testimony_attachments).to be_empty
        expect(provisioning.extracted_testimony).to be_blank
        expect(provisioning.testimony_present?).to be(false)
      end

      # @lat: [[hearing-testimony-census#Retracting evidence retires the conclusions drawn from it]]
      it "marks existing draft_org_positions evidence-retracted when the evidence is retracted" do
        provisioning = bill.bill_llm_provisioning || bill.create_bill_llm_provisioning!
        provisioning.update!(
          extracted_testimony: "Pre-phase-63 text that was really the bill.",
          draft_org_positions: [
            {"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."},
            {"org_name" => "Beta", "stance" => "oppose", "summary" => "Against it."}
          ]
        )
        # Discovery FOUND attachments and the classifier kept none — what
        # #nothing_qualified? looks for, set directly here the same way the
        # download-failure example below does.
        service.instance_variable_set(:@discovery_found, 2)

        service.send(:persist_testimony!, bill, [])

        provisioning.reload
        drafts = provisioning.draft_org_positions
        expect(provisioning.extracted_testimony).to be_nil
        expect(drafts.pluck("org_name")).to eq(%w[ACME Beta])
        expect(drafts.pluck(BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY)).to all(be_present)
        expect(drafts.pluck("summary")).to eq(["Backs it.", "Against it."])
      end

      # The other direction: retain_with_notice is deliberately NOT a
      # confident answer, since discovery returned nothing — it must not tar
      # the drafts or block approval for nothing.
      it "does NOT mark drafts when discovery itself returned nothing" do
        provisioning = bill.bill_llm_provisioning || bill.create_bill_llm_provisioning!
        drafts = [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}]
        provisioning.update!(
          extracted_testimony: "Testimony from a healthy earlier run.",
          draft_org_positions: drafts
        )

        service.send(:persist_testimony!, bill, [])

        expect(provisioning.reload.draft_org_positions).to eq(drafts)
      end

      # Same rule for the temporary-failure case: candidates existed and the
      # downloads failed. The testimony is real; this run could not read it.
      it "does NOT mark drafts when candidates exist but every download failed" do
        record = succeeded_record(id: 972)
          .merge("download_status" => "failed", "extraction_status" => "skipped_download_failed", "error" => "HTTP 404")
        provisioning = bill.bill_llm_provisioning || bill.create_bill_llm_provisioning!
        drafts = [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}]
        provisioning.update!(
          extracted_testimony: "Testimony from a healthy earlier run.",
          draft_org_positions: drafts
        )
        service.instance_variable_set(:@discovery_found, 1)

        service.send(:persist_testimony!, bill, [record])

        expect(provisioning.reload.draft_org_positions).to eq(drafts)
      end

      it "does NOT clear when discovery itself found nothing — that is ambiguous, not authoritative" do
        provisioning = bill.bill_llm_provisioning || bill.create_bill_llm_provisioning!
        provisioning.update!(extracted_testimony: "Testimony from a healthy earlier run.")

        # @discovery_found stays 0 because both collections came back empty,
        # which is what a Legistar outage looks like from here.
        service.send(:persist_testimony!, bill, [])

        expect(provisioning.reload.extracted_testimony).to eq("Testimony from a healthy earlier run.")
      end

      # The admin list is rewritten on EVERY run, while extracted_testimony's
      # write is conditional — a total outage gives zero discovery, so the
      # column is KEPT while the list rewrites to empty.
      it "says so on the mirror when discovery returned nothing and prior testimony is being retained" do
        provisioning = bill.bill_llm_provisioning || bill.create_bill_llm_provisioning!
        provisioning.update!(
          extracted_testimony: "Testimony from a healthy earlier run.",
          testimony_attachments: [
            {"filename" => "Public Testimony.pdf", "download_status" => "succeeded",
             "extraction_status" => "succeeded", "error" => nil}
          ]
        )

        service.send(:persist_testimony!, bill, [])

        provisioning.reload
        expect(provisioning.extracted_testimony).to eq("Testimony from a healthy earlier run.")
        expect(provisioning.testimony_attachments).not_to be_empty
        entry = provisioning.testimony_attachments.last
        expect(entry["download_status"]).to eq("not_attempted")
        expect(entry["error"]).to match(/no attachments/i)
        expect(entry["error"]).to match(/prior/i)
      end

      # The other half of the same rule: a bill that genuinely has no
      # attachments and no kept testimony has nothing to explain, so it must
      # not grow a permanent warning row for an ordinary empty bill.
      it "adds no discovery-outage entry when there is no prior testimony to explain" do
        provisioning = bill.bill_llm_provisioning || bill.create_bill_llm_provisioning!

        service.send(:persist_testimony!, bill, [])

        expect(provisioning.reload.testimony_attachments).to eq([])
      end

      it "does NOT clear when candidates exist but every download failed" do
        record = succeeded_record(id: 971)
          .merge("download_status" => "failed", "extraction_status" => "skipped_download_failed", "error" => "HTTP 404")
        provisioning = bill.bill_llm_provisioning || bill.create_bill_llm_provisioning!
        provisioning.update!(extracted_testimony: "Testimony from a healthy earlier run.")
        service.instance_variable_set(:@discovery_found, 1)

        service.send(:persist_testimony!, bill, [record])

        expect(provisioning.reload.extracted_testimony).to eq("Testimony from a healthy earlier run.")
      end

      # The zero-success guard only covers NOTHING worked. A PARTIAL re-fetch
      # — A extracts, B 404s — used to rebuild extracted_testimony from this
      # run's successes alone, silently losing B's testimony.
      it "keeps a previously captured attachment's testimony when a later re-fetch loses only that one" do
        stub_matter_attachments([
          matter_attachment(id: 990, name: "Testimony A"),
          matter_attachment(id: 991, name: "Testimony B")
        ])
        stub_matter_histories([])
        url_a = "https://baltimore.legistar1.com/baltimore/attachments/990.pdf"
        url_b = "https://baltimore.legistar1.com/baltimore/attachments/991.pdf"
        stub_request(:get, url_a).to_return(status: 200, body: "%PDF-1.4 a")
        stub_request(:get, url_b).to_return(status: 200, body: "%PDF-1.4 b")
        allow(TestimonyTextExtractor).to receive(:new) do |path|
          instance_double(
            TestimonyTextExtractor,
            call: path.to_s.include?("990") ? "Testimony from A." : "Testimony from B."
          )
        end

        described_class.new(bill: bill).call

        provisioning = bill.reload.bill_llm_provisioning
        expect(provisioning.extracted_testimony).to eq("Testimony from A.\n\nTestimony from B.")
        provisioning.testimony_fetched_at

        # Second run: B's download 404s. A is unchanged.
        travel 1.hour do
          WebMock.reset!
          stub_matter_attachments([
            matter_attachment(id: 990, name: "Testimony A"),
            matter_attachment(id: 991, name: "Testimony B")
          ])
          stub_matter_histories([])
          stub_request(:get, url_a).to_return(status: 200, body: "%PDF-1.4 a")
          stub_request(:get, url_b).to_return(status: 404, body: "Not Found")

          described_class.new(bill: bill).call
        end

        provisioning.reload
        expect(provisioning.extracted_testimony).to eq("Testimony from A.\n\nTestimony from B.")
        expect(provisioning.testimony_attachments.find { |a| a["filename"] == "Testimony B" }["download_status"])
          .to eq("failed")
      end

      # The SAME bug as above, a different door: which collection an
      # attachment shows up in depends on the event fetch succeeding, so
      # keying the filename on source_endpoint flips between runs.
      it "recomposes a prior run's sidecar when the same attachment arrives from the other collection" do
        url_a = "https://baltimore.legistar1.com/baltimore/attachments/975.pdf"
        url_b = "https://baltimore.legistar1.com/baltimore/attachments/976.pdf"
        allow(TestimonyTextExtractor).to receive(:new) do |path|
          instance_double(
            TestimonyTextExtractor,
            call: path.to_s.include?("975") ? "Testimony from A." : "Testimony from B."
          )
        end

        # Run 1: the event fetch succeeds, so deduping keeps A's event-linked
        # entry and B comes from the matter collection.
        stub_matter_attachments([
          matter_attachment(id: 975, name: "Testimony A"),
          matter_attachment(id: 976, name: "Testimony B")
        ])
        stub_matter_histories([6001])
        stub_event_items(6001, [
          {
            "EventItemId" => 8001,
            "EventItemMatterId" => matter_id_int,
            "EventItemMatterAttachments" => [matter_attachment(id: 975, name: "Testimony A")]
          }
        ])
        stub_request(:get, url_a).to_return(status: 200, body: "%PDF-1.4 a")
        stub_request(:get, url_b).to_return(status: 200, body: "%PDF-1.4 b")

        described_class.new(bill: bill).call

        provisioning = bill.reload.bill_llm_provisioning
        expect(provisioning.extracted_testimony).to eq("Testimony from A.\n\nTestimony from B.")
        first_fetched_at = provisioning.testimony_fetched_at

        # Run 2: Events/6001/EventItems 500s (rescued to empty), so A now
        # arrives from the matter collection only — AND its download 404s,
        # the known Pi failure. B is unchanged.
        travel 1.hour do
          WebMock.reset!
          stub_matter_attachments([
            matter_attachment(id: 975, name: "Testimony A"),
            matter_attachment(id: 976, name: "Testimony B")
          ])
          stub_matter_histories([6001])
          stub_event_items(6001, [], status: 500)
          stub_request(:get, url_a).to_return(status: 404, body: "Not Found")
          stub_request(:get, url_b).to_return(status: 200, body: "%PDF-1.4 b")

          described_class.new(bill: bill).call
        end

        provisioning.reload
        expect(provisioning.extracted_testimony).to eq("Testimony from A.\n\nTestimony from B.")
        expect(provisioning.testimony_fetched_at).to eq(first_fetched_at)

        # This example already triggered the defect but only checked
        # extracted_testimony, walking past it — attachment 975 404d on run 2
        # yet its run-1 .txt file IS what fed the composed text.
        mirror = provisioning.testimony_attachments
        reused = mirror.find { |a| a["filename"].to_s == "Testimony A" }
        expect(reused["download_status"]).to eq("failed")
        expect(reused["extraction_status"]).to eq("reused_prior_run")

        fresh = mirror.find { |a| a["filename"].to_s == "Testimony B" }
        expect(fresh["download_status"]).to eq("succeeded")
        expect(fresh["extraction_status"]).to eq("succeeded")

        # And nothing anywhere is left claiming to be pending.
        expect(mirror.pluck("extraction_status")).not_to include("pending")
      end

      # The opposite case: a failed download with NO .txt file on disk
      # contributes nothing, and must look different from the reuse case above.
      # Both used to say "pending".
      it "records a failed download with no sidecar as skipped, not pending" do
        stub_matter_attachments([matter_attachment(id: 981, name: "Testimony Never Fetched")])
        stub_matter_histories([])
        stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/981.pdf")
          .to_return(status: 404, body: "Not Found")

        described_class.new(bill: bill).call

        mirror = bill.reload.bill_llm_provisioning.testimony_attachments
        expect(mirror.length).to eq(1)
        expect(mirror.first["download_status"]).to eq("failed")
        expect(mirror.first["extraction_status"]).to eq("skipped_download_failed")
      end

      # The same fix buys this for free: rebuilding text from disk makes the
      # nothing changed case visible, so a re-fetch capturing identical text
      # no longer flips stale? for no reason.
      it "does not bump testimony_fetched_at when a re-fetch recomposes identical text" do
        stub_matter_attachments([matter_attachment(id: 992, name: "Public Testimony")])
        stub_matter_histories([])
        pdf_url = "https://baltimore.legistar1.com/baltimore/attachments/992.pdf"
        stub_request(:get, pdf_url).to_return(status: 200, body: "%PDF-1.4 x")
        extractor = instance_double(TestimonyTextExtractor, call: "Identical testimony body.")
        allow(TestimonyTextExtractor).to receive(:new).and_return(extractor)

        described_class.new(bill: bill).call
        first_fetched_at = bill.reload.bill_llm_provisioning.testimony_fetched_at

        travel 1.hour do
          described_class.new(bill: bill).call
        end

        provisioning = bill.reload.bill_llm_provisioning
        expect(provisioning.extracted_testimony).to eq("Identical testimony body.")
        expect(provisioning.testimony_fetched_at).to eq(first_fetched_at)
      end

      # @lat: [[hearing-testimony-census#Losing some testimony is not the same as losing all of it]]
      describe "partial withdrawal of contributing testimony" do
        # The shape attachment_status_mirror writes for a contributing
        # record: filename is the label shown to people, and attachment_id is
        # included since every mirror built today carries one.
        def contributing_entry(record)
          {
            "filename" => record["filename"], "attachment_id" => record["id"]&.to_s,
            "download_status" => "succeeded", "extraction_status" => "succeeded", "error" => nil
          }
        end

        def write_sidecar(id, text)
          File.write(attachment_dir.join("attachment-#{id}.txt"), text)
        end

        def provision!(testimony:, attachments:)
          provisioning = bill.bill_llm_provisioning || bill.create_bill_llm_provisioning!
          provisioning.update!(
            extracted_testimony: testimony,
            testimony_attachments: attachments,
            draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}]
          )
          provisioning
        end

        def drafts_retracted?(provisioning)
          BillLlmProvisioning.draft_evidence_retracted?(provisioning.reload.draft_org_positions.first)
        end

        let(:record_a) { succeeded_record(id: 940).merge("extraction_status" => "succeeded") }
        let(:record_b) { succeeded_record(id: 941).merge("extraction_status" => "succeeded") }
        let(:record_c) { succeeded_record(id: 942).merge("extraction_status" => "succeeded") }

        # THE CASE THAT HAD TO FAIL FIRST: A contributed to the stored text
        # and is no longer a candidate at all; B still contributes. The new
        # value is non-empty, different, and strictly less evidence.
        it "marks the drafts when an attachment that contributed to the stored composition stops contributing" do
          provisioning = provision!(
            testimony: "Testimony from A.\n\nTestimony from B.",
            attachments: [contributing_entry(record_a), contributing_entry(record_b)]
          )
          write_sidecar(941, "Testimony from B.")

          service.send(:persist_testimony!, bill, [record_b])

          expect(provisioning.reload.extracted_testimony).to eq("Testimony from B.")
          expect(drafts_retracted?(provisioning)).to be(true)
          # Marked, never destroyed — what every other refusal of this kind does.
          expect(provisioning.draft_org_positions.first["org_name"]).to eq("ACME")
        end

        # @lat: [[hearing-testimony-census#Losing some testimony is not the same as losing all of it]]
        it "does not mark the drafts recovering from a degraded run when the stored census predates attachment_id" do
          legacy_shape = {"download_status" => "succeeded", "extraction_status" => "succeeded", "error" => nil}
          provisioning = provision!(
            testimony: "Testimony from A.\n\nTestimony from B.",
            attachments: [
              legacy_shape.merge("filename" => record_a["filename"]),
              legacy_shape.merge("filename" => record_b["filename"])
            ]
          )

          # Run 2 — Legistar returns nothing at all. The testimony is
          # correctly kept and drafts correctly NOT marked: this run
          # establishes nothing, so it isn't sure enough to condemn anything.
          service.send(:persist_testimony!, bill, [])
          expect(provisioning.reload.extracted_testimony).to eq("Testimony from A.\n\nTestimony from B.")
          expect(drafts_retracted?(provisioning)).to be(false)

          # The census survives, re-labelled: reused_prior_run text really is
          # carried over and counts as contributing, checked BEFORE
          # download_status, so it shows as reused, not a failure.
          carried = Array(provisioning.testimony_attachments)
          expect(carried.pluck("extraction_status")).to eq(%w[reused_prior_run reused_prior_run not_attempted])
          expect(carried.first(2).pluck("filename")).to eq([record_a["filename"], record_b["filename"]])
          expect(carried.first(2).pluck("attachment_id")).to eq([nil, nil])

          # Run 3 — Legistar recovers. A is really gone and B still
          # contributes, but the stored census can't supply an id, so
          # evidence_withdrawn? reports nothing rather than trust a filename.
          write_sidecar(941, "Testimony from B.")
          service.send(:persist_testimony!, bill, [record_b])

          expect(provisioning.reload.extracted_testimony).to eq("Testimony from B.")
          expect(drafts_retracted?(provisioning)).to be(false)
          expect(Array(provisioning.testimony_attachments).first["attachment_id"]).to eq("941")
        end

        # @lat: [[hearing-testimony-census#Losing some testimony is not the same as losing all of it]]
        it "keeps the census when candidates are in hand but none contributes" do
          provisioning = provision!(
            testimony: "Testimony from A.",
            attachments: [contributing_entry(record_a)]
          )
          failed = succeeded_record(id: 950).merge(
            "download_status" => "failed",
            "extraction_status" => "skipped_download_failed",
            "error" => "download failed: 404"
          )

          service.send(:persist_testimony!, bill, [failed])

          expect(provisioning.reload.extracted_testimony).to eq("Testimony from A.")
          expect(drafts_retracted?(provisioning)).to be(false)
          mirror = Array(provisioning.testimony_attachments)
          expect(mirror.pluck("extraction_status"))
            .to eq(%w[reused_prior_run skipped_download_failed not_attempted])
          expect(mirror.first["filename"]).to eq(record_a["filename"])
        end

        # The statuses above were pinned; the sentence the operator READS was
        # not. This route borrowed the empty-discovery row, contradicting the
        # detail row for the attachment this run actually tried.
        it "explains the fourth route in its own words, not the empty-discovery ones" do
          provisioning = provision!(
            testimony: "Testimony from A.",
            attachments: [contributing_entry(record_a)]
          )
          failed = succeeded_record(id: 950).merge(
            "download_status" => "failed",
            "extraction_status" => "skipped_download_failed",
            "error" => "download failed: 404"
          )

          service.send(:persist_testimony!, bill, [failed])

          notice = Array(provisioning.reload.testimony_attachments).last
          expect(notice["error"]).to include("discovered 1 attachment(s) and none of them contributed text")
          expect(notice["error"]).not_to include("Legistar returned no attachments")
          expect(notice["filename"]).to eq("(1 attachment(s) discovered, none produced text)")
        end

        # The other side of that wire: empty discovery must keep the row that
        # names ITS cause, so the assertion above cannot pass on one row
        # rewritten for every route.
        it "keeps the empty-discovery wording when discovery really came back empty" do
          provisioning = provision!(
            testimony: "Testimony from A.",
            attachments: [contributing_entry(record_a)]
          )

          service.send(:persist_testimony!, bill, [])

          notice = Array(provisioning.reload.testimony_attachments).last
          expect(notice["error"]).to include("Legistar returned no attachments")
        end

        # The example above uses two DIFFERENT ids so the retain_with_notice
        # halves never overlap — they can, and when they do, following the
        # wrong row pastes text already in the column.
        it "writes one row per attachment when a carried-forward attachment is also in this run's records" do
          provisioning = provision!(
            testimony: "Testimony from A.\n\nTestimony from B.",
            attachments: service.send(:attachment_status_mirror, [record_a, record_b])
          )
          # 941 downloads but yields no text this run, and its sidecar is gone
          # (an operator cleared the attachments directory, the cure
          # Legislation::Paths documents). No sidecar, so nothing composes.
          failed_b = record_b.merge(
            "extraction_status" => "extraction_failed",
            "error" => "TestimonyTextExtractor::ExtractionFailed: no text layer"
          )

          service.send(:persist_testimony!, bill, [failed_b])

          expect(provisioning.reload.extracted_testimony).to eq("Testimony from A.\n\nTestimony from B.")
          mirror = Array(provisioning.testimony_attachments)
          rows_for_941 = mirror.select { |entry| entry["attachment_id"] == "941" }
          expect(rows_for_941.length).to eq(1)
          expect(rows_for_941.first["extraction_status"]).to eq("reused_prior_run")
          expect(mirror.pluck("extraction_status"))
            .to eq(%w[reused_prior_run reused_prior_run not_attempted])
          expect(mirror.first["attachment_id"]).to eq("940")
        end

        # Reason 3 above, carried to the consumer that acts on it: nothing
        # else covers a withdrawal ACROSS a retain_with_notice run whose
        # records overlap the stored census.
        it "still flags a withdrawal after a retain run that also had a row for the carried attachment" do
          provisioning = provision!(
            testimony: "Testimony from A.\n\nTestimony from B.",
            attachments: service.send(:attachment_status_mirror, [record_a, record_b])
          )
          failed_b = record_b.merge(
            "extraction_status" => "extraction_failed",
            "error" => "TestimonyTextExtractor::ExtractionFailed: no text layer"
          )

          # Run N — 941 is in both halves. Text kept, nothing condemned: this
          # run established nothing about whether 941 is really gone.
          service.send(:persist_testimony!, bill, [failed_b])
          expect(drafts_retracted?(provisioning)).to be(false)

          # Run N+1 — Legistar recovers and 940 alone composes. 941's
          # testimony has now genuinely left the column, and the drafts rest
          # on evidence that is half missing.
          write_sidecar(940, "Testimony from A.")
          service.send(:persist_testimony!, bill, [record_a])

          expect(provisioning.reload.extracted_testimony).to eq("Testimony from A.")
          expect(drafts_retracted?(provisioning)).to be(true)
        end

        # @lat: [[hearing-testimony-census#Losing some testimony is not the same as losing all of it]]
        it "marks the drafts when one of two attachments sharing a display name stops contributing" do
          shared = "25-0064 News Paper Ad.pdf"
          twin_a = record_a.merge("name" => shared, "extraction_status" => "succeeded")
          twin_b = record_b.merge("name" => shared, "extraction_status" => "succeeded")
          provisioning = provision!(
            testimony: "Testimony from A.\n\nTestimony from B.",
            attachments: service.send(:attachment_status_mirror, [twin_a, twin_b])
          )
          write_sidecar(941, "Testimony from B.")

          service.send(:persist_testimony!, bill, [twin_b])

          expect(provisioning.reload.extracted_testimony).to eq("Testimony from B.")
          expect(drafts_retracted?(provisioning)).to be(true)
        end

        # Boundary 1 — TEXT INSERTED IN THE MIDDLE. The stored string is NOT
        # contained in the new one, so a containment check would stamp the
        # drafts. Nothing was actually withdrawn.
        it "does not mark the drafts when a new attachment is inserted between two that still contribute" do
          provisioning = provision!(
            testimony: "Testimony from A.\n\nTestimony from C.",
            attachments: [contributing_entry(record_a), contributing_entry(record_c)]
          )
          write_sidecar(940, "Testimony from A.")
          write_sidecar(941, "Testimony from B.")
          write_sidecar(942, "Testimony from C.")

          service.send(:persist_testimony!, bill, [record_a, record_b, record_c])

          composed = provisioning.reload.extracted_testimony
          expect(composed).to eq("Testimony from A.\n\nTestimony from B.\n\nTestimony from C.")
          expect(composed).not_to include("Testimony from A.\n\nTestimony from C.")
          expect(drafts_retracted?(provisioning)).to be(false)
        end

        # Boundary 2 — TEXT ADDED AT THE END. The set of contributors only grew.
        it "does not mark the drafts when the contributor set only grows" do
          provisioning = provision!(
            testimony: "Testimony from A.",
            attachments: [contributing_entry(record_a)]
          )
          write_sidecar(940, "Testimony from A.")
          write_sidecar(941, "Testimony from B.")

          service.send(:persist_testimony!, bill, [record_a, record_b])

          expect(provisioning.reload.extracted_testimony).to eq("Testimony from A.\n\nTestimony from B.")
          expect(drafts_retracted?(provisioning)).to be(false)
        end

        # Boundary 3 — THE FIRST TIME TEXT IS COMPOSED. There was no stored
        # value to destroy. Drafts on such a row rest on the bill diff or
        # supplemental_testimony, already handled elsewhere.
        it "does not mark the drafts on a first composition" do
          provisioning = provision!(testimony: nil, attachments: nil)
          write_sidecar(940, "Testimony from A.")

          service.send(:persist_testimony!, bill, [record_a])

          expect(provisioning.reload.extracted_testimony).to eq("Testimony from A.")
          expect(drafts_retracted?(provisioning)).to be(false)
        end

        # Boundary 4 — CUT OFF AT A DIFFERENT POINT: past
        # MAX_COMPOSED_TESTIMONY_CHARS the loop stops, so B's text leaves the
        # column though B is still a candidate. A containment check fails
        # here too.
        it "does not mark the drafts when the composed value changed only because it re-truncated" do
          stub_const("#{described_class}::MAX_COMPOSED_TESTIMONY_CHARS", 30)
          provisioning = provision!(
            testimony: "#{"a" * 20}\n\n#{"b" * 20}",
            attachments: [contributing_entry(record_a), contributing_entry(record_b)]
          )
          write_sidecar(940, "a" * 40)
          write_sidecar(941, "b" * 20)

          service.send(:persist_testimony!, bill, [record_a, record_b])

          composed = provisioning.reload.extracted_testimony
          expect(composed).to start_with("a" * 30)
          expect(composed).to include("truncated")
          expect(composed).not_to include("b" * 20)
          expect(drafts_retracted?(provisioning)).to be(false)
        end

        # Boundary 5 — the list also carries MADE-UP rows naming no
        # attachment; a run whose candidates newly fit drops the truncation
        # row, which is not a withdrawal on either side of the comparison.
        it "does not treat a synthetic mirror row as a withdrawn attachment" do
          provisioning = provision!(
            testimony: "Testimony from A.",
            attachments: [
              contributing_entry(record_a),
              {"filename" => "(3 attachments not fetched)", "download_status" => "not_attempted",
               "extraction_status" => "not_attempted", "error" => "discovery found 5 PDF attachments"}
            ]
          )
          write_sidecar(940, "Testimony from A.")
          write_sidecar(941, "Testimony from B.")

          service.send(:persist_testimony!, bill, [record_a, record_b])

          expect(provisioning.reload.extracted_testimony).to eq("Testimony from A.\n\nTestimony from B.")
          expect(drafts_retracted?(provisioning)).to be(false)
        end

        # Boundary 6 — a row that never contributed text cannot be withdrawn. A
        # failed download drops out of the candidate set on the next run all the
        # time, and the drafts never rested on it.
        it "does not mark the drafts when the attachment that disappeared contributed no text" do
          failed = succeeded_record(id: 943)
            .merge("download_status" => "failed", "extraction_status" => "skipped_download_failed")
          provisioning = provision!(
            testimony: "Testimony from A.",
            attachments: [
              contributing_entry(record_a),
              {"filename" => failed["filename"], "download_status" => "failed",
               "extraction_status" => "skipped_download_failed", "error" => "HTTP 404"}
            ]
          )
          write_sidecar(940, "Testimony from A.")
          write_sidecar(941, "Testimony from B.")

          service.send(:persist_testimony!, bill, [record_a, record_b])

          expect(provisioning.reload.extracted_testimony).to eq("Testimony from A.\n\nTestimony from B.")
          expect(drafts_retracted?(provisioning)).to be(false)
        end

        # A reused .txt file IS a contributor: compose_testimony_from_disk
        # reads every such file, so reused_prior_run text is in the prompt
        # exactly like fresh text. Losing one is a withdrawal.
        it "counts a reused prior-run sidecar as a contributor" do
          provisioning = provision!(
            testimony: "Testimony from A.\n\nTestimony from B.",
            attachments: [
              contributing_entry(record_a).merge("extraction_status" => "reused_prior_run"),
              contributing_entry(record_b)
            ]
          )
          write_sidecar(941, "Testimony from B.")

          service.send(:persist_testimony!, bill, [record_b])

          expect(provisioning.reload.extracted_testimony).to eq("Testimony from B.")
          expect(drafts_retracted?(provisioning)).to be(true)
        end

        # The migration adding this column landed one day before
        # the writer switched from the raw GUID to the display name — a
        # mirror in that window holds a GUID and no id.
        it "does not mark the drafts when the stored mirror predates attachment_id and holds the raw upstream GUID" do
          legacy_guid_entry = {
            "filename" => "17b4a1c3-3b40-40e0-a9d1-622d9b150764.pdf",
            "download_status" => "succeeded", "extraction_status" => "succeeded", "error" => nil
          }
          provisioning = provision!(
            testimony: "Testimony from A.",
            attachments: [legacy_guid_entry]
          )
          named_record_a = record_a.merge("name" => "BCFD 25-0064.pdf")
          write_sidecar(940, "Testimony from A.")
          write_sidecar(941, "Testimony from B.")

          service.send(:persist_testimony!, bill, [named_record_a, record_b])

          expect(provisioning.reload.extracted_testimony).to eq("Testimony from A.\n\nTestimony from B.")
          expect(drafts_retracted?(provisioning)).to be(false)
        end

        # COVERAGE FOR THE COMPARISON PRODUCTION ACTUALLY RUNS: every other
        # fixture keeps name and filename moving together, so a defect in the
        # by-id branch itself could pass unnoticed without this one.
        it "does not mark the drafts when attachment_id matches even though the display name changed" do
          provisioning = provision!(
            testimony: "Testimony from A.",
            attachments: service.send(:attachment_status_mirror, [record_a.merge("name" => "Old Title.pdf")])
          )
          renamed_record_a = record_a.merge("name" => "New Title.pdf")
          write_sidecar(940, "Testimony from A.")
          write_sidecar(941, "Testimony from B.")

          service.send(:persist_testimony!, bill, [renamed_record_a, record_b])

          expect(provisioning.reload.extracted_testimony).to eq("Testimony from A.\n\nTestimony from B.")
          expect(drafts_retracted?(provisioning)).to be(false)
        end
      end
    end
  end

  # End-to-end proof that cleaning bytes as they come in from Legistar stops
  # one bad document from killing the run — a badly encoded name used to
  # abort fetch_hearings for every REMAINING bill.
  describe "invalid UTF-8 from Legistar (A2-WR-01)" do
    it "degrades per-attachment instead of killing the stage" do
      # Raw bytes, NOT `.to_json` — an invalid byte sequence cannot survive being
      # re-encoded by Ruby, which is the whole point here.
      dirty = %([{"MatterAttachmentId":975,"MatterAttachmentName":"Public Testimony caf\xC3\x28e 25-0064","MatterAttachmentFileName":"caf\xC3\x28e.pdf","MatterAttachmentHyperlink":"https://baltimore.legistar1.com/baltimore/attachments/975.pdf","MatterAttachmentLastModifiedUtc":"2025-01-01T00:00:00"}]).b
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/#{matter_id_int}/Attachments})
        .to_return(status: 200, body: dirty, headers: {"Content-Type" => "application/json"})
      stub_matter_histories([])
      stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/975.pdf")
        .to_return(status: 200, body: "%PDF-1.4 x")
      allow(TestimonyTextExtractor).to receive(:new)
        .and_return(instance_double(TestimonyTextExtractor, call: "Testimony body."))

      expect { described_class.new(bill: bill).call }.not_to raise_error

      provisioning = bill.reload.bill_llm_provisioning
      expect(provisioning.extracted_testimony).to eq("Testimony body.")
      mirror = provisioning.testimony_attachments.first
      expect(mirror["download_status"]).to eq("succeeded")
      expect(mirror["filename"]).to be_a(String)
      expect(mirror["filename"].valid_encoding?).to be(true)
      # The artifact is written with JSON.pretty_generate — the second place the
      # same bytes could raise.
      artifact = File.read(hearings_artifact)
      expect(JSON.parse(artifact)["attachments"].first["id"]).to eq(975)
    end
  end

  # call_discover's own comment claims the attachment steps never raise, but
  # file writes, the mutool subprocess, and the ActiveRecord save were all
  # unguarded.
  describe "failure isolation (PROD-CR-02)" do
    let(:service) { described_class.new(bill: bill) }

    # These match the helpers in the describe blocks above on purpose —
    # sig-test/object_spec_methods.rbs declares ONE signature per helper name
    # for the whole suite, so these have to stay compatible.
    def pending_record(id:, url:, source_endpoint: "matter_attachments", filename: nil)
      {
        "id" => id,
        "filename" => filename || "testimony-#{id}.pdf",
        "url" => url,
        "source_endpoint" => source_endpoint,
        "event_id" => nil,
        "event_item_id" => nil,
        "download_status" => "pending",
        "extraction_status" => "pending",
        "error" => nil
      }
    end

    def succeeded_record(id:, source_endpoint: "matter_attachments", name: nil)
      pending_record(
        id: id,
        url: "https://baltimore.legistar1.com/baltimore/attachments/#{id}.pdf",
        source_endpoint: source_endpoint
      ).merge("download_status" => "succeeded", "name" => name)
    end

    it "records a per-attachment failure instead of raising when the PDF write fails" do
      record = pending_record(id: 980, url: "https://baltimore.legistar1.com/baltimore/attachments/980.pdf")
      stub_request(:get, record["url"]).to_return(status: 200, body: "%PDF-1.4 ok")
      allow(File).to receive(:binwrite).and_raise(Errno::ENOSPC)

      expect { service.send(:download_attachments!, [record], sway_locale: sway_locale_name) }.not_to raise_error
      expect(record["download_status"]).to eq("failed")
      expect(record["error"]).to match(/write failed.*ENOSPC/)
    end

    it "keeps downloading the remaining attachments after one write failure" do
      first = pending_record(id: 981, url: "https://baltimore.legistar1.com/baltimore/attachments/981.pdf")
      second = pending_record(id: 982, url: "https://baltimore.legistar1.com/baltimore/attachments/982.pdf")
      stub_request(:get, first["url"]).to_return(status: 200, body: "%PDF-1.4 one")
      stub_request(:get, second["url"]).to_return(status: 200, body: "%PDF-1.4 two")
      call_count = 0
      allow(File).to receive(:binwrite).and_wrap_original do |original, path, bytes|
        call_count += 1
        raise Errno::EACCES, "Permission denied" if call_count == 1

        original.call(path, bytes)
      end

      service.send(:download_attachments!, [first, second], sway_locale: sway_locale_name)

      expect(first["download_status"]).to eq("failed")
      expect(second["download_status"]).to eq("succeeded")
    end

    it "records a per-attachment failure instead of raising when the .txt sidecar write fails" do
      record = succeeded_record(id: 983)
      extractor = instance_double(TestimonyTextExtractor, call: "Testimony body.")
      allow(TestimonyTextExtractor).to receive(:new).and_return(extractor)
      allow(File).to receive(:write).and_raise(Errno::EACCES)

      expect { service.send(:extract_attachments!, [record], sway_locale: sway_locale_name) }.not_to raise_error
      expect(record["extraction_status"]).to eq("extraction_failed")
      expect(record["error"]).to match(/write failed.*EACCES/)
    end

    # Errno::ENOENT is the realistic one on the Pi: TestimonyTextExtractor
    # deliberately skips MupdfExtractor#preflight!, so nothing checks mutool
    # is installed before the run starts.
    it "records a per-attachment failure instead of raising when mutool is absent" do
      record = succeeded_record(id: 984)
      allow(Sway::Subprocess).to receive(:capture3).and_raise(Errno::ENOENT)

      expect { service.send(:extract_attachments!, [record], sway_locale: sway_locale_name) }.not_to raise_error
      expect(record["extraction_status"]).to eq("extraction_failed")
      expect(record["error"]).to match(/mutool unavailable/)
    end

    # A database failure IS a failure of this bill, since the row belongs to
    # it — unlike the per-attachment paths, this one still raises, but as
    # BillProcessingError.
    it "raises BillProcessingError, not the raw AR error, when the provisioning save fails" do
      record = succeeded_record(id: 985).merge("extraction_status" => "succeeded")
      allow_any_instance_of(BillLlmProvisioning)
        .to receive(:save!)
        .and_raise(ActiveRecord::StatementInvalid.new("SQLite3::BusyException: database is locked"))

      expect { service.send(:persist_testimony!, bill, [record]) }
        .to raise_error(BillProcessingError, /testimony persist failed.*StatementInvalid/)
    end

    # The two comments above establish a filesystem error at a write is NOT a
    # BillProcessingError. That was applied to the two writes this work
    # ADDED, not the write already in the same call chain.
    it "raises BillProcessingError, not the raw Errno, when the hearings artifact write fails" do
      allow(File).to receive(:write).and_raise(Errno::ENOSPC)

      expect { described_class.new(bill: bill).call }
        .to raise_error(BillProcessingError, /artifact write failed.*ENOSPC/)
    end

    it "raises BillProcessingError when the hearings artifact DIRECTORY cannot be created" do
      allow_any_instance_of(Pathname).to receive(:mkpath).and_raise(Errno::EROFS)

      expect { described_class.new(bill: bill).call }
        .to raise_error(BillProcessingError, /artifact write failed.*EROFS/)
    end
  end

  # @lat: [[untrusted-text-in-prompts#Why the model judges the document rather than its name]]
  describe "content-based classification of undecided attachments" do
    let(:content_classifier_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }
    let(:captured_classification_prompts) { [] }

    # The model stage is turned off in the test environment (.build returns
    # new(llm: nil)), so an example that wants to see what the model was actually
    # asked has to wire one up by hand.
    def stub_content_classifier(payload)
      allow(Testimony::AttachmentClassifier).to receive(:build)
        .and_return(Testimony::AttachmentClassifier.new(llm: content_classifier_adapter))
      allow(content_classifier_adapter).to receive(:generate_testimony_classification) do |**kwargs|
        captured_classification_prompts << kwargs[:prompt]
        payload
      end
      nil
    end

    # THE MAIN POINT. "Attachment 3" contains no keyword either list can decide
    # on, so it reaches the model; its extracted text is plainly the bill.
    it "sends the document's extracted text to the model, not just its name" do
      stub_content_classifier({"classifications" => [{"index" => 0, "label" => "not_testimony"}]})
      stub_matter_attachments([matter_attachment(id: 700, name: "Attachment 3")])
      stub_matter_histories([])
      stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/700.pdf")
        .to_return(status: 200, body: "%PDF-1.4 x")
      allow(TestimonyTextExtractor).to receive(:new).and_return(
        instance_double(
          TestimonyTextExtractor,
          call: "AN ORDINANCE CONCERNING Zoning - Conditional Use Conversions"
        )
      )

      described_class.new(bill: bill).call

      expect(captured_classification_prompts.length).to eq(1)
      expect(captured_classification_prompts.first.user_message)
        .to include("AN ORDINANCE CONCERNING Zoning - Conditional Use Conversions")
    end

    # When in doubt, say no: an undecided document nobody could read is
    # REJECTED, since letting it in would claim evidence never seen. The
    # model isn't asked at all — nothing to ask about.
    it "asks the model nothing about an undecided document whose text could not be extracted" do
      stub_content_classifier({"classifications" => []})
      stub_matter_attachments([matter_attachment(id: 701, name: "Attachment 4")])
      stub_matter_histories([])
      stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/701.pdf")
        .to_return(status: 200, body: "%PDF-1.4 x")
      allow(TestimonyTextExtractor).to receive(:new)
        .and_return(instance_double(TestimonyTextExtractor, call: "   "))

      described_class.new(bill: bill).call

      expect(captured_classification_prompts).to be_empty
      expect(bill.reload.bill_llm_provisioning.extracted_testimony).to be_blank
    end

    # ...and it doesn't happen quietly: attachmentDisposition shows any
    # non-succeeded row as no_text, telling the admin to paste it by hand —
    # the record stays KEPT so that trace survives.
    it "still surfaces an undecided document it could not read on the admin status mirror" do
      stub_content_classifier({"classifications" => []})
      stub_matter_attachments([matter_attachment(id: 702, name: "Attachment 5")])
      stub_matter_histories([])
      stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/702.pdf")
        .to_return(status: 200, body: "%PDF-1.4 x")
      allow(TestimonyTextExtractor).to receive(:new)
        .and_return(instance_double(TestimonyTextExtractor, call: ""))

      described_class.new(bill: bill).call

      mirror = bill.reload.bill_llm_provisioning.testimony_attachments
      expect(mirror.length).to eq(1)
      expect(mirror.first["filename"]).to eq("Attachment 5")
      expect(mirror.first["extraction_status"]).to eq("extraction_failed")
      expect(mirror.first["error"]).to include("no text layer")
    end

    # WHY the keyword pass stays a first filter instead of extracting
    # everything: an attachment the name rules reject is still never fetched,
    # limiting extraction work to the undecided third.
    it "never downloads an attachment the keyword rules already denied" do
      stub_content_classifier({"classifications" => []})
      stub_matter_attachments([matter_attachment(id: 703, name: "25-0064~3rd Reader")])
      stub_matter_histories([])

      described_class.new(bill: bill).call

      expect(a_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/703.pdf"))
        .not_to have_been_made
      expect(captured_classification_prompts).to be_empty
    end

    # THE NORMAL, SETTLED CASE: once a document is judged from its contents,
    # the saved row answers for it and prefilter settles it before a single
    # byte is fetched, so a later run pays nothing again.
    it "neither downloads nor re-classifies a document with a cached verdict" do
      stub_content_classifier({"classifications" => []})
      TestimonyAttachmentClassification.create!(
        sway_locale: bill.sway_locale,
        source_endpoint: "matter_attachments", attachment_id: 704,
        label: "not_testimony",
        model: Testimony::AttachmentClassifier::CLASSIFIER_MODEL,
        prompt_version: Testimony::ClassificationPromptBuilder::PROMPT_VERSION
      )
      stub_matter_attachments([matter_attachment(id: 704, name: "Attachment 6")])
      stub_matter_histories([])

      described_class.new(bill: bill).call

      expect(a_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/704.pdf"))
        .not_to have_been_made
      expect(captured_classification_prompts).to be_empty
      expect(bill.reload.bill_llm_provisioning.testimony_attachments).to be_empty
    end

    # The point of the whole exercise: the model read the document and said
    # no, and its text does NOT reach extracted_testimony — removing the
    # record from the working set is what achieves that.
    it "keeps a content-denied document's text out of extracted_testimony" do
      stub_content_classifier(
        {"classifications" => [{"index" => 0, "label" => "not_testimony"}]}
      )
      stub_matter_attachments([
        matter_attachment(id: 705, name: "Attachment 7"),
        matter_attachment(id: 706, name: "Public Testimony 25-0064")
      ])
      stub_matter_histories([])
      [705, 706].each do |id|
        stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/#{id}.pdf")
          .to_return(status: 200, body: "%PDF-1.4 x")
      end
      allow(TestimonyTextExtractor).to receive(:new) do |path|
        body = File.basename(path.to_s).include?("705") ? "AN ORDINANCE CONCERNING Zoning." : "I support this bill."
        instance_double(TestimonyTextExtractor, call: body)
      end

      described_class.new(bill: bill).call

      provisioning = bill.reload.bill_llm_provisioning
      expect(provisioning.extracted_testimony).to eq("I support this bill.")
      # The denial stays VISIBLE: the denied record leaves the
      # working set but keeps a mirror row carrying the verdict and the way
      # out, appended after the contributing rows.
      expect(provisioning.testimony_attachments.pluck("filename"))
        .to eq(["Public Testimony 25-0064", "Attachment 7"])
      denied_row = provisioning.testimony_attachments.last
      expect(denied_row["extraction_status"]).to eq("content_denied")
      expect(denied_row["error"]).to include("not testimony")
    end

    # The mirror is rewritten by the very next run, so it can't be the only
    # record of a decision that REMOVES EVIDENCE — the artifact dropped the
    # denied record.
    it "keeps a content-denied record in the durable artifact, with the census matching" do
      stub_content_classifier(
        {"classifications" => [{"index" => 0, "label" => "not_testimony"}]}
      )
      stub_matter_attachments([
        matter_attachment(id: 715, name: "Attachment 15"),
        matter_attachment(id: 716, name: "Public Testimony 25-0064")
      ])
      stub_matter_histories([])
      [715, 716].each do |id|
        stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/#{id}.pdf")
          .to_return(status: 200, body: "%PDF-1.4 x")
      end
      allow(TestimonyTextExtractor).to receive(:new) do |path|
        body = File.basename(path.to_s).include?("715") ? "AN ORDINANCE CONCERNING Zoning." : "I support this bill."
        instance_double(TestimonyTextExtractor, call: body)
      end

      described_class.new(bill: bill).call

      artifact = JSON.parse(
        File.read(hearings_artifact)
      )
      denied = artifact["attachments"].find { |record| record["id"] == 715 }
      expect(denied).to be_present
      expect(denied["extraction_status"]).to eq("content_denied")
      # The full record — the fields the mirror deliberately does not carry —
      # is what makes the artifact the durable copy.
      expect(denied["source_endpoint"]).to be_present
      # recorded is the count reconcilable against the list beside it:
      # downloaded/extracted records, denials included. NOT kept, assigned
      # before name rules run and always the cap's larger number.
      expect(artifact["attachment_discovery"]["recorded"]).to eq(artifact["attachments"].length)
    end

    # THE CASE THE EXAMPLE ABOVE CAN'T SEE: both fixtures survive prefilter,
    # so kept and recorded are accidentally equal there. A real bill settles
    # most attachments first.
    it "counts a name-rejected candidate in kept and not in recorded" do
      stub_content_classifier({"classifications" => []})
      stub_matter_attachments([
        # NameRules :bill_text — rejected on the name, never downloaded.
        matter_attachment(id: 717, name: "25-0064~3rd Reader"),
        matter_attachment(id: 718, name: "Public Testimony 25-0064")
      ])
      stub_matter_histories([])
      stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/718.pdf")
        .to_return(status: 200, body: "%PDF-1.4 x")
      allow(TestimonyTextExtractor).to receive(:new)
        .and_return(instance_double(TestimonyTextExtractor, call: "I support this bill."))

      described_class.new(bill: bill).call

      artifact = JSON.parse(
        File.read(hearings_artifact)
      )
      census = artifact["attachment_discovery"]
      expect(artifact["attachments"].pluck("id")).to eq([718])
      expect(census["recorded"]).to eq(artifact["attachments"].length)
      # The gap IS the finding: two PDF candidates, one record. A reader
      # reconciling the payload can now account for the missing one.
      expect(census["kept"]).to eq(2)
      expect(census["recorded"]).to eq(1)
    end

    # THE OVERLAP THE ROUTE-4 SUMMARY ROW USED TO MISCOUNT: built from
    # records plus content-denied ones, and a denied document can have
    # downloaded and extracted fine before rejection.
    it "counts the denied rows too when route 4 summarizes a mixed failure" do
      bill.create_bill_llm_provisioning!(extracted_testimony: "text a prior run captured")
      stub_content_classifier(
        {"classifications" => [{"index" => 0, "label" => "not_testimony"}]}
      )
      stub_matter_attachments([
        # Undecided on its name, so it reaches the model — which denies it.
        matter_attachment(id: 719, name: "Attachment 19"),
        # Decided testimony on its name, and its download then fails.
        matter_attachment(id: 720, name: "Public Testimony 25-0064")
      ])
      stub_matter_histories([])
      stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/719.pdf")
        .to_return(status: 200, body: "%PDF-1.4 x")
      stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/720.pdf")
        .to_return(status: 500, body: "")
      allow(TestimonyTextExtractor).to receive(:new).and_return(
        instance_double(TestimonyTextExtractor, call: "AN ORDINANCE CONCERNING Zoning.")
      )

      described_class.new(bill: bill).call

      provisioning = bill.reload.bill_llm_provisioning
      # Route 4: candidates in hand, none contributing, so the prior testimony
      # is kept and the run says so rather than deleting evidence.
      expect(provisioning.extracted_testimony).to eq("text a prior run captured")
      mirror = provisioning.testimony_attachments
      expect(mirror.pluck("extraction_status")).to eq(%w[skipped_download_failed content_denied not_attempted])

      # fetch(-1), not last: the summary row is required to be there, and an
      # empty mirror should fail this example rather than compare against nil.
      notice = mirror.fetch(-1)
      expect(notice["error"]).to include("discovered 2 attachment(s) and none of them contributed text")
      expect(notice["filename"]).to eq("(2 attachment(s) discovered, none produced text)")
      # False of the denied row, whose download and extraction both worked.
      expect(notice["error"]).not_to include("every download or extraction failed")
    end

    # @lat: [[hearing-testimony-census#Why an all-denied run explains itself]]
    it "explains an all-denied retract on the admin mirror" do
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "text a prior run captured",
        draft_org_positions: [{"org_name" => "Org X", "stance" => "support", "summary" => "s"}]
      )
      stub_content_classifier({"classifications" => [{"index" => 0, "label" => "not_testimony"}]})
      stub_matter_attachments([matter_attachment(id: 708, name: "Attachment 10")])
      stub_matter_histories([])
      stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/708.pdf")
        .to_return(status: 200, body: "%PDF-1.4 x")
      allow(TestimonyTextExtractor).to receive(:new).and_return(
        instance_double(TestimonyTextExtractor, call: "AN ORDINANCE CONCERNING nothing at all")
      )

      described_class.new(bill: bill).call

      provisioning = bill.reload.bill_llm_provisioning
      expect(provisioning.extracted_testimony).to be_nil
      expect(provisioning.draft_org_positions.first["evidence_retracted_at"]).to be_present
      expect(provisioning.testimony_attachments.length).to eq(1)
      row = provisioning.testimony_attachments.first
      expect(row["filename"]).to eq("Attachment 10")
      expect(row["extraction_status"]).to eq("content_denied")
      expect(row["error"]).to include("not testimony")
    end

    # @lat: [[untrusted-text-in-prompts#Why character caps stand in for token budgets]]
    it "reads only a bounded slice of each sidecar while classifying; the full text still composes" do
      classifier = Testimony::AttachmentClassifier.new(llm: content_classifier_adapter)
      allow(Testimony::AttachmentClassifier).to receive(:build).and_return(classifier)
      captured_candidates = []
      allow(classifier).to receive(:classify_contents).and_wrap_original do |original, candidates, **kwargs|
        captured_candidates.concat(candidates)
        original.call(candidates, **kwargs)
      end
      allow(content_classifier_adapter).to receive(:generate_testimony_classification)
        .and_return({"classifications" => [{"index" => 0, "label" => "testimony"}]})

      stub_matter_attachments([matter_attachment(id: 707, name: "Attachment 8")])
      stub_matter_histories([])
      stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/707.pdf")
        .to_return(status: 200, body: "%PDF-1.4 x")
      allow(TestimonyTextExtractor).to receive(:new).and_return(
        instance_double(TestimonyTextExtractor, call: "I support this bill. #{"x" * 600_000}")
      )

      described_class.new(bill: bill).call

      bound = Testimony::ClassificationPromptBuilder::MAX_DOCUMENT_CHARS * 4
      expect(captured_candidates.length).to eq(1)
      expect(captured_candidates.first["text"].length).to be <= bound
      expect(bill.reload.bill_llm_provisioning.extracted_testimony.length).to be > 400_000
    end

    # The classification read and composition read are separate reads of the
    # same file — a read failing at classification but succeeding at
    # composition fed unjudged text.
    it "withholds a record's text when its sidecar was unreadable at classification, even if readable later" do
      service = described_class.new(bill: bill)
      record = {
        "id" => 810,
        "name" => "Attachment 9",
        "source_endpoint" => "matter_attachments",
        "download_status" => "succeeded",
        "extraction_status" => "reused_prior_run"
      }
      service.instance_variable_set(:@content_pending_ids, [810])

      # No sidecar exists yet, so the classification read comes back blank.
      kept = service.send(:classify_attachment_contents!, [record], sway_locale: sway_locale_name, sway_locale_id: bill.sway_locale_id)
      expect(kept).to eq([record])
      expect(record["extraction_status"]).to eq("extraction_failed")
      expect(record["error"]).to include("withheld")

      # The sidecar appears between the two reads — a transient read failure
      # clearing, or another process writing the file.
      path = service.send(:attachment_txt_path, record, sway_locale: sway_locale_name)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "I oppose this bill.")

      expect(service.send(:compose_testimony_from_disk, kept, sway_locale: sway_locale_name)).to eq("")
    end

    # HOW THIS MEETS THE PARTIAL-WITHDRAWAL CHECK, AND WHY THAT IS RIGHT:
    # reordering the stages changes both sides of evidence_withdrawn?'s
    # comparison, so the question must be answered, not assumed.
    it "marks the drafts evidence-retracted when a content denial withdraws contributing testimony" do
      stub_content_classifier(
        {"classifications" => [{"index" => 0, "label" => "not_testimony"}]}
      )
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "AN ORDINANCE CONCERNING Zoning.\n\nI support this bill.",
        # @lat: [[hearing-testimony-census#Losing some testimony is not the same as losing all of it]]
        testimony_attachments: [
          {"filename" => "Attachment 8", "attachment_id" => "707", "download_status" => "succeeded",
           "extraction_status" => "succeeded", "error" => nil},
          {"filename" => "Public Testimony 25-0064", "attachment_id" => "708", "download_status" => "succeeded",
           "extraction_status" => "succeeded", "error" => nil}
        ],
        draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}]
      )
      stub_matter_attachments([
        matter_attachment(id: 707, name: "Attachment 8"),
        matter_attachment(id: 708, name: "Public Testimony 25-0064")
      ])
      stub_matter_histories([])
      [707, 708].each do |id|
        stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/#{id}.pdf")
          .to_return(status: 200, body: "%PDF-1.4 x")
      end
      allow(TestimonyTextExtractor).to receive(:new) do |path|
        body = File.basename(path.to_s).include?("707") ? "AN ORDINANCE CONCERNING Zoning." : "I support this bill."
        instance_double(TestimonyTextExtractor, call: body)
      end

      described_class.new(bill: bill).call

      provisioning = bill.reload.bill_llm_provisioning
      expect(provisioning.extracted_testimony).to eq("I support this bill.")
      expect(BillLlmProvisioning.draft_evidence_retracted?(provisioning.draft_org_positions.first)).to be(true)
      expect(provisioning.draft_org_positions.first["org_name"]).to eq("ACME")
    end

    # The other side of the same comparison: a document rejected as
    # UNREADABLE keeps its record with a non-contributing status, and a
    # document that never contributed cannot be withdrawn.
    it "does not mark the drafts when the denied document never contributed text" do
      stub_content_classifier({"classifications" => []})
      bill.create_bill_llm_provisioning!(
        extracted_testimony: "I support this bill.",
        testimony_attachments: [
          {"filename" => "Public Testimony 25-0064", "download_status" => "succeeded",
           "extraction_status" => "succeeded", "error" => nil}
        ],
        draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}]
      )
      stub_matter_attachments([
        matter_attachment(id: 709, name: "Attachment 9"),
        matter_attachment(id: 710, name: "Public Testimony 25-0064")
      ])
      stub_matter_histories([])
      [709, 710].each do |id|
        stub_request(:get, "https://baltimore.legistar1.com/baltimore/attachments/#{id}.pdf")
          .to_return(status: 200, body: "%PDF-1.4 x")
      end
      allow(TestimonyTextExtractor).to receive(:new) do |path|
        body = File.basename(path.to_s).include?("709") ? "" : "I support this bill."
        instance_double(TestimonyTextExtractor, call: body)
      end

      described_class.new(bill: bill).call

      provisioning = bill.reload.bill_llm_provisioning
      expect(provisioning.extracted_testimony).to eq("I support this bill.")
      expect(BillLlmProvisioning.draft_evidence_retracted?(provisioning.draft_org_positions.first)).to be(false)
    end
  end

  describe "Decoupled hearing fetching via GenericHearingsAdapter" do
    let(:baltimore_locale) { bill.sway_locale }

    it "delegates Legistar client instantiation to GenericHearingsAdapter configured with locale namespace" do
      service = described_class.new(bill: bill)
      adapter = service.send(:adapter)

      expect(adapter).to be_a(Legislation::Adapters::GenericHearingsAdapter)
      expect(adapter.legistar_client.client).to eq("baltimore")
    end
  end

  describe "Migrate FetchHearingsService to use GenericHearingsAdapter" do
    let(:maryland_locale) { create(:sway_locale, :maryland) }
    let(:congress_locale) { create(:sway_locale, :congress) }

    describe "direct GenericHearingsAdapter instantiation and delegation" do
      it "instantiates GenericHearingsAdapter with locale hearings_rules and delegates discover_hearings" do
        mock_bill = create(:bill, external_id: "SB0001", sway_locale: maryland_locale)
        mock_adapter = instance_double(Legislation::Adapters::GenericHearingsAdapter)
        allow(Legislation::Adapters::GenericHearingsAdapter).to receive(:new).and_return(mock_adapter)
        allow(mock_adapter).to receive(:discover_hearings).and_return([])

        described_class.new(bill: mock_bill).call

        expect(Legislation::Adapters::GenericHearingsAdapter).to have_received(:new).with(
          mock_bill.sway_locale.jurisdiction_rules.hearings_rules,
          connection: an_instance_of(Faraday::Connection),
          attachment_connection: an_instance_of(Faraday::Connection),
          service: an_instance_of(described_class)
        )
        expect(mock_adapter).to have_received(:discover_hearings).with(
          bill: mock_bill,
          sway_locale: mock_bill.sway_locale,
          faraday_conn: an_instance_of(Faraday::Connection),
          service: an_instance_of(described_class)
        )
      end
    end

    describe "generic_html engine (Maryland)" do
      it "discovers hearings via generic_html engine, writes hearings artifact, and returns events" do
        mga_bill = create(:bill, external_id: "SB0001", sway_locale: maryland_locale)
        html_response = <<~HTML
          <html><body>
            <div class="hearing-entry">
              <span class="committee">Judicial Proceedings</span>
              <span class="date">1/22/2026</span>
              <span class="time">1:00 PM</span>
              <span class="location">West Committee Room</span>
            </div>
          </body></html>
        HTML

        endpoint = maryland_locale.jurisdiction_rules.hearings_rules.dig(:endpoints, :details)&.gsub(":external_id", "sb0001") || "/details/sb0001"
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get(endpoint) { [200, {"content-type" => "text/html"}, html_response] }
        conn = Faraday.new("https://mgaleg.maryland.gov") { |f| f.adapter :test, stubs }

        service = described_class.new(bill: mga_bill, faraday_conn: conn)
        results = service.call

        expect(results).to be_an(Array)
        expect(results.length).to eq(1)
        expect(results.first["EventBodyName"]).to eq("Judicial Proceedings")
        expect(results.first["EventDate"]).to eq("1/22/2026")

        artifact = Legislation::Paths.hearings_file(mga_bill.external_id, sway_locale: maryland_locale.name)
        expect(artifact).to exist
        parsed = JSON.parse(artifact.read)
        expect(parsed["events"].length).to eq(1)
        expect(mga_bill.reload.bill_llm_provisioning&.testimony_fetched_at).not_to be_nil
      end
    end

    describe "generic_rest engine (Congress)" do
      it "discovers hearings via generic_rest engine, writes hearings artifact, and returns events" do
        cg_bill = create(:bill, external_id: "HR100", sway_locale: congress_locale)
        json_response = {
          hearings: [
            {
              id: 201,
              committee: "House Judiciary",
              date: "2026-03-01",
              time: "10:00 AM",
              room: "Rayburn 2141"
            }
          ]
        }.to_json

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/hearings/HR100") { [200, {"content-type" => "application/json"}, json_response] }
        conn = Faraday.new("https://api.congress.gov/v3") { |f| f.adapter :test, stubs }

        service = described_class.new(bill: cg_bill, faraday_conn: conn)
        results = service.call

        expect(results).to be_an(Array)
        expect(results.length).to eq(1)
        expect(results.first["EventBodyName"]).to eq("House Judiciary")
        expect(results.first["EventDate"]).to eq("2026-03-01")

        artifact = Legislation::Paths.hearings_file(cg_bill.external_id, sway_locale: congress_locale.name)
        expect(artifact).to exist
        parsed = JSON.parse(artifact.read)
        expect(parsed["events"].length).to eq(1)
        expect(cg_bill.reload.bill_llm_provisioning&.testimony_fetched_at).not_to be_nil
      end
    end

    describe "unavailable engine" do
      it "returns empty array without network requests" do
        unavailable_rules = instance_double(
          SwayLocale::JurisdictionRules,
          hearings_rules: {engine: :unavailable}
        )
        unavailable_locale = instance_double(
          SwayLocale,
          name: "manual-locale",
          jurisdiction_rules: unavailable_rules
        )
        unavailable_bill = instance_double(Bill, sway_locale: unavailable_locale)

        service = described_class.new(bill: unavailable_bill)
        expect(service.call).to eq([])
      end
    end
  end

  describe "#default_faraday_conn" do
    let(:service) { described_class.new(bill: bill, faraday_conn: Faraday.new) }

    before do
      @mock_rules = instance_double(SwayLocale::JurisdictionRules, hearings_rules: nil)
      allow(bill.sway_locale).to receive(:jurisdiction_rules).and_return(@mock_rules)
    end

    it "selects congress_gov connection when retrieval is congress_dot_gov without hardcoded CONGRESS_GOV_API_KEY check" do
      allow(@mock_rules).to receive(:hearings_rules).and_return({
        retrieval: "congress_dot_gov",
        api_key_secret: "CUSTOM_SECRET_ENV_VAR"
      })
      allow(Sway::FaradayStack).to receive(:congress_gov).and_call_original

      conn = service.send(:default_faraday_conn)
      expect(Sway::FaradayStack).to have_received(:congress_gov)
      expect(conn).to be_a(Faraday::Connection)
    end

    it "selects congress_gov connection when retrieval is congress" do
      allow(@mock_rules).to receive(:hearings_rules).and_return({
        retrieval: "congress"
      })
      allow(Sway::FaradayStack).to receive(:congress_gov).and_call_original

      conn = service.send(:default_faraday_conn)
      expect(Sway::FaradayStack).to have_received(:congress_gov)
      expect(conn).to be_a(Faraday::Connection)
    end

    it "builds a custom Faraday connection when base_url is present and retrieval is not congress or legistar" do
      allow(@mock_rules).to receive(:hearings_rules).and_return({
        retrieval: "generic_rest",
        base_url: "https://api.custom-jurisdiction.gov",
        api_key_secret: "CONGRESS_GOV_API_KEY"
      })
      allow(Sway::FaradayStack).to receive(:build).and_call_original

      conn = service.send(:default_faraday_conn)
      expect(Sway::FaradayStack).to have_received(:build).with(base_url: "https://api.custom-jurisdiction.gov")
      expect(conn).to be_a(Faraday::Connection)
    end

    it "selects legistar connection when retrieval is legistar" do
      allow(@mock_rules).to receive(:hearings_rules).and_return({
        retrieval: "legistar"
      })
      allow(Sway::FaradayStack).to receive(:legistar).and_call_original

      conn = service.send(:default_faraday_conn)
      expect(Sway::FaradayStack).to have_received(:legistar)
      expect(conn).to be_a(Faraday::Connection)
    end

    it "selects congress_gov connection when retrieval_strategy is congress" do
      allow(@mock_rules).to receive(:hearings_rules).and_return({
        retrieval_strategy: "congress"
      })
      allow(Sway::FaradayStack).to receive(:congress_gov).and_call_original

      conn = service.send(:default_faraday_conn)
      expect(Sway::FaradayStack).to have_received(:congress_gov)
      expect(conn).to be_a(Faraday::Connection)
    end

    it "selects congress_gov connection when engine is congress" do
      allow(@mock_rules).to receive(:hearings_rules).and_return({
        engine: "congress"
      })
      allow(Sway::FaradayStack).to receive(:congress_gov).and_call_original

      conn = service.send(:default_faraday_conn)
      expect(Sway::FaradayStack).to have_received(:congress_gov)
      expect(conn).to be_a(Faraday::Connection)
    end

    it "handles string keys in hearings_rules dictionary" do
      allow(@mock_rules).to receive(:hearings_rules).and_return({
        "retrieval" => "congress"
      })
      allow(Sway::FaradayStack).to receive(:congress_gov).and_call_original

      conn = service.send(:default_faraday_conn)
      expect(Sway::FaradayStack).to have_received(:congress_gov)
      expect(conn).to be_a(Faraday::Connection)
    end

    it "raises StageError when hearings_rules is nil" do
      allow(@mock_rules).to receive(:hearings_rules).and_return(nil)

      expect {
        service.send(:default_faraday_conn)
      }.to raise_error(StageError, /fetch_hearings: connection rules lack a valid retrieval strategy or base_url/)
    end

    it "raises StageError when jurisdiction_rules raises an error" do
      allow(bill.sway_locale).to receive(:jurisdiction_rules).and_raise(StandardError, "rules error")

      expect {
        service.send(:default_faraday_conn)
      }.to raise_error(StageError, /fetch_hearings: connection rules lack a valid retrieval strategy or base_url/)
    end

    it "raises StageError when retrieval is unrecognized and base_url is blank" do
      allow(@mock_rules).to receive(:hearings_rules).and_return({
        retrieval: "unsupported_strategy",
        base_url: nil
      })

      expect {
        service.send(:default_faraday_conn)
      }.to raise_error(StageError, /fetch_hearings: connection rules lack a valid retrieval strategy or base_url/)
    end

    it "builds a custom connection when retrieval is nil but base_url is present" do
      allow(@mock_rules).to receive(:hearings_rules).and_return({
        base_url: "https://api.custom-jurisdiction.gov"
      })
      allow(Sway::FaradayStack).to receive(:build).and_call_original

      conn = service.send(:default_faraday_conn)
      expect(Sway::FaradayStack).to have_received(:build).with(base_url: "https://api.custom-jurisdiction.gov")
      expect(conn).to be_a(Faraday::Connection)
    end
  end

  describe "#default_attachment_faraday_conn" do
    let(:service) { described_class.new(bill: bill, faraday_conn: Faraday.new) }

    before do
      @mock_rules = instance_double(SwayLocale::JurisdictionRules, hearings_rules: nil)
      allow(bill.sway_locale).to receive(:jurisdiction_rules).and_return(@mock_rules)
    end

    it "selects congress_gov connection when retrieval is congress_dot_gov" do
      allow(@mock_rules).to receive(:hearings_rules).and_return({
        retrieval: "congress_dot_gov"
      })
      allow(Sway::FaradayStack).to receive(:congress_gov).and_call_original

      conn = service.send(:default_attachment_faraday_conn)
      expect(Sway::FaradayStack).to have_received(:congress_gov)
      expect(conn).to be_a(Faraday::Connection)
    end

    it "selects congress_gov connection when retrieval is congress" do
      allow(@mock_rules).to receive(:hearings_rules).and_return({
        retrieval: "congress"
      })
      allow(Sway::FaradayStack).to receive(:congress_gov).and_call_original

      conn = service.send(:default_attachment_faraday_conn)
      expect(Sway::FaradayStack).to have_received(:congress_gov)
      expect(conn).to be_a(Faraday::Connection)
    end

    it "selects legistar_attachment connection when retrieval is legistar" do
      allow(@mock_rules).to receive(:hearings_rules).and_return({
        retrieval: "legistar"
      })
      allow(Sway::FaradayStack).to receive(:legistar_attachment).and_call_original

      conn = service.send(:default_attachment_faraday_conn)
      expect(Sway::FaradayStack).to have_received(:legistar_attachment)
      expect(conn).to be_a(Faraday::Connection)
    end

    it "builds Faraday connection when base_url is present" do
      allow(@mock_rules).to receive(:hearings_rules).and_return({
        base_url: "https://attachments.example.gov"
      })

      conn = service.send(:default_attachment_faraday_conn)
      expect(conn).to be_a(Faraday::Connection)
      expect(conn.url_prefix.to_s).to eq("https://attachments.example.gov/")
    end

    it "raises StageError when hearings_rules is nil" do
      allow(@mock_rules).to receive(:hearings_rules).and_return(nil)

      expect {
        service.send(:default_attachment_faraday_conn)
      }.to raise_error(StageError, /fetch_hearings: connection rules lack a valid retrieval strategy or base_url/)
    end

    it "raises StageError when jurisdiction_rules raises an error" do
      allow(bill.sway_locale).to receive(:jurisdiction_rules).and_raise(StandardError, "rules error")

      expect {
        service.send(:default_attachment_faraday_conn)
      }.to raise_error(StageError, /fetch_hearings: connection rules lack a valid retrieval strategy or base_url/)
    end

    it "raises StageError when unconfigured or unknown retrieval without base_url" do
      allow(@mock_rules).to receive(:hearings_rules).and_return({
        retrieval: "unknown_retrieval",
        base_url: nil
      })

      expect {
        service.send(:default_attachment_faraday_conn)
      }.to raise_error(StageError, /fetch_hearings: connection rules lack a valid retrieval strategy or base_url/)
    end

    it "falls back to DEFAULT_LOCALE_NAME when bill and run have no locale and raises StageError if default locale is missing" do
      unassigned_bill = instance_double(Bill, external_id: "TEMP02", sway_locale: nil)
      empty_run = instance_double(LegislationPipelineRun, effective_sway_locale: nil, bill: nil)

      fallback_service = described_class.new(bill: unassigned_bill, run: empty_run)
      expect(fallback_service.send(:adapter).engine).to eq(:legistar)

      allow(SwayLocale).to receive(:resolve_by_computed_name)
        .with(LegislationIngestionService::DEFAULT_LOCALE_NAME)
        .and_return(nil)

      expect { described_class.new }
        .to raise_error(StageError, "fetch_hearings: no default SwayLocale found")
    end
  end
end
