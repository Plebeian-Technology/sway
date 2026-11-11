# frozen_string_literal: true

require "rails_helper"

# Tests for FetchBillsService. Helper constants live on a frozen module, not
# let(...), since Steep cant see RSpec's DSL.
module FetchBillsServiceSpecHelpers
  ARTIFACT_ROOT = LegislationTestArtifacts.root_for("fetch_bills_service").freeze

  # FetchBillsService fetches Baltimore only, so files land under one
  # segment: <root>/<sway_locale>/<external_id>/, since a Bill is unique on
  # (external_id, sway_locale_id) together.
  SWAY_LOCALE = "baltimore-maryland-united_states"

  # One bill's artifact directory.
  def self.bill_dir(external_id)
    File.join(ARTIFACT_ROOT, SWAY_LOCALE, external_id.to_s)
  end
  CASSETTE_DIR = Rails.root.join("spec", "fixtures", "vcr_cassettes").to_s.freeze
  LEGISTAR_BASE_URL = "https://webapi.legistar.com/v1"
end

RSpec.describe FetchBillsService do
  include ActiveSupport::Testing::TimeHelpers

  # Points the folder holding each bill's PDF/metadata at a temp directory
  # via the same setting production reads (Legislation::Paths.bills_raw), so
  # both writer and reader resolve through one root.
  around do |example|
    FileUtils.rm_rf(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT)
    FileUtils.mkdir_p(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT)
    with_app_config(:legislation, legislation_bills_raw_root: FetchBillsServiceSpecHelpers::ARTIFACT_ROOT) {
      example.run
    }
  ensure
    FileUtils.rm_rf(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT)
  end

  # run must be a saved LegislationPipelineRun since the service writes
  # Bill/PipelineRunBill rows. find_or_create_by! is atomic, unlike find_by
  # || create!.
  let(:baltimore_locale) do
    SwayLocale.find_or_create_by!(city: "baltimore", state: "maryland", country: "united_states")
  end

  # A top-level let! would create the Baltimore SwayLocale in every example,
  # including the one that needs to delete it — :no_council_president skips
  # it.
  let!(:council_president) do |example|
    next if example.metadata[:no_council_president]
    district = baltimore_locale.districts.find_or_create_by!(name: "at-large")
    legislator =
      Legislator.find_or_create_by!(external_id: "baltimore-council-president-test") do |leg|
        leg.first_name = "Test"
        leg.last_name = "President"
        leg.party = "D"
        leg.sway_locale = baltimore_locale
      end
    legislator.active_term ||
      create(:legislator_term, legislator:, district:, title: "Council President")
    legislator
  end

  let(:run) do
    create(:legislation_pipeline_run)
  end

  # The introduction-date range Baltimore is asked about follows the
  # calendar: the query boundary is worked out entirely from default_years,
  # so pinning default_years pins the query.
  describe "#default_years" do
    it "returns [previous_year, current_year] and rolls forward each year" do
      service = described_class.new(run: run)

      travel_to(Time.zone.local(2026, 6, 1)) do
        expect(service.send(:default_years)).to eq([2025, 2026])
      end

      travel_to(Time.zone.local(2027, 2, 1)) do
        expect(service.send(:default_years)).to eq([2026, 2027])
      end
    end
  end

  describe "#call (happy path via VCR cassette)" do
    it "returns an array of metadata Hashes and writes metadata.json + PDF per bill" do
      VCR.configure do |c|
        c.cassette_library_dir = FetchBillsServiceSpecHelpers::CASSETTE_DIR
      end
      begin
        VCR.use_cassette("fetch_bills_service",
          allow_playback_repeats: true,
          match_requests_on: %i[method host path]) do
          service = described_class.new(run: run)
          results = service.call

          expect(results).to be_an(Array)
          expect(results).not_to be_empty
          first = results.first
          expect(first).to include(:external_id, :title, :pdf_url)

          dir = FetchBillsServiceSpecHelpers.bill_dir(first[:external_id])
          expect(File.exist?(File.join(dir, "metadata.json"))).to be(true)
        end
      ensure
        VCR.configure do |c|
          c.cassette_library_dir = "spec/cassettes"
        end
      end
    end
  end

  describe "#call (network failure → BillProcessingError)" do
    it "wraps Faraday::TimeoutError and truncates message to 500 chars" do
      stub_request(:get,
        /webapi\.legistar\.com\/v1\/baltimore\/Matters/)
        .to_raise(Faraday::TimeoutError.new("a" * 1000))

      service = described_class.new(run: run)
      expect { service.call }.to raise_error(BillProcessingError) do |err|
        expect(err.message).to include("fetch_bills network error")
        expect(err.message.length).to be <= ("fetch_bills network error: ".length + 500)
      end
    end
  end

  describe "#call (bill missing PDF URL)" do
    it "writes metadata.json and skips PDF download without raising" do
      matters_body = [{
        "MatterId" => 999,
        "MatterFile" => "TEST-001",
        "MatterTitle" => "A test bill with no PDF",
        "MatterIntroDate" => "2025-01-15T00:00:00",
        "MatterTypeName" => "Ordinance"
      }].to_json
      stub_request(:get,
        /webapi\.legistar\.com\/v1\/baltimore\/Matters\?\$filter/)
        .to_return(status: 200, body: matters_body,
          headers: {"Content-Type" => "application/json"})
      stub_request(:get,
        %r{webapi\.legistar\.com/v1/baltimore/Matters/999/Attachments})
        .to_return(status: 200, body: "[]",
          headers: {"Content-Type" => "application/json"})

      service = described_class.new(run: run)
      results = service.call

      expect(results).to be_an(Array)
      expect(results.length).to eq(1)
      expect(results.first[:external_id]).to eq("TEST-001")
      expect(results.first[:pdf_url]).to be_nil

      dir = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, "TEST-001")
      expect(File.exist?(File.join(dir, "metadata.json"))).to be(true)
      expect(Dir.glob(File.join(dir, "*.pdf"))).to be_empty
    end
  end

  # Both discover loops reach Legistar once per bill and neither raises on a
  # stalled request — hours of invisible progress on a one-worker queue.
  describe "#call — the discover loops stop when their time budget is used up" do
    def stub_two_matters!
      matters_body = [
        {"MatterId" => 901, "MatterFile" => "BUDGET-1", "MatterTitle" => "First",
         "MatterIntroDate" => "2025-01-15T00:00:00", "MatterTypeName" => "Ordinance"},
        {"MatterId" => 902, "MatterFile" => "BUDGET-2", "MatterTitle" => "Second",
         "MatterIntroDate" => "2025-01-16T00:00:00", "MatterTypeName" => "Ordinance"}
      ].to_json
      stub_request(:get, /webapi\.legistar\.com\/v1\/baltimore\/Matters\?\$filter/)
        .to_return(status: 200, body: matters_body, headers: {"Content-Type" => "application/json"})
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/90\d/Attachments})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})
    end

    it "fails discovery when its budget expires before any bills are found" do
      stub_two_matters!
      stub_const("#{described_class}::DISCOVERY_BUDGET_SECONDS", 0.0)

      expect { described_class.new(run: run).call }
        .to raise_error(EmptyStageError, /no bills were discovered/)
    end

    it "asks Legistar for no attachments at all once that budget is gone" do
      stub_two_matters!
      stub_const("#{described_class}::DISCOVERY_BUDGET_SECONDS", 0.0)

      expect { described_class.new(run: run).call }
        .to raise_error(EmptyStageError, /no bills were discovered/)

      expect(a_request(:get, %r{Matters/90\d/Attachments})).not_to have_been_made
    end

    it "says how far it got rather than stopping silently" do
      stub_two_matters!
      stub_const("#{described_class}::DISCOVERY_BUDGET_SECONDS", 0.0)
      allow(SwayLogging).to receive(:warn)

      expect { described_class.new(run: run).call }
        .to raise_error(EmptyStageError, /no bills were discovered/)

      expect(SwayLogging).to have_received(:warn)
        .with(/discovery budget of .+ used up after 0 of 2 matters/)
    end
  end

  # The download half stops differently, on purpose. Backfill mode finds a
  # bill via matter_id in metadata.json, so a bill with none is invisible to
  # it.
  describe "#call — the download budget reaches the loop" do
    before do
      matters_body = [{
        "MatterId" => 921, "MatterFile" => "LOOPBUDGET-1", "MatterTitle" => "First",
        "MatterIntroDate" => "2025-01-15T00:00:00", "MatterTypeName" => "Ordinance"
      }].to_json
      attachments_body = [{
        "MatterAttachmentId" => 5101,
        "MatterAttachmentName" => "LOOPBUDGET-1~1st Reader.pdf",
        "MatterAttachmentFileName" => "loopbudget-1.pdf",
        "MatterAttachmentHyperlink" => "https://baltimore.legistar1.com/loopbudget-1.pdf"
      }].to_json
      stub_request(:get, /webapi\.legistar\.com\/v1\/baltimore\/Matters\?\$filter/)
        .to_return(status: 200, body: matters_body, headers: {"Content-Type" => "application/json"})
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/921/Attachments})
        .to_return(status: 200, body: attachments_body, headers: {"Content-Type" => "application/json"})
      stub_request(:get, "https://baltimore.legistar1.com/loopbudget-1.pdf")
        .to_return(status: 200, body: "%PDF-1.4 fake", headers: {"Content-Type" => "application/pdf"})
    end

    it "skips the PDF fetch once the download budget is gone" do
      stub_const("#{described_class}::DOWNLOAD_BUDGET_SECONDS", 0.0)

      described_class.new(run: run).call

      expect(a_request(:get, "https://baltimore.legistar1.com/loopbudget-1.pdf")).not_to have_been_made
    end

    it "still writes that bill's metadata.json, so backfill can find it" do
      stub_const("#{described_class}::DOWNLOAD_BUDGET_SECONDS", 0.0)

      described_class.new(run: run).call

      path = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, "LOOPBUDGET-1", "metadata.json")
      expect(File.exist?(path)).to be(true)
    end

    it "fetches the PDF when the budget has not run out" do
      described_class.new(run: run).call

      expect(a_request(:get, "https://baltimore.legistar1.com/loopbudget-1.pdf")).to have_been_made
    end
  end

  describe "#persist — the download budget drops the fetch, never the file" do
    let(:metadata) do
      {
        external_id: "DLBUDGET-1",
        matter_id: 911,
        title: "First",
        introduction_date: "2025-01-15T00:00:00",
        bill_number: "DLBUDGET-1",
        matter_type: "Ordinance",
        pdf_url: "https://baltimore.legistar1.com/dlbudget-1.pdf",
        pdf_filename: "dlbudget-1.pdf"
      }
    end

    before do
      stub_request(:get, "https://baltimore.legistar1.com/dlbudget-1.pdf")
        .to_return(status: 200, body: "%PDF-1.4 fake",
          headers: {"Content-Type" => "application/pdf"})
    end

    it "writes metadata.json even with the download switched off" do
      described_class.new(run: run).send(:persist, metadata, download: false)

      path = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, "DLBUDGET-1", "metadata.json")
      expect(File.exist?(path)).to be(true)
    end

    it "makes no request with the download switched off" do
      described_class.new(run: run).send(:persist, metadata, download: false)

      expect(a_request(:get, "https://baltimore.legistar1.com/dlbudget-1.pdf")).not_to have_been_made
    end

    # The control. Without it the example above would pass just as well against
    # a broken fixture that never downloads anything.
    it "fetches the PDF when the download is on" do
      described_class.new(run: run).send(:persist, metadata, download: true)

      expect(a_request(:get, "https://baltimore.legistar1.com/dlbudget-1.pdf")).to have_been_made
    end

    it "writes the PDF when the download is on" do
      described_class.new(run: run).send(:persist, metadata, download: true)

      path = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, "DLBUDGET-1", "dlbudget-1.pdf")
      expect(File.exist?(path)).to be(true)
    end
  end

  # @lat: [[legislation-pipeline#Empty discovery is a stage failure]]
  describe "#call with a non-JSON first Matters page" do
    it "fails discovery when the success response provides no usable bills" do
      stub_request(:get,
        /webapi\.legistar\.com\/v1\/baltimore\/Matters\?\$filter/)
        .to_return(status: 200, body: "<html>gateway hiccup</html>",
          headers: {"Content-Type" => "text/html"})

      service = described_class.new(run: run)
      expect { service.call }
        .to raise_error(BillProcessingError, /Legistar returned a non-JSON body|no bills were discovered/)
    end
  end

  # A network failure on one bill must NOT stop the rest from
  # being discovered. These examples use no retries so webmock fires
  # immediately.
  describe "#call (per-bill network failure is isolated)" do
    # The same base URL as FaradayStack.legistar, but with NO retry
    # middleware. LEGISTAR_PATH_PREFIX starts with a slash, resolving to the
    # same URLs the other fake requests match.
    let(:no_retry_conn) do
      Faraday.new(url: FetchBillsServiceSpecHelpers::LEGISTAR_BASE_URL) do |conn|
        conn.adapter(Faraday.default_adapter)
      end
    end

    let(:two_matters) do
      [
        {"MatterId" => 101, "MatterFile" => "CCB-25-0101",
         "MatterTitle" => "Bill whose attachments endpoint is flaky",
         "MatterIntroDate" => "2025-01-15T00:00:00", "MatterTypeName" => "Ordinance"},
        {"MatterId" => 102, "MatterFile" => "CCB-25-0102",
         "MatterTitle" => "Healthy bill",
         "MatterIntroDate" => "2025-02-20T00:00:00", "MatterTypeName" => "Ordinance"}
      ].to_json
    end

    before do
      stub_request(:get, /webapi\.legistar\.com\/v1\/baltimore\/Matters\?\$filter/)
        .to_return(status: 200, body: two_matters,
          headers: {"Content-Type" => "application/json"})
    end

    it "discovers a bill whose attachment fetch fails (no PDF) and still seeds every bill" do
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/101/Attachments})
        .to_raise(Faraday::SSLError.new("SSL_read: unexpected eof while reading"))
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/102/Attachments})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})

      service = described_class.new(run: run, faraday_conn: no_retry_conn)
      results = nil #: untyped
      expect { results = service.call }.not_to raise_error

      # Both bills are discovered — the flaky one ends up with no PDF, not gone.
      expect(results.pluck(:external_id).sort).to eq(%w[CCB-25-0101 CCB-25-0102])
      flaky = results.find { |m| m[:external_id] == "CCB-25-0101" }
      expect(flaky[:pdf_url]).to be_nil
      expect(run.reload.pipeline_run_bills.pluck(:bill_external_id).sort)
        .to eq(%w[CCB-25-0101 CCB-25-0102])
    end

    it "keeps metadata.json (and skips the PDF) when a bill's PDF download fails" do
      pdf_url = "https://legistar.blob.test/CCB-25-0101.pdf"
      attachments = [{
        "MatterAttachmentName" => "CCB-25-0101 1st Reader",
        "MatterAttachmentFileName" => "CCB-25-0101.pdf",
        "MatterAttachmentHyperlink" => pdf_url,
        "MatterAttachmentLastModifiedUtc" => "2025-01-16T00:00:00"
      }].to_json
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/101/Attachments})
        .to_return(status: 200, body: attachments, headers: {"Content-Type" => "application/json"})
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/102/Attachments})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})
      stub_request(:get, pdf_url)
        .to_raise(Faraday::ConnectionFailed.new("connection reset by peer"))

      service = described_class.new(run: run, faraday_conn: no_retry_conn)
      expect { service.call }.not_to raise_error

      dir = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, "CCB-25-0101")
      expect(File.exist?(File.join(dir, "metadata.json"))).to be(true)
      expect(Dir.glob(File.join(dir, "*.pdf"))).to be_empty
      expect(run.reload.pipeline_run_bills.pluck(:bill_external_id))
        .to include("CCB-25-0101", "CCB-25-0102")
    end

    # #download_pdf is the older twin of #download_attachments!: an absolute
    # URL in a hyperlink overrides the connection's base — the same SSRF
    # hole.
    it "never fetches a bill PDF from a host outside the Legistar allowlist" do
      hostile_url = "http://169.254.169.254/latest/meta-data/"
      attachments = [{
        "MatterAttachmentName" => "CCB-25-0101 1st Reader",
        "MatterAttachmentFileName" => "CCB-25-0101.pdf",
        "MatterAttachmentHyperlink" => hostile_url,
        "MatterAttachmentLastModifiedUtc" => "2025-01-16T00:00:00"
      }].to_json
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/101/Attachments})
        .to_return(status: 200, body: attachments, headers: {"Content-Type" => "application/json"})
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/102/Attachments})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})
      probe = stub_request(:get, hostile_url)

      service = described_class.new(run: run, faraday_conn: no_retry_conn)
      expect { service.call }.not_to raise_error

      expect(probe).not_to have_been_requested
      dir = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, "CCB-25-0101")
      expect(Dir.glob(File.join(dir, "*.pdf"))).to be_empty
    end

    # The host allowlist reached both download sites; the SIZE cap reached
    # only hearings. A control not applied at both sites is only advice.
    it "refuses an over-cap bill PDF whose advertised Content-Length exceeds the shared attachment cap" do
      pdf_url = "https://baltimore.legistar1.com/View.ashx?M=F&ID=huge"
      attachments = [{
        "MatterAttachmentName" => "CCB-25-0101 1st Reader",
        "MatterAttachmentFileName" => "CCB-25-0101.pdf",
        "MatterAttachmentHyperlink" => pdf_url,
        "MatterAttachmentLastModifiedUtc" => "2025-01-16T00:00:00"
      }].to_json
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/101/Attachments})
        .to_return(status: 200, body: attachments, headers: {"Content-Type" => "application/json"})
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/102/Attachments})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})
      stub_request(:get, pdf_url).to_return(
        status: 200,
        body: "%PDF-1.4 small body, enormous claim",
        headers: {"Content-Length" => (512 * 1024 * 1024).to_s}
      )

      service = described_class.new(run: run, faraday_conn: no_retry_conn)
      expect { service.call }.not_to raise_error

      dir = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, "CCB-25-0101")
      expect(File.exist?(File.join(dir, "metadata.json"))).to be(true)
      expect(Dir.glob(File.join(dir, "*.pdf"))).to be_empty
    end

    it "refuses an over-cap bill PDF that advertised no Content-Length" do
      stub_const("Legistar::AttachmentFetch::MAX_ATTACHMENT_BYTES", 16)
      pdf_url = "https://baltimore.legistar1.com/View.ashx?M=F&ID=unadvertised"
      attachments = [{
        "MatterAttachmentName" => "CCB-25-0101 1st Reader",
        "MatterAttachmentFileName" => "CCB-25-0101.pdf",
        "MatterAttachmentHyperlink" => pdf_url,
        "MatterAttachmentLastModifiedUtc" => "2025-01-16T00:00:00"
      }].to_json
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/101/Attachments})
        .to_return(status: 200, body: attachments, headers: {"Content-Type" => "application/json"})
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/102/Attachments})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})
      stub_request(:get, pdf_url).to_return(status: 200, body: "%PDF-1.4 this body is well over sixteen bytes")

      service = described_class.new(run: run, faraday_conn: no_retry_conn)
      expect { service.call }.not_to raise_error

      dir = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, "CCB-25-0101")
      expect(Dir.glob(File.join(dir, "*.pdf"))).to be_empty
    end
  end

  # FetchBillsService must create a Bill row and a PipelineRunBill row for
  # every matter fetched, or every later stage trips the zero-count guard.
  describe "#call (AR seeding — Bill + PipelineRunBill rows)" do
    let(:matters_payload) do
      [
        {
          "MatterId" => 101,
          "MatterFile" => "CCB-25-0001",
          "MatterTitle" => "An Ordinance for the First Test Bill",
          "MatterIntroDate" => "2025-01-15T00:00:00",
          "MatterTypeName" => "Ordinance"
        },
        {
          "MatterId" => 102,
          "MatterFile" => "CCB-25-0002",
          "MatterTitle" => "An Ordinance for the Second Test Bill",
          "MatterIntroDate" => "2025-02-20T00:00:00",
          "MatterTypeName" => "Ordinance"
        }
      ]
    end

    before do
      # Reference the let! definitions so the Baltimore locale and the Council
      # President legislator are actually created for this example.
      council_president
      stub_request(:get,
        /webapi\.legistar\.com\/v1\/baltimore\/Matters\?\$filter/)
        .to_return(status: 200, body: matters_payload.to_json,
          headers: {"Content-Type" => "application/json"})
      stub_request(:get,
        %r{webapi\.legistar\.com/v1/baltimore/Matters/\d+/Attachments})
        .to_return(status: 200, body: "[]",
          headers: {"Content-Type" => "application/json"})
    end

    it "creates one Bill and one PipelineRunBill per fetched matter" do
      service = described_class.new(run: run)
      expect { service.call }
        .to change { Bill.where(sway_locale: baltimore_locale).count }.by(2)
        .and change { run.reload.pipeline_run_bills.count }.by(2)

      external_ids = matters_payload.pluck("MatterFile").sort
      expect(run.reload.pipeline_run_bills.pluck(:bill_external_id).sort)
        .to eq(external_ids)
      expect(Bill.where(sway_locale: baltimore_locale).pluck(:external_id).sort)
        .to include(*external_ids)
    end

    it "assigns monotonically increasing sort_order to PipelineRunBill rows" do
      described_class.new(run: run).call
      sort_orders = run.reload.pipeline_run_bills.order(:sort_order).pluck(:sort_order)
      expect(sort_orders).to eq([0, 1])
    end

    it "is idempotent — re-running for the same run does not duplicate rows" do
      described_class.new(run: run).call
      bills_before = Bill.where(sway_locale: baltimore_locale).count
      prbs_before = run.reload.pipeline_run_bills.count

      described_class.new(run: run).call

      expect(Bill.where(sway_locale: baltimore_locale).count).to eq(bills_before)
      expect(run.reload.pipeline_run_bills.count).to eq(prbs_before)
    end

    # @lat: [[legislation-pipeline#Runs, resume and restart#A run naming one bill seeds only that bill]]
    describe "single-bill scoping via run.bill" do
      let(:scoped_bill) { create(:bill, external_id: "CCB-25-0002", sway_locale: baltimore_locale) }
      let(:run_filtered) { create(:legislation_pipeline_run, bill: scoped_bill) }

      it "creates PRB rows only for the matter matching run.bill.external_id" do
        service = described_class.new(run: run_filtered)
        expect { service.call }
          .to change { run_filtered.reload.pipeline_run_bills.count }.by(1)

        expect(run_filtered.reload.pipeline_run_bills.pluck(:bill_external_id))
          .to eq(["CCB-25-0002"])
        expect(Bill.where(sway_locale: baltimore_locale).pluck(:external_id))
          .to include("CCB-25-0002")
        # The other matter in the faked Legistar response MUST NOT have been
        # seeded.
        expect(run_filtered.reload.pipeline_run_bills.pluck(:bill_external_id))
          .not_to include("CCB-25-0001")
      end
    end
  end

  # Rebuilds Bill/PipelineRunBill rows from metadata.json on disk,
  # for when a volume reset wiped the database but files survived.
  describe "#seed_from_disk" do
    # `sway_locale:` defaults to the jurisdiction this service fetches. The
    # example below overrides it to plant a file under a DIFFERENT one.
    def write_metadata(external_id, matter_id:, intro: "2025-01-15T00:00:00",
      sway_locale: FetchBillsServiceSpecHelpers::SWAY_LOCALE)
      dir = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, sway_locale, external_id)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "metadata.json"), {
        external_id: external_id,
        matter_id: matter_id,
        title: "An Ordinance for #{external_id}",
        introduction_date: intro,
        bill_number: external_id,
        matter_type: "Ordinance",
        pdf_url: "https://example.test/#{external_id}.pdf",
        pdf_filename: "#{external_id}.pdf"
      }.to_json)
    end

    before { council_president }

    it "seeds one Bill and one PipelineRunBill per on-disk metadata.json, no network" do
      write_metadata("CCB-25-0001", matter_id: 101)
      write_metadata("CCB-25-0002", matter_id: 102)

      service = described_class.new(run: run)
      expect { expect(service.seed_from_disk).to eq(2) }
        .to change { Bill.where(sway_locale: baltimore_locale).count }.by(2)
        .and change { run.reload.pipeline_run_bills.count }.by(2)

      expect(run.reload.pipeline_run_bills.pluck(:bill_external_id).sort)
        .to eq(["CCB-25-0001", "CCB-25-0002"])
    end

    # @lat: [[bill-session-archiving-tests#Bill session archive tests#Disk ingestion skips archives]]
    it "skips archived identities without rolling back live intake or creating pipeline work" do
      archived = create(:bill, sway_locale: baltimore_locale, external_id: "CCB-25-0001", archived_at: Time.current)
      write_metadata(archived.external_id, matter_id: 101)
      write_metadata("CCB-25-0002", matter_id: 102)

      expect { described_class.new(run: run).seed_from_disk }
        .to change { Bill.where(sway_locale: baltimore_locale).count }.by(1)
        .and change { run.reload.pipeline_run_bills.count }.by(1)
      expect(run.pipeline_run_bills.pluck(:bill_external_id)).to eq(["CCB-25-0002"])
      expect(Bill.unscoped.find(archived.id).archived_at).to be_present
    end

    # THE SWEEP MUST STAY INSIDE ITS OWN JURISDICTION: #seed_from_disk stamps
    # every row Baltimore, so a cross-jurisdiction sweep would mislabel a
    # city.
    it "ignores a metadata.json filed under another jurisdiction" do
      write_metadata("CCB-25-0001", matter_id: 101)
      write_metadata("HB1234", matter_id: 999, sway_locale: "maryland-maryland-united_states")

      service = described_class.new(run: run)
      expect(service.seed_from_disk).to eq(1)

      expect(run.reload.pipeline_run_bills.pluck(:bill_external_id)).to eq(["CCB-25-0001"])
      expect(Bill.exists?(external_id: "HB1234")).to be(false)
    end

    it "assigns deterministic sort_order ordered by external_id" do
      write_metadata("CCB-25-0002", matter_id: 102)
      write_metadata("CCB-25-0001", matter_id: 101)

      described_class.new(run: run).seed_from_disk

      ordered = run.reload.pipeline_run_bills.order(:sort_order).pluck(:bill_external_id)
      expect(ordered).to eq(["CCB-25-0001", "CCB-25-0002"])
    end

    it "returns 0 and seeds nothing when the disk cache is empty" do
      service = described_class.new(run: run)
      expect { expect(service.seed_from_disk).to eq(0) }
        .to change { run.reload.pipeline_run_bills.count }.by(0)
    end

    it "skips blank-external_id, non-Integer-matter_id, and unparseable rows" do
      write_metadata("CCB-25-0001", matter_id: 101)
      write_metadata("", matter_id: 999) # blank external_id → skipped
      bad = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, "CCB-25-0003")
      FileUtils.mkdir_p(bad)
      File.write(File.join(bad, "metadata.json"),
        {external_id: "CCB-25-0003", matter_id: "not-an-int"}.to_json)
      corrupt = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, "CCB-25-0004")
      FileUtils.mkdir_p(corrupt)
      File.write(File.join(corrupt, "metadata.json"), "{ not valid json")

      expect(described_class.new(run: run).seed_from_disk).to eq(1)
      expect(run.reload.pipeline_run_bills.pluck(:bill_external_id)).to eq(["CCB-25-0001"])
    end

    it "honors run.bill single-bill scoping" do
      write_metadata("CCB-25-0001", matter_id: 101)
      write_metadata("CCB-25-0002", matter_id: 102)
      scoped_bill = create(:bill, external_id: "CCB-25-0002", sway_locale: baltimore_locale)
      run_filtered = create(:legislation_pipeline_run, bill: scoped_bill)

      expect(described_class.new(run: run_filtered).seed_from_disk).to eq(1)
      expect(run_filtered.reload.pipeline_run_bills.pluck(:bill_external_id))
        .to eq(["CCB-25-0002"])
    end

    it "is idempotent — re-running does not duplicate rows" do
      write_metadata("CCB-25-0001", matter_id: 101)
      described_class.new(run: run).seed_from_disk
      prbs_before = run.reload.pipeline_run_bills.count

      described_class.new(run: run).seed_from_disk
      expect(run.reload.pipeline_run_bills.count).to eq(prbs_before)
    end
  end

  # Two places put a value into Bill#external_id, reaching 13 file-path
  # sites. #read_disk_metadatas is worse: no strip, no format check on an
  # operator-editable field — a path-injection risk.
  describe "external_id boundary validation (A1-CR-02)" do
    before { council_president }

    def write_raw_metadata(dirname, payload)
      dir = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, dirname)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "metadata.json"), payload.to_json)
      dir
    end

    describe "#seed_from_disk — operator-editable metadata.json" do
      # The key case. A hand-edited metadata.json carrying `..` path segments
      # must not create a Bill, must not create a PipelineRunBill, and must not
      # let anything later build a file path from it.
      it "refuses a metadata.json whose external_id escapes the artifact root" do
        write_raw_metadata("evil", {
          external_id: "../../../../rails/config/pwned",
          matter_id: 4242,
          title: "Traversal",
          introduction_date: "2025-01-15T00:00:00",
          bill_number: "x",
          matter_type: "Ordinance"
        })

        expect { expect(described_class.new(run: run).seed_from_disk).to eq(0) }
          .to change { Bill.count }.by(0)
          .and change { PipelineRunBill.count }.by(0)
      end

      it "keeps seeding the well-formed rows in the same sweep" do
        write_raw_metadata("evil", {
          external_id: "../../../../rails/config/pwned",
          matter_id: 4242,
          title: "Traversal",
          introduction_date: "2025-01-15T00:00:00",
          bill_number: "x",
          matter_type: "Ordinance"
        })
        write_raw_metadata("CCB-25-0009", {
          external_id: "CCB-25-0009",
          matter_id: 109,
          title: "An Ordinance",
          introduction_date: "2025-01-15T00:00:00",
          bill_number: "CCB-25-0009",
          matter_type: "Ordinance"
        })

        expect(described_class.new(run: run).seed_from_disk).to eq(1)
        expect(run.reload.pipeline_run_bills.pluck(:bill_external_id)).to eq(["CCB-25-0009"])
      end

      it "warns rather than failing silently, matching the method's existing skip policy" do
        allow(SwayLogging).to receive(:warn)

        write_raw_metadata("evil", {
          external_id: "../../../../rails/config/pwned",
          matter_id: 4242,
          title: "Traversal",
          introduction_date: "2025-01-15T00:00:00",
          bill_number: "x",
          matter_type: "Ordinance"
        })

        described_class.new(run: run).seed_from_disk

        expect(SwayLogging).to have_received(:warn).with(/external_id/)
      end

      # Two rows in production carry this padded shape, each with a leading tab:
      # bill 58 "\t24-0599" and bill 59 "\t24-0592". Such a value gets cleaned
      # up, not rejected.
      it "strips a whitespace-padded external_id rather than dropping the bill" do
        write_raw_metadata("CCB-25-0010", {
          external_id: "\tCCB-25-0010 ",
          matter_id: 110,
          title: "An Ordinance",
          introduction_date: "2025-01-15T00:00:00",
          bill_number: "CCB-25-0010",
          matter_type: "Ordinance"
        })

        expect(described_class.new(run: run).seed_from_disk).to eq(1)
        expect(run.reload.pipeline_run_bills.pluck(:bill_external_id)).to eq(["CCB-25-0010"])
        expect(Bill.where(external_id: "CCB-25-0010")).to exist
      end
    end

    describe "#build_metadata — Legistar MatterFile free text" do
      def build_for(matter_file)
        described_class.new(run: run).send(
          :build_metadata,
          {
            "MatterFile" => matter_file,
            "MatterId" => 5150,
            "MatterTypeName" => "Ordinance",
            "MatterTitle" => "An Ordinance",
            "MatterIntroDate" => "2025-01-15T00:00:00"
          }
        )
      end

      it "skips a matter whose MatterFile escapes the artifact root" do
        expect(build_for("../../../../rails/config/pwned")).to be_nil
      end

      it "skips a matter whose MatterFile carries a nested path segment" do
        expect(build_for("24-0599/nested")).to be_nil
      end

      it "still skips a blank MatterFile (the pre-existing guard)" do
        expect(build_for("   ")).to be_nil
      end
    end

    # The FileUtils.mkdir_p call itself: #seed_from_disk never reaches it, so
    # testing through it measures nothing. Call #persist directly instead.
    describe "#persist — the mkdir_p + File.write seam" do
      let(:escape_target) { Pathname.new(LegislationTestArtifacts.root_for("a1_cr_02_escape_probe")) }

      it "creates no directory outside the artifact root for a traversal external_id" do
        FileUtils.rm_rf(escape_target.to_s)
        relative = escape_target.relative_path_from(Pathname.new(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT))
        # Check that this path really does climb out of the artifact folder.
        expect(relative.to_s).to start_with("..")

        begin
          described_class.new(run: run).send(:persist, {
            external_id: relative.to_s,
            matter_id: 4243,
            title: "Traversal",
            introduction_date: "2025-01-15T00:00:00",
            bill_number: "x",
            matter_type: "Ordinance",
            pdf_url: nil,
            pdf_filename: nil
          })
        rescue Legislation::Paths::UnsafeExternalIdError
          # Refusing loudly is an acceptable outcome; escaping is not.
        end

        expect(escape_target.exist?).to be(false)
      ensure
        FileUtils.rm_rf(escape_target.to_s)
      end

      it "still writes metadata.json under the artifact root for a conforming id" do
        described_class.new(run: run).send(:persist, {
          external_id: "CCB-25-0011",
          matter_id: 111,
          title: "An Ordinance",
          introduction_date: "2025-01-15T00:00:00",
          bill_number: "CCB-25-0011",
          matter_type: "Ordinance",
          pdf_url: nil,
          pdf_filename: nil
        })

        expect(
          File.exist?(File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, "CCB-25-0011", "metadata.json"))
        ).to be(true)
      end
    end
  end

  describe "#call (default SwayLocale missing)" do
    # This context skips the top-level council_president let! so the
    # SwayLocale rows can really be deleted, exercising the real
    # resolve_by_computed_name.
    it "raises StageError before issuing any network requests", :no_council_president do
      Legislator.delete_all
      District.delete_all
      SwayLocale.delete_all

      # No fake requests are registered, so if the service made a network call
      # it would raise WebMock::NetError rather than StageError. Getting a
      # StageError proves the locale check runs first.
      run_fresh = create(:legislation_pipeline_run)
      expect { described_class.new(run: run_fresh).call }
        .to raise_error(StageError, /no default SwayLocale/)
    end
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart#Which attachment is the bill text]]
  describe "#select_primary_attachment" do
    let(:service) { described_class.new(run: run) }

    it "does not rank another jurisdiction's PDFs using Baltimore filenames" do
      service = described_class.new(run: run)
      allow(service).to receive(:sway_locale_name).and_return("maryland-maryland-united_states")
      attachments = [build_attachment("Agency report", "2025-01-01"), build_attachment("Public Testimony", "2025-02-01")]
      expect(service.send(:select_primary_attachment, attachments)).to eq(attachments.last)
    end

    def build_attachment(name, last_modified)
      {
        "MatterAttachmentId" => name.hash.abs,
        "MatterAttachmentFileName" => "#{name.parameterize}.pdf",
        "MatterAttachmentName" => name,
        "MatterAttachmentLastModifiedUtc" => last_modified,
        "MatterAttachmentHyperlink" => "https://example.test/#{name.parameterize}.pdf"
      }
    end

    it "selects the Reader (bill text) over a more-recently-modified testimony bundle" do
      # The real attachment set for bill 25-0064: the testimony bundle was
      # changed months after the bill text was finished.
      attachments = [
        build_attachment("25-0064~1st Reader.pdf", "2025-11-12T16:24:22"),
        build_attachment("25-0064~3rd Reader", "2025-10-27T15:23:28"),
        build_attachment("10.16.25 Public Testimony 25-0064", "2026-01-29T18:01:25"),
        build_attachment("9-18-25 Voting Record 25-0064.pdf", "2025-09-22T12:38:39")
      ]

      primary = service.send(:select_primary_attachment, attachments)

      expect(primary["MatterAttachmentName"]).to eq("25-0064~3rd Reader")
    end

    it "prefers the highest reading number even when an earlier reading was modified later" do
      attachments = [
        build_attachment("25-0099~1st Reader", "2026-02-01T00:00:00"),
        build_attachment("25-0099~3rd Reader", "2025-10-01T00:00:00")
      ]

      primary = service.send(:select_primary_attachment, attachments)

      expect(primary["MatterAttachmentName"]).to eq("25-0099~3rd Reader")
    end

    it "returns nil when there are no PDF attachments" do
      no_attachments = [] #: Array[untyped]
      expect(service.send(:select_primary_attachment, no_attachments)).to be_nil
    end

    # @lat: [[legislation-pipeline#Runs, resume and restart#Which attachment is the bill text]]
    it "still recognises a PDF whose file name carries trailing rubbish" do
      trailing_space = build_attachment("25-0101~1st Reader", "2026-01-01T00:00:00")
      trailing_space["MatterAttachmentFileName"] = "25-0101-1st-reader.pdf "
      trailing_nul = build_attachment("25-0101~3rd Reader", "2026-01-02T00:00:00")
      trailing_nul["MatterAttachmentFileName"] = "25-0101-3rd-reader.pdf\0"

      primary = service.send(:select_primary_attachment, [trailing_space, trailing_nul])

      expect(primary["MatterAttachmentName"]).to eq("25-0101~3rd Reader")
    end

    # The other half of the same claim: cleaning the name must not turn a
    # non-PDF into one.
    it "still refuses an attachment that is not a PDF" do
      not_a_pdf = build_attachment("25-0102 Voting Record", "2026-01-01T00:00:00")
      not_a_pdf["MatterAttachmentFileName"] = "25-0102-voting-record.xlsx"

      expect(service.send(:select_primary_attachment, [not_a_pdf])).to be_nil
    end
  end

  # Picking the Reader document was only half the fix — its fallback is the
  # SAME condemned rule, still running for matters with no Reader. NameRules
  # replaces it, using only its pure stages.
  describe "#select_primary_attachment fallback tiering" do
    def build_attachment(name, last_modified)
      {
        "MatterAttachmentId" => name.hash.abs,
        "MatterAttachmentFileName" => "#{name.parameterize}.pdf",
        "MatterAttachmentName" => name,
        "MatterAttachmentLastModifiedUtc" => last_modified,
        "MatterAttachmentHyperlink" => "https://example.test/#{name.parameterize}.pdf"
      }
    end

    let(:service) { described_class.new(run: run) }

    # The opposite of what the block above used to pin: falls back to
    # latest-modified was intended. The agency report is undecided; testimony
    # is newer.
    it "picks an unclassified agency PDF over a newer testimony bundle" do
      attachments = [
        build_attachment("BDC 25-0099.pdf", "2025-09-04T12:51:49"),
        build_attachment("10.16.25 Public Testimony 25-0099", "2026-01-29T18:06:36")
      ]

      primary = service.send(:select_primary_attachment, attachments)

      expect(primary["MatterAttachmentName"]).to eq("BDC 25-0099.pdf")
    end

    # The case actually observed in production.
    it "picks the ordinance over a newer community letter of support" do
      attachments = [
        build_attachment("100 Holliday Street", "2025-06-01T00:00:00"),
        build_attachment("100 Holliday Street - Community Letter of Support", "2026-03-01T00:00:00")
      ]

      primary = service.send(:select_primary_attachment, attachments)

      expect(primary["MatterAttachmentName"]).to eq("100 Holliday Street")
    end

    # Shows the ranking does more than reject testimony: this name is
    # bill_text for its 1st reprint marker, but contains no Reader, so it
    # falls through to the fallback the fallback exists for.
    it "prefers a positively-identified bill text over an older unclassified PDF" do
      attachments = [
        build_attachment("BDC 25-0064.pdf", "2026-05-01T00:00:00"),
        build_attachment("cc25-0064(1)~1st (LUT)", "2025-01-01T00:00:00")
      ]

      primary = service.send(:select_primary_attachment, attachments)

      expect(primary["MatterAttachmentName"]).to eq("cc25-0064(1)~1st (LUT)")
    end

    # Procedural documents are not bill text either, but they are a better
    # guess than testimony: a hearing packet at least quotes the measure.
    it "prefers a procedural document over testimony when nothing better exists" do
      attachments = [
        build_attachment("9-18-25 Voting Record 25-0099.pdf", "2025-09-22T12:38:39"),
        build_attachment("10.16.25 Public Testimony 25-0099", "2026-01-29T18:06:36")
      ]

      primary = service.send(:select_primary_attachment, attachments)

      expect(primary["MatterAttachmentName"]).to eq("9-18-25 Voting Record 25-0099.pdf")
    end

    # Fail honestly rather than returning nil: a bill whose only PDF is
    # testimony still gets a document, so the summary is visibly wrong
    # instead of quietly missing extracted_text.
    it "still returns a document when every PDF classifies as testimony" do
      attachments = [
        build_attachment("Public Testimony 25-0099", "2025-01-01T00:00:00"),
        build_attachment("Letter of Support 25-0099", "2026-01-01T00:00:00")
      ]

      primary = service.send(:select_primary_attachment, attachments)

      expect(primary["MatterAttachmentName"]).to eq("Letter of Support 25-0099")
    end

    # THE OTHER HALF, wrong the opposite way: this classified as bill_text,
    # the FIRST fallback rank, so testimony became the primary document.
    it "does not let a testimony name with a loose bill-text word become the primary document" do
      attachments = [
        build_attachment("Baltimore Readers Alliance Testimony.pdf", "2026-03-01T00:00:00"),
        build_attachment("Hearing Packet 25-0099", "2025-06-01T00:00:00")
      ]

      primary = service.send(:select_primary_attachment, attachments)

      expect(primary["MatterAttachmentName"]).to eq("Hearing Packet 25-0099")
    end

    it "prefers an unclassified agency PDF over an ambiguous testimony name" do
      attachments = [
        build_attachment("Signed Petition of Support.pdf", "2026-03-01T00:00:00"),
        build_attachment("BDC 25-0099.pdf", "2025-06-01T00:00:00")
      ]

      primary = service.send(:select_primary_attachment, attachments)

      expect(primary["MatterAttachmentName"]).to eq("BDC 25-0099.pdf")
    end

    # Above :testimony, though — an ambiguous name at least carries a
    # bill-text token, and preferring a document that says only "testimony"
    # over it would be the same mistake pointing the other way.
    it "still prefers an ambiguous name over an unambiguous testimony document" do
      attachments = [
        build_attachment("Signed Petition of Support.pdf", "2025-06-01T00:00:00"),
        build_attachment("10.16.25 Public Testimony 25-0099", "2026-03-01T00:00:00")
      ]

      primary = service.send(:select_primary_attachment, attachments)

      expect(primary["MatterAttachmentName"]).to eq("Signed Petition of Support.pdf")
    end

    # `25-0064 Signed` matches nothing on the allowlist, so it stays :bill_text
    # and stays in the top rank. The split must not cost the fallback its best
    # signal.
    it "keeps a genuine bill-text name in the top tier" do
      attachments = [
        build_attachment("25-0064 Signed", "2025-01-01T00:00:00"),
        build_attachment("BDC 25-0064.pdf", "2026-05-01T00:00:00")
      ]

      primary = service.send(:select_primary_attachment, attachments)

      expect(primary["MatterAttachmentName"]).to eq("25-0064 Signed")
    end

    # Inside a single rank the old rule still decides, so nothing gets worse for
    # matters where every candidate classifies the same way.
    it "keeps latest-modified as the tie-break inside a tier" do
      attachments = [
        build_attachment("BDC 25-0099.pdf", "2025-09-04T12:51:49"),
        build_attachment("DHCD 25-0099.pdf", "2025-11-04T12:51:49")
      ]

      primary = service.send(:select_primary_attachment, attachments)

      expect(primary["MatterAttachmentName"]).to eq("DHCD 25-0099.pdf")
    end
  end

  # fetch_all_matters pages by MatterId gt last_id. If a full pages last id
  # isnt an Integer, last_id never moves, and the SAME query loops forever —
  # the short-page check only catches the final page.
  describe "#fetch_all_matters (WR-07: non-Integer tail MatterId)" do
    # A fake connection answering a full page whose last MatterId is a
    # String, a corrupted row. The loop MUST stop after one or two rounds.
    let(:call_log) { [] }
    let(:bad_page) do
      999.times.map { |i| {"MatterId" => i + 1, "MatterTypeName" => "Bill"} } +
        [{"MatterId" => "not-an-integer", "MatterTypeName" => "Bill"}]
    end
    # A Struct standing in for Faraday::Response. fetch_all_matters reads
    # both status and body through Legistar::Client — always answering 200
    # keeps the paging guard the thing under test.
    let(:response_struct) { Struct.new(:status, :body) }
    # steep:ignore:start
    let(:bad_conn) do
      cl = call_log
      page = bad_page
      rs = response_struct
      Class.new do
        define_method(:get) do |*args|
          cl << args
          # Safety net: stop the test hanging if the paging guard is missing.
          raise "fetch_all_matters did not terminate (call ##{cl.size})" if cl.size > 5
          rs.new(200, page.to_json)
        end
      end.new
    end
    # steep:ignore:end

    it "terminates when the last MatterId in a full page is non-Integer" do
      service = described_class.new(run: run, faraday_conn: bad_conn)
      expect {
        service.send(:fetch_all_matters)
      }.not_to raise_error
      # The loop should make AT MOST 2 calls: the first one, and ideally it
      # stops right away. Without the guard it would re-query forever, which the
      # safety raise above cuts short.
      expect(call_log.size).to be <= 2
    end
  end

  # The same shape as FetchHearingsServices report, in the stage that runs
  # FIRST for the whole run. call_discover rescues only Faraday/Legistar, so
  # a malformed item kills the run before seeding.
  describe "malformed elements inside a well-formed Legistar array (A4-WR-04)" do
    let(:service) { described_class.new(run: run) }

    # #fetch_all_matters checks `page.is_a?(Array)` and then does
    # `page.last["MatterId"]` and hands every element to #build_metadata, which
    # opens with `matter["MatterTypeName"]`.
    it "skips non-Hash rows in a Matters page instead of raising" do
      stub_request(:get, /webapi\.legistar\.com\/v1\/baltimore\/Matters\?\$filter/).to_return(
        status: 200,
        body: [
          nil,
          {"MatterId" => 101, "MatterFile" => "25-0101", "MatterTypeName" => "Ordinance", "MatterTitle" => "A bill"},
          "not a row"
        ].to_json,
        headers: {"Content-Type" => "application/json"}
      )
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/101/Attachments})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})

      # Not raising IS the assertion. Setting metadatas to nil first and
      # assigning inside expect made Steep treat it as nil, turning the pluck
      # below into a type error.
      metadatas = service.call
      expect(metadatas.pluck(:external_id)).to eq(["25-0101"])
    end

    # #fetch_attachments checks `parsed.is_a?(Array)` and then hands every
    # element to #select_primary_attachment, which opens with
    # `a["MatterAttachmentFileName"]`.
    it "skips non-Hash rows in an Attachments array instead of raising" do
      stub_request(:get, /webapi\.legistar\.com\/v1\/baltimore\/Matters\?\$filter/).to_return(
        status: 200,
        body: [{"MatterId" => 102, "MatterFile" => "25-0102", "MatterTypeName" => "Ordinance", "MatterTitle" => "A bill"}].to_json,
        headers: {"Content-Type" => "application/json"}
      )
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/102/Attachments}).to_return(
        status: 200,
        body: [
          nil,
          {"MatterAttachmentId" => 1, "MatterAttachmentName" => "25-0102~1st Reader",
           "MatterAttachmentFileName" => "reader.pdf",
           "MatterAttachmentHyperlink" => "https://baltimore.legistar1.com/x/reader.pdf",
           "MatterAttachmentLastModifiedUtc" => "2026-01-01T00:00:00"}
        ].to_json,
        headers: {"Content-Type" => "application/json"}
      )
      stub_request(:get, "https://baltimore.legistar1.com/x/reader.pdf")
        .to_return(status: 200, body: "%PDF-1.4 reader")

      metadatas = nil
      expect { metadatas = service.call }.not_to raise_error
      expect(metadatas.first[:pdf_filename]).to eq("reader.pdf")
    end
  end

  # Two writes already had the not-a-BillProcessingError note; writes in the
  # same chain never got it. A disk-full error ends the run for every LATER
  # bill.
  describe "filesystem failures during persist (A4-WR-05)" do
    let(:service) { described_class.new(run: run) }

    before do
      stub_request(:get, /webapi\.legistar\.com\/v1\/baltimore\/Matters\?\$filter/).to_return(
        status: 200,
        body: [
          {"MatterId" => 201, "MatterFile" => "25-0201", "MatterTypeName" => "Ordinance", "MatterTitle" => "First"},
          {"MatterId" => 202, "MatterFile" => "25-0202", "MatterTypeName" => "Ordinance", "MatterTitle" => "Second"}
        ].to_json,
        headers: {"Content-Type" => "application/json"}
      )
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/20[12]/Attachments})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})
    end

    it "degrades per-bill instead of killing the run when metadata.json cannot be written" do
      allow(File).to receive(:write).and_raise(Errno::ENOSPC)

      expect { service.call }.not_to raise_error
      # The database rows are written before the disk loop, so both bills can
      # still be filled in later — which is the whole point of that ordering.
      expect(Bill.where(sway_locale: baltimore_locale).pluck(:external_id))
        .to include("25-0201", "25-0202")
    end

    it "keeps persisting later bills after one bill's directory cannot be created" do
      calls = 0
      allow(FileUtils).to receive(:mkdir_p).and_wrap_original do |original, dir|
        calls += 1
        raise Errno::EROFS if calls == 1

        original.call(dir)
      end

      expect { service.call }.not_to raise_error
      expect(File.exist?(File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, "25-0202", "metadata.json"))).to be(true)
    end
  end

  # The READING half of the same problem: read_disk_metadatas rescues only
  # JSON::ParserError, so a permission or I/O error aborts hydration for
  # every bill over one unreadable file.
  describe "filesystem failures during read (A1-WR-02)" do
    before { council_president }

    def write_metadata_for_read(external_id, matter_id:)
      dir = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, external_id)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "metadata.json"), {
        external_id: external_id,
        matter_id: matter_id,
        title: "An Ordinance for #{external_id}",
        introduction_date: "2025-01-15T00:00:00",
        bill_number: external_id,
        matter_type: "Ordinance"
      }.to_json)
    end

    def write_unreadable_metadata(external_id)
      FileUtils.mkdir_p(File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, external_id, "metadata.json"))
    end

    # The key case.
    it "skips an unreadable metadata.json instead of aborting the hydrate" do
      write_unreadable_metadata("CCB-25-0100")

      expect { expect(described_class.new(run: run).seed_from_disk).to eq(0) }.not_to raise_error
    end

    it "keeps seeding the readable rows in the same sweep" do
      write_unreadable_metadata("CCB-25-0100")
      write_metadata_for_read("CCB-25-0101", matter_id: 101)

      expect(described_class.new(run: run).seed_from_disk).to eq(1)
      expect(run.reload.pipeline_run_bills.pluck(:bill_external_id)).to eq(["CCB-25-0101"])
    end

    it "warns, matching the method's existing skip policy" do
      allow(SwayLogging).to receive(:warn)
      write_unreadable_metadata("CCB-25-0100")

      described_class.new(run: run).seed_from_disk

      expect(SwayLogging).to have_received(:warn).with(/unreadable metadata\.json/)
    end
  end

  # Time.zone.parse returns nil for some unreadable strings but RAISES
  # ArgumentError for others. The fallback only covers the nil case; the
  # raise escapes and spends a budget slot on bad data.
  describe "#coerce_introduction_date (WR-06: hard-unparseable strings)" do
    let(:service) { described_class.new(run: run) }

    it "warns and returns nil when Time.zone.parse raises ArgumentError" do
      expect(Rails.logger).to receive(:warn).with(/unparseable string/)
      result = service.send(:coerce_introduction_date, "BILL-WR06", "99-99-99")
      expect(result).to be_nil
    end

    it "does NOT raise BillProcessingError when the string is hard-unparseable" do
      expect {
        service.send(:coerce_introduction_date, "BILL-WR06", "2025-13-45")
      }.not_to raise_error
    end
  end

  describe "artifact root" do
    it "resolves the per-bill PDF/metadata root through Legislation::Paths" do
      # The around hook sets legislation_bills_raw_root to the temp directory
      # and the service writes there. How that path is worked out in full is
      # covered by spec/services/legislation/paths_spec.rb.
      expect(Legislation::Paths.bills_raw.to_s).to eq(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT)
    end
  end

  # Backfill mode, one bill at a time: runs when fetch-bills was pulled in
  # automatically, skipping bills with a PDF already, via matter_id.
  describe "per-bill backfill mode" do
    let(:bill_with_pdf) { create(:bill, external_id: "BFM-001", sway_locale: baltimore_locale, scheduled_release_date_utc: 100.days.ago) }
    let(:bill_without_pdf) { create(:bill, external_id: "BFM-002", sway_locale: baltimore_locale, scheduled_release_date_utc: 101.days.ago) }
    let!(:prb_with) { create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill_with_pdf.external_id, sort_order: 0) }
    let!(:prb_without) { create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill_without_pdf.external_id, sort_order: 1) }

    before do
      # Puts metadata.json on disk for both bills, as a previous discovery
      # run would. The top-level hook points the raw root at the temp root so
      # both lookups resolve to it.
      [[bill_with_pdf, 1001], [bill_without_pdf, 1002]].each do |bill, matter_id|
        dir = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, bill.external_id)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "metadata.json"), JSON.pretty_generate({"external_id" => bill.external_id, "matter_id" => matter_id}))
      end
      # Give bill_with_pdf a PDF so backfill skips it. The file sits under the
      # same temp root the presence check reads, and the top-level after hook
      # deletes it.
      File.binwrite(File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, bill_with_pdf.external_id, "existing.pdf"), "%PDF-FAKE")
    end

    # @lat: [[legislation-pipeline#Runs, resume and restart#A stage that produced nothing is not a success]]
    describe "a bill with no metadata.json" do
      let(:bill_without_metadata_dir) do
        File.join(
          FetchBillsServiceSpecHelpers::ARTIFACT_ROOT,
          FetchBillsServiceSpecHelpers::SWAY_LOCALE,
          bill_without_pdf.external_id
        )
      end

      # The named lookup: one bill asked for by its file number. Matched on the
      # id in the query so each bill can answer differently.
      def stub_named_lookup(external_id, matters)
        stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters\?.*#{Regexp.escape(external_id)}})
          .to_return(status: 200, body: matters.to_json, headers: {"Content-Type" => "application/json"})
      end

      def matter_row(external_id, matter_id)
        {
          "MatterId" => matter_id,
          "MatterFile" => external_id,
          "MatterTitle" => "A bill asked for by name",
          "MatterIntroDate" => "2025-03-04T00:00:00",
          "MatterTypeName" => "Ordinance"
        }
      end

      before do
        FileUtils.rm_rf(bill_without_metadata_dir)
        allow(SwayLogging).to receive(:warn)
      end

      it "asks Legistar for the bill by name and writes the metadata.json this mode reads" do
        stub_named_lookup(bill_without_pdf.external_id, [matter_row(bill_without_pdf.external_id, 1002)])
        stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/1002/Attachments})
          .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})

        expect { described_class.new(run: run, mode: :backfill_missing).call }.not_to raise_error

        expect(File.exist?(File.join(bill_without_metadata_dir, "metadata.json"))).to be(true)
      end

      # The full discovery would cost ~166 attachment lookups and ~166 PDF
      # downloads to repair one bill. Its filter is the one that names an
      # introduction-date range; the named lookup's is not.
      it "does not page the whole bill list" do
        stub_named_lookup(bill_without_pdf.external_id, [matter_row(bill_without_pdf.external_id, 1002)])
        stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/1002/Attachments})
          .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})

        described_class.new(run: run, mode: :backfill_missing).call

        expect(a_request(:get, %r{/Matters\?.*MatterIntroDate})).not_to have_been_made
      end

      # Discovery seeds a PipelineRunBill for every ordinance it finds, so
      # repairing one bill that way would grow the run past the bills the
      # operator picked — and the paid summarize stage would follow it there.
      it "adds no bills to the run" do
        stub_named_lookup(bill_without_pdf.external_id, [matter_row(bill_without_pdf.external_id, 1002)])
        stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/1002/Attachments})
          .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})

        expect { described_class.new(run: run, mode: :backfill_missing).call }
          .not_to change { run.pipeline_run_bills.count }
      end

      # @lat: [[legislation-pipeline#Runs, resume and restart#A stage that produced nothing is not a success]]
      it "refuses when upstream returns nothing for any of them" do
        stub_named_lookup(bill_without_pdf.external_id, [])

        expect { described_class.new(run: run, mode: :backfill_missing).call }
          .to raise_error(EmptyStageError, /could not acquire bill text for .* by name/)
      end

      # @lat: [[legislation-pipeline#Runs, resume and restart#A stage that produced nothing is not a success]]
      it "carries on when one bill is repaired and another is not" do
        gone = create(:bill, external_id: "BFMGONE", sway_locale: baltimore_locale, scheduled_release_date_utc: 104.days.ago)
        create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: gone.external_id, sort_order: 3)
        stub_named_lookup(bill_without_pdf.external_id, [matter_row(bill_without_pdf.external_id, 1002)])
        stub_named_lookup(gone.external_id, [])
        stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/1002/Attachments})
          .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})

        expect { described_class.new(run: run, mode: :backfill_missing).call }.not_to raise_error

        expect(SwayLogging).to have_received(:warn).with(/no bill text for BFMGONE/)
      end
    end

    # A bill that only needs its PDF must not pay for one that cannot be
    # repaired at all — the targeted downloads run first.
    it "still fetches the PDF for a ready bill when another bill cannot be repaired" do
      gone = create(:bill, external_id: "BFMGONE", sway_locale: baltimore_locale, scheduled_release_date_utc: 104.days.ago)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: gone.external_id, sort_order: 3)
      allow(SwayLogging).to receive(:warn)
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters\?.*#{gone.external_id}})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})
      ready_attachments = stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/1002/Attachments})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})

      described_class.new(run: run, mode: :backfill_missing).call

      expect(ready_attachments).to have_been_requested
    end

    # @lat: [[legislation-pipeline#Runs, resume and restart#A stage that produced nothing is not a success]]
    it "has already saved a ready bill's PDF when a later repair dies on the network" do
      gone = create(:bill, external_id: "BFMGONE", sway_locale: baltimore_locale, scheduled_release_date_utc: 104.days.ago)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: gone.external_id, sort_order: 3)
      allow_any_instance_of(Legislation::Adapters::GenericLegislationAdapter)
        .to receive(:repair_missing_metadata).with(gone.external_id, anything)
        .and_raise(Faraday::ConnectionFailed.new("upstream is gone"))
      ready_attachments = stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/1002/Attachments})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})

      expect { described_class.new(run: run, mode: :backfill_missing).call }
        .to raise_error(BillProcessingError)

      expect(ready_attachments).to have_been_requested
    end

    it "skips bills with PDF already present and fetches per-matter attachments for missing bills" do
      # Backfill must NOT page through the bill list; it must NOT touch
      # /Matters/1001/Attachments, whose PDF is already there; and it MUST touch
      # /Matters/1002/Attachments, whose PDF is missing.
      list_stub = stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters\?\$filter}).to_return(status: 500)
      attach_with = stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/1001/Attachments}).to_return(status: 500)
      attach_without = stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/1002/Attachments})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})

      described_class.new(run: run, mode: :backfill_missing).call

      expect(list_stub).not_to have_been_requested
      expect(attach_with).not_to have_been_requested
      expect(attach_without).to have_been_requested
    end

    # The same bug as FetchHearingsService#call_backfill_missing:
    # find_by(external_id:) treats it as identifying one bill, which it does
    # not — the bill it settles on decides the PDFs directory.
    it "refuses to process a bill_external_id that two locales share" do
      create(:bill, external_id: "BFM-DUP", sway_locale: baltimore_locale, scheduled_release_date_utc: 102.days.ago)
      # @lat: [[jurisdiction-rules#A test fixture names a jurisdiction in full or not at all]]
      other_locale = SwayLocale.find_or_create_by!(
        city: "congress", state: "congress", country: "united_states"
      )
      create(:bill, external_id: "BFM-DUP", sway_locale: other_locale, scheduled_release_date_utc: 103.days.ago)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: "BFM-DUP", sort_order: 2)
      dir = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, "BFM-DUP")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "metadata.json"), JSON.pretty_generate({"external_id" => "BFM-DUP", "matter_id" => 1003}))
      # bill_without_pdf (matter 1002) is another row in the same run and is
      # still processed. Fake its request so only the ambiguous id is under
      # test.
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/1002/Attachments})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})
      allow(SwayLogging).to receive(:warn)

      described_class.new(run: run, mode: :backfill_missing).call

      # No Legistar traffic at all for the ambiguous matter: the loop must move
      # on with `next` before it can decide which jurisdiction it is in.
      expect(a_request(:get, %r{/Matters/1003/Attachments})).not_to have_been_made
      expect(SwayLogging).to have_received(:warn).with(/BFM-DUP.*more than one sway_locale/m)
    end

    it "defaults to :discover when no mode kwarg given (back-compat)" do
      service = described_class.new(run: run)
      expect(service.instance_variable_get(:@mode)).to eq(:discover)
    end

    it "raises StageError on an unknown mode" do
      expect {
        described_class.new(run: run, mode: :bogus).call
      }.to raise_error(StageError, /unknown mode/)
    end

    # The second site with the same problem: Backfill's rescue counts a
    # network failure against budget — a filesystem error skipped it
    # entirely.
    it "raises BillProcessingError, not a bare Errno, when the backfill directory cannot be created" do
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/1002/Attachments}).to_return(
        status: 200,
        body: [{
          "MatterAttachmentId" => 1,
          "MatterAttachmentName" => "BFM-002~1st Reader",
          "MatterAttachmentFileName" => "reader.pdf",
          "MatterAttachmentHyperlink" => "https://baltimore.legistar1.com/x/bfm-002.pdf",
          "MatterAttachmentLastModifiedUtc" => "2026-01-01T00:00:00"
        }].to_json,
        headers: {"Content-Type" => "application/json"}
      )
      allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::ENOSPC)

      expect { described_class.new(run: run, mode: :backfill_missing).call }
        .to raise_error(BillProcessingError, /fetch_bills \(backfill\).*ENOSPC/)
    end
  end

  # @lat: [[legislation-pipeline#Empty discovery is a stage failure]]
  describe "#call with dynamic legislation_rules configuration" do
    [[], [{external_id: "FUTURE-1", title: "Future bill"}]].each do |discovered|
      it "#{discovered.empty? ? "rejects empty" : "accepts populated"} discovery via GenericLegislationAdapter" do
        future_rules = instance_double(
          SwayLocale::JurisdictionRules,
          legislation_rules: {engine: "generic_rest", base_url: "https://future.example.gov"}
        )
        future_locale = instance_double(SwayLocale, name: "future-region-country", jurisdiction_rules: future_rules)
        allow(run).to receive(:effective_sway_locale).and_return(future_locale)
        future_adapter = instance_double(Legislation::Adapters::GenericLegislationAdapter, discover: discovered)
        allow(Legislation::Adapters::GenericLegislationAdapter).to receive(:new).and_return(future_adapter)
        service = described_class.new(run: run, faraday_conn: Faraday.new)

        if discovered.empty?
          expect(service).not_to receive(:seed_ar_rows)
          expect(service).not_to receive(:persist_within_budget)
          expect { service.call }.to raise_error(EmptyStageError,
            "fetch_bills: no bills were discovered for future-region-country")
        else
          expect(service).to receive(:seed_ar_rows).with(discovered, future_locale)
          expect(service).to receive(:persist_within_budget).with(discovered)
          expect(service.call).to eq(discovered)
        end

        expect(future_adapter).to have_received(:discover)
          .with(hash_including(sway_locale: future_locale, service: service))
      end
    end
  end

  describe "#call — non-Baltimore jurisdiction rules" do
    let(:maryland_loc) { create(:sway_locale, :maryland) }
    let(:maryland_run) { create(:legislation_pipeline_run, sway_locale: maryland_loc) }

    it "routes discovery for Maryland through GenericLegislationAdapter and never contacts Legistar" do
      discovery_adapter = instance_double(Legislation::Adapters::GenericLegislationAdapter, discover: [])
      allow(Legislation::Adapters::GenericLegislationAdapter).to receive(:new).with(
        maryland_loc.jurisdiction_rules.legislation_rules,
        anything
      ).and_return(discovery_adapter)

      expect { described_class.new(run: maryland_run, mode: :discover).call }
        .to raise_error(EmptyStageError, /no bills were discovered for maryland-maryland-united_states/)

      expect(discovery_adapter).to have_received(:discover)
      expect(a_request(:any, /webapi\.legistar\.com/)).not_to have_been_made
    end

    it "routes backfill for Maryland through GenericLegislationAdapter and never contacts Legistar" do
      md_bill = create(:bill, external_id: "SB0001", sway_locale: maryland_loc)
      single_run = create(:legislation_pipeline_run, bill: md_bill, sway_locale: maryland_loc)
      create(:pipeline_run_bill, legislation_pipeline_run: single_run, bill_external_id: "SB0001")

      text_adapter = instance_double(Legislation::Adapters::GenericLegislationAdapter)
      allow(text_adapter).to receive(:backfill_bill) do |_b, ready:, **|
        ready << ["SB0001", maryland_loc.name, 12345]
      end
      allow(Legislation::Adapters::GenericLegislationAdapter).to receive(:new).with(
        md_bill.sway_locale.jurisdiction_rules.legislation_rules,
        anything
      ).and_return(text_adapter)

      described_class.new(run: single_run, mode: :backfill_missing).call

      expect(text_adapter).to have_received(:backfill_bill)
      expect(a_request(:any, /webapi\.legistar\.com/)).not_to have_been_made
    end
  end

  # @lat: [[legistar-matter-status-mapping#Ingestion pipeline status boundary]]
  describe "#build_metadata — upstream MatterStatusName mapping" do
    before do
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/\d+/Attachments})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})
    end

    it "maps MatterStatusName 'Enacted' to status 'passed'" do
      result = described_class.new(run: run).send(
        :build_metadata,
        {
          "MatterFile" => "CCB-25-0012",
          "MatterId" => 5160,
          "MatterTypeName" => "Ordinance",
          "MatterTitle" => "An Ordinance for Status Test",
          "MatterIntroDate" => "2025-01-15T00:00:00",
          "MatterStatusName" => "Enacted"
        }
      )
      expect(result[:status]).to eq("passed")
    end

    it "maps MatterStatusName 'Failed - End of Term' to status 'failed'" do
      result = described_class.new(run: run).send(
        :build_metadata,
        {
          "MatterFile" => "CCB-25-0012",
          "MatterId" => 5160,
          "MatterTypeName" => "Ordinance",
          "MatterTitle" => "An Ordinance for Status Test",
          "MatterIntroDate" => "2025-01-15T00:00:00",
          "MatterStatusName" => "Failed - End of Term"
        }
      )
      expect(result[:status]).to eq("failed")
    end

    it "maps MatterStatusName 'Vetoed by Mayor' to status 'vetoed'" do
      result = described_class.new(run: run).send(
        :build_metadata,
        {
          "MatterFile" => "CCB-25-0012",
          "MatterId" => 5160,
          "MatterTypeName" => "Ordinance",
          "MatterTitle" => "An Ordinance for Status Test",
          "MatterIntroDate" => "2025-01-15T00:00:00",
          "MatterStatusName" => "Vetoed by Mayor"
        }
      )
      expect(result[:status]).to eq("vetoed")
    end

    it "maps MatterStatusName 'In Committee' to status 'committee'" do
      result = described_class.new(run: run).send(
        :build_metadata,
        {
          "MatterFile" => "CCB-25-0012",
          "MatterId" => 5160,
          "MatterTypeName" => "Ordinance",
          "MatterTitle" => "An Ordinance for Status Test",
          "MatterIntroDate" => "2025-01-15T00:00:00",
          "MatterStatusName" => "In Committee"
        }
      )
      expect(result[:status]).to eq("committee")
    end

    it "returns status nil when MatterStatusName is omitted" do
      matter = {
        "MatterFile" => "CCB-25-0012",
        "MatterId" => 5160,
        "MatterTypeName" => "Ordinance",
        "MatterTitle" => "An Ordinance",
        "MatterIntroDate" => "2025-01-15T00:00:00"
      }
      result = described_class.new(run: run).send(:build_metadata, matter)
      expect(result[:status]).to be_nil
    end

    it "returns status nil when MatterStatusName is unrecognised" do
      result = described_class.new(run: run).send(
        :build_metadata,
        {
          "MatterFile" => "CCB-25-0012",
          "MatterId" => 5160,
          "MatterTypeName" => "Ordinance",
          "MatterTitle" => "An Ordinance for Status Test",
          "MatterIntroDate" => "2025-01-15T00:00:00",
          "MatterStatusName" => "Unrecognised Legistar Status"
        }
      )
      expect(result[:status]).to be_nil
    end
  end

  # @lat: [[legistar-detail-url-resolution#Ingestion pipeline integration and fallback elimination]]
  describe "#build_metadata — Legistar detail URL resolution" do
    let(:service) { described_class.new(run: run) }

    before do
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/\d+/Attachments})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})
    end

    it "resolves and includes canonical Legistar detail URL when Gateway returns 302" do
      matter = {
        "MatterId" => 10599,
        "MatterFile" => "CCB-26-0217",
        "MatterTitle" => "Data Centers Over 5 Megawatts",
        "MatterIntroDate" => "2026-01-15T00:00:00",
        "MatterTypeName" => "Ordinance",
        "MatterStatusName" => "In Committee"
      }
      stub_request(:head, "https://baltimore.legistar.com/Gateway.aspx")
        .with(query: {"M" => "L", "ID" => "10599"})
        .to_return(
          status: 302,
          headers: {"Location" => "/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"}
        )

      result = service.send(:build_metadata, matter)

      expect(result[:link]).to eq(
        "https://baltimore.legistar.com/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
      )
    end

    it "sets link to nil when Gateway returns non-redirect response (e.g. 200 or 404)" do
      matter = {
        "MatterId" => 10599,
        "MatterFile" => "CCB-26-0217",
        "MatterTitle" => "Data Centers Over 5 Megawatts",
        "MatterIntroDate" => "2026-01-15T00:00:00",
        "MatterTypeName" => "Ordinance"
      }
      stub_request(:head, "https://baltimore.legistar.com/Gateway.aspx")
        .with(query: {"M" => "L", "ID" => "10599"})
        .to_return(status: 200, body: "19-byte error body")

      result = service.send(:build_metadata, matter)

      expect(result[:link]).to be_nil
    end

    it "sets link to nil when Gateway request encounters a network error without raising" do
      matter = {
        "MatterId" => 10599,
        "MatterFile" => "CCB-26-0217",
        "MatterTitle" => "Data Centers Over 5 Megawatts",
        "MatterIntroDate" => "2026-01-15T00:00:00",
        "MatterTypeName" => "Ordinance"
      }
      stub_request(:head, "https://baltimore.legistar.com/Gateway.aspx")
        .with(query: {"M" => "L", "ID" => "10599"})
        .to_raise(Faraday::TimeoutError.new("connection timeout"))

      result = service.send(:build_metadata, matter)

      expect(result[:link]).to be_nil
    end

    it "sets link to nil without requesting Gateway when MatterId is missing" do
      matter = {
        "MatterFile" => "CCB-26-0217",
        "MatterTitle" => "No Matter ID",
        "MatterIntroDate" => "2026-01-15T00:00:00",
        "MatterTypeName" => "Ordinance"
      }

      result = service.send(:build_metadata, matter)

      expect(result).to be_nil
      expect(a_request(:head, %r{baltimore\.legistar\.com/Gateway\.aspx})).not_to have_been_made
    end
  end

  # @lat: [[legistar-matter-status-mapping#Ingestion pipeline status boundary]]
  describe "#bill_data_from_metadata — status propagation" do
    it "forwards mapped status to the bill payload" do
      service = described_class.new(run: run)
      metadata = {
        external_id: "CCB-25-0013",
        matter_id: 5161,
        title: "Title",
        introduction_date: "2025-01-15T00:00:00",
        bill_number: "CCB-25-0013",
        matter_type: "Ordinance",
        pdf_url: nil,
        pdf_filename: nil,
        status: "passed"
      }
      data = service.send(:bill_data_from_metadata, metadata, baltimore_locale)
      expect(data["status"]).to eq("passed")
    end

    it "forwards nil status when metadata status is nil" do
      service = described_class.new(run: run)
      metadata = {
        external_id: "CCB-25-0013",
        matter_id: 5161,
        title: "Title",
        introduction_date: "2025-01-15T00:00:00",
        bill_number: "CCB-25-0013",
        matter_type: "Ordinance",
        pdf_url: nil,
        pdf_filename: nil,
        status: nil
      }
      data = service.send(:bill_data_from_metadata, metadata, baltimore_locale)
      expect(data["status"]).to be_nil
    end

    it "forwards nil status when metadata has no status key" do
      service = described_class.new(run: run)
      metadata = {
        external_id: "CCB-25-0013",
        matter_id: 5161,
        title: "Title",
        introduction_date: "2025-01-15T00:00:00",
        bill_number: "CCB-25-0013",
        matter_type: "Ordinance",
        pdf_url: nil,
        pdf_filename: nil
      }
      data = service.send(:bill_data_from_metadata, metadata, baltimore_locale)
      expect(data["status"]).to be_nil
    end
  end

  # @lat: [[legistar-detail-url-resolution#Ingestion pipeline integration and fallback elimination]]
  describe "#bill_data_from_metadata — link propagation" do
    let(:service) { described_class.new(run: run) }

    it "forwards resolved link to the bill payload" do
      metadata = {
        external_id: "CCB-26-0217",
        matter_id: 10599,
        title: "Title",
        introduction_date: "2026-01-15T00:00:00",
        bill_number: "CCB-26-0217",
        matter_type: "Ordinance",
        pdf_url: nil,
        pdf_filename: nil,
        status: "committee",
        link: "https://baltimore.legistar.com/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
      }
      data = service.send(:bill_data_from_metadata, metadata, baltimore_locale)
      expect(data["link"]).to eq(
        "https://baltimore.legistar.com/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
      )
    end

    it "forwards nil link when metadata link is nil" do
      metadata = {
        external_id: "CCB-26-0217",
        matter_id: 10599,
        title: "Title",
        introduction_date: "2026-01-15T00:00:00",
        bill_number: "CCB-26-0217",
        matter_type: "Ordinance",
        pdf_url: nil,
        pdf_filename: nil,
        status: "committee",
        link: nil
      }
      data = service.send(:bill_data_from_metadata, metadata, baltimore_locale)
      expect(data["link"]).to be_nil
    end

    it "forwards nil link when metadata has no link key" do
      metadata = {
        external_id: "CCB-26-0217",
        matter_id: 10599,
        title: "Title",
        introduction_date: "2026-01-15T00:00:00",
        bill_number: "CCB-26-0217",
        matter_type: "Ordinance",
        pdf_url: nil,
        pdf_filename: nil,
        status: "committee"
      }
      data = service.send(:bill_data_from_metadata, metadata, baltimore_locale)
      expect(data["link"]).to be_nil
    end
  end

  describe "#bill_data_from_metadata — session resolution delegation" do
    it "does not include legislative_session_id, delegating session resolution to LegislationIngestionService" do
      service = described_class.new(run: run)
      metadata = {
        external_id: "CCB-25-0099",
        title: "Test Session Delegation Bill",
        matter_id: 12345,
        bill_number: "25-0099",
        matter_type: "Ordinance",
        introduction_date: "2025-03-01T00:00:00",
        pdf_url: nil,
        pdf_filename: nil
      }
      data = service.send(:bill_data_from_metadata, metadata, baltimore_locale)
      expect(data).not_to have_key("legislative_session_id")
      expect(data["legislative_session_id"]).to be_nil
    end

    it "persists bills with legislative_session resolved by LegislationIngestionService from introduction date" do
      session = create(
        :legislative_session,
        :active,
        sway_locale: baltimore_locale,
        name: "2024-2028 Term",
        start_date: Date.new(2024, 12, 5),
        end_date: Date.new(2028, 12, 5)
      )
      service = described_class.new(run: run)
      metadata = {
        external_id: "CCB-25-0100",
        title: "Test Seed AR Rows Session Bill",
        matter_id: 12346,
        bill_number: "25-0100",
        matter_type: "Ordinance",
        introduction_date: "2025-04-15T00:00:00",
        pdf_url: nil,
        pdf_filename: nil
      }

      service.send(:seed_ar_rows, [metadata], baltimore_locale)

      bill = Bill.find_by!(external_id: "CCB-25-0100", sway_locale: baltimore_locale)
      expect(bill.legislative_session).to eq(session)
      expect(bill.active).to be true
    end

    it "persists bills with historical legislative_session and active: false when introduction date is in past session" do
      past_session = create(
        :legislative_session,
        active: false,
        sway_locale: baltimore_locale,
        name: "2020-2024 Term",
        start_date: Date.new(2020, 12, 5),
        end_date: Date.new(2024, 12, 4)
      )
      service = described_class.new(run: run)
      metadata = {
        external_id: "CCB-22-0101",
        title: "Test Historical Seed AR Rows Session Bill",
        matter_id: 12347,
        bill_number: "22-0101",
        matter_type: "Ordinance",
        introduction_date: "2022-06-01T00:00:00",
        pdf_url: nil,
        pdf_filename: nil
      }

      service.send(:seed_ar_rows, [metadata], baltimore_locale)

      bill = Bill.find_by!(external_id: "CCB-22-0101", sway_locale: baltimore_locale)
      expect(bill.legislative_session).to eq(past_session)
      expect(bill.active).to be false
    end

    it "persists bills safely when introduction date is nil, delegating fallback to LegislationIngestionService" do
      active_session = create(
        :legislative_session,
        :active,
        sway_locale: baltimore_locale,
        name: "Current Term",
        start_date: 1.year.ago.to_date,
        end_date: 1.year.from_now.to_date
      )
      service = described_class.new(run: run)
      metadata = {
        external_id: "CCB-25-NIL-DATE",
        title: "Test Nil Date Seed AR Rows Bill",
        matter_id: 12348,
        bill_number: "25-NIL",
        matter_type: "Ordinance",
        introduction_date: nil,
        pdf_url: nil,
        pdf_filename: nil
      }

      service.send(:seed_ar_rows, [metadata], baltimore_locale)

      bill = Bill.find_by!(external_id: "CCB-25-NIL-DATE", sway_locale: baltimore_locale)
      expect(bill.legislative_session).to eq(active_session)
    end
  end

  describe "#call — AR seeding with upstream status" do
    it "persists the upstream mapped status to the created Bill rows" do
      matters = [
        {
          "MatterId" => 101,
          "MatterFile" => "CCB-25-0001",
          "MatterTitle" => "Passed Bill",
          "MatterIntroDate" => "2025-01-15T00:00:00",
          "MatterTypeName" => "Ordinance",
          "MatterStatusName" => "Enacted"
        },
        {
          "MatterId" => 102,
          "MatterFile" => "CCB-25-0002",
          "MatterTitle" => "Failed Bill",
          "MatterIntroDate" => "2025-02-20T00:00:00",
          "MatterTypeName" => "Ordinance",
          "MatterStatusName" => "Failed - End of Term"
        }
      ]
      stub_request(:get, /webapi\.legistar\.com\/v1\/baltimore\/Matters\?\$filter/)
        .to_return(status: 200, body: matters.to_json, headers: {"Content-Type" => "application/json"})
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/\d+/Attachments})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})
      stub_request(:head, %r{baltimore\.legistar\.com/Gateway\.aspx})
        .to_return(status: 404)

      described_class.new(run: run).call

      bill_passed = Bill.find_by!(external_id: "CCB-25-0001", sway_locale: baltimore_locale)
      bill_failed = Bill.find_by!(external_id: "CCB-25-0002", sway_locale: baltimore_locale)

      expect(bill_passed.status).to eq("passed")
      expect(bill_failed.status).to eq("failed")
    end
  end

  # @lat: [[legistar-detail-url-resolution#Ingestion pipeline integration and fallback elimination]]
  describe "#call — AR seeding with real Legistar detail URLs and refusal rule" do
    it "persists real Legistar detail URL on successful resolution and nil on resolution failure without failing the run" do
      matters = [
        {
          "MatterId" => 10599,
          "MatterFile" => "CCB-26-0217",
          "MatterTitle" => "Data Centers Over 5 Megawatts",
          "MatterIntroDate" => "2026-01-15T00:00:00",
          "MatterTypeName" => "Ordinance",
          "MatterStatusName" => "In Committee"
        },
        {
          "MatterId" => 10600,
          "MatterFile" => "CCB-26-0218",
          "MatterTitle" => "Unresolvable Bill",
          "MatterIntroDate" => "2026-02-01T00:00:00",
          "MatterTypeName" => "Ordinance",
          "MatterStatusName" => "In Committee"
        }
      ]
      stub_request(:get, /webapi\.legistar\.com\/v1\/baltimore\/Matters\?\$filter/)
        .to_return(status: 200, body: matters.to_json, headers: {"Content-Type" => "application/json"})
      stub_request(:get, %r{webapi\.legistar\.com/v1/baltimore/Matters/\d+/Attachments})
        .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})

      # Matter 10599 succeeds
      stub_request(:head, "https://baltimore.legistar.com/Gateway.aspx")
        .with(query: {"M" => "L", "ID" => "10599"})
        .to_return(
          status: 302,
          headers: {"Location" => "/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"}
        )

      # Matter 10600 fails at gateway (404)
      stub_request(:head, "https://baltimore.legistar.com/Gateway.aspx")
        .with(query: {"M" => "L", "ID" => "10600"})
        .to_return(status: 404)

      expect { described_class.new(run: run).call }.not_to raise_error

      bill_resolved = Bill.find_by!(external_id: "CCB-26-0217", sway_locale: baltimore_locale)
      bill_unresolved = Bill.find_by!(external_id: "CCB-26-0218", sway_locale: baltimore_locale)

      expect(bill_resolved.link).to eq(
        "https://baltimore.legistar.com/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570"
      )
      expect(bill_unresolved.link).to be_nil
      expect(bill_unresolved.link).not_to eq("https://baltimore.legistar.com/LegislationSearch.aspx")
    end
  end

  describe "Decoupled from direct Legistar client" do
    let(:service) { described_class.new(run: run) }

    it "delegates discovery to GenericLegislationAdapter#discover" do
      adapter_double = instance_double(Legislation::Adapters::GenericLegislationAdapter)
      allow(service).to receive(:adapter_for).and_return(adapter_double)

      expect(adapter_double).to receive(:discover).with(
        hash_including(sway_locale: baltimore_locale)
      ).and_return([
        {
          external_id: "24-0001",
          matter_id: 1234,
          title: "Test Ordinance",
          introduction_date: "2026-01-01",
          bill_number: "24-0001",
          matter_type: "Ordinance",
          pdf_url: nil,
          pdf_filename: nil,
          status: "passed",
          link: nil
        }
      ])

      service.send(:call_discover)
    end

    it "delegates backfill to GenericLegislationAdapter#backfill_bill" do
      test_bill = create(:bill, external_id: "24-0001", sway_locale: baltimore_locale)
      create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: test_bill.external_id, sort_order: 1)
      adapter_double = instance_double(Legislation::Adapters::GenericLegislationAdapter)
      allow_any_instance_of(described_class).to receive(:adapter_for).and_return(adapter_double)

      expect(adapter_double).to receive(:backfill_bill).with(
        test_bill,
        hash_including(ready: a_kind_of(Array), undiscovered: a_kind_of(Array))
      )
      allow(adapter_double).to receive(:repair_missing_metadata).and_return(true)

      described_class.new(run: run, mode: :backfill_missing).call
    end
  end

  describe "#default_faraday_conn" do
    let(:service) { described_class.new(run: run) }

    before do
      @mock_rules = instance_double(SwayLocale::JurisdictionRules, legislation_rules: nil)
      allow(service).to receive(:resolve_sway_locale).and_return(baltimore_locale)
      allow(baltimore_locale).to receive(:jurisdiction_rules).and_return(@mock_rules)
    end

    it "selects congress_gov connection when retrieval is congress_dot_gov without hardcoded CONGRESS_GOV_API_KEY check" do
      allow(@mock_rules).to receive(:legislation_rules).and_return({
        retrieval: "congress_dot_gov",
        api_key_secret: "CUSTOM_SECRET_ENV_VAR"
      })
      allow(Sway::FaradayStack).to receive(:congress_gov).and_call_original

      conn = service.send(:default_faraday_conn)
      expect(Sway::FaradayStack).to have_received(:congress_gov)
      expect(conn).to be_a(Faraday::Connection)
    end

    it "selects congress_gov connection when retrieval is congress" do
      allow(@mock_rules).to receive(:legislation_rules).and_return({
        retrieval: "congress"
      })
      allow(Sway::FaradayStack).to receive(:congress_gov).and_call_original

      conn = service.send(:default_faraday_conn)
      expect(Sway::FaradayStack).to have_received(:congress_gov)
      expect(conn).to be_a(Faraday::Connection)
    end

    it "builds a custom Faraday connection when base_url is present and retrieval is not congress or legistar" do
      allow(@mock_rules).to receive(:legislation_rules).and_return({
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
      allow(@mock_rules).to receive(:legislation_rules).and_return({
        retrieval: "legistar"
      })
      allow(Sway::FaradayStack).to receive(:legistar).and_call_original

      conn = service.send(:default_faraday_conn)
      expect(Sway::FaradayStack).to have_received(:legistar)
      expect(conn).to be_a(Faraday::Connection)
    end

    it "raises StageError when legislation_rules is nil and does not default to legistar" do
      allow(@mock_rules).to receive(:legislation_rules).and_return(nil)
      allow(Sway::FaradayStack).to receive(:legistar)

      expect {
        service.send(:default_faraday_conn)
      }.to raise_error(StageError, "fetch_bills: connection rules lack a valid retrieval strategy or base_url for baltimore-maryland-united_states")

      expect(Sway::FaradayStack).not_to have_received(:legistar)
    end

    it "raises StageError when jurisdiction_rules is nil and does not default to legistar" do
      allow(baltimore_locale).to receive(:jurisdiction_rules).and_return(nil)
      allow(Sway::FaradayStack).to receive(:legistar)

      expect {
        service.send(:default_faraday_conn)
      }.to raise_error(StageError, "fetch_bills: connection rules lack a valid retrieval strategy or base_url for baltimore-maryland-united_states")

      expect(Sway::FaradayStack).not_to have_received(:legistar)
    end

    it "raises StageError and does not default to Sway::FaradayStack.legistar when retrieval is unrecognized and base_url is blank" do
      allow(@mock_rules).to receive(:legislation_rules).and_return({
        retrieval: "unrecognized_retrieval",
        base_url: ""
      })
      allow(Sway::FaradayStack).to receive(:legistar)

      expect {
        service.send(:default_faraday_conn)
      }.to raise_error(StageError, "fetch_bills: connection rules lack a valid retrieval strategy or base_url for baltimore-maryland-united_states")

      expect(Sway::FaradayStack).not_to have_received(:legistar)
    end

    it "raises StageError with 'nil' when resolve_sway_locale is nil" do
      allow(service).to receive(:resolve_sway_locale).and_return(nil)
      allow(Sway::FaradayStack).to receive(:legistar)

      expect {
        service.send(:default_faraday_conn)
      }.to raise_error(StageError, "fetch_bills: connection rules lack a valid retrieval strategy or base_url for nil")

      expect(Sway::FaradayStack).not_to have_received(:legistar)
    end
  end

  describe "unusable external_id safety" do
    describe "#persist" do
      it "logs a warning, returns nil, and does not raise UnsafeExternalIdError" do
        allow(SwayLogging).to receive(:warn)
        service = described_class.new(run: run)

        expect {
          service.send(:persist, {external_id: "../../etc/passwd", title: "Unusable ID"}, download: false)
        }.not_to raise_error

        expect(SwayLogging).to have_received(:warn).with(/unusable external_id.*etc\/passwd/i)
      end
    end

    describe "#call (discover mode — unusable external_id safety)" do
      it "persists valid bills, logs a warning, skips the unusable bill id, and does not raise" do
        allow(SwayLogging).to receive(:warn).and_call_original

        mock_adapter = instance_double(Legislation::Adapters::GenericLegislationAdapter)
        allow_any_instance_of(described_class).to receive(:adapter_for).and_return(mock_adapter)

        # batch contains one valid bill and one path traversal external_id
        batch = [
          {
            external_id: "BFM-GOOD-01",
            title: "Good bill",
            introduction_date: "2025-01-15T00:00:00",
            pdf_url: nil,
            pdf_filename: nil
          },
          {
            external_id: "../../etc/passwd",
            title: "Unusable ID bill",
            introduction_date: "2025-01-15T00:00:00",
            pdf_url: nil,
            pdf_filename: nil
          }
        ]
        allow(mock_adapter).to receive(:discover).and_return(batch)

        expect {
          described_class.new(run: run).call
        }.not_to raise_error

        expect(SwayLogging).to have_received(:warn).with(/unusable external_id.*etc\/passwd/i).at_least(:once)

        good_meta_path = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, "BFM-GOOD-01", "metadata.json")
        expect(File.exist?(good_meta_path)).to be(true)

        bad_meta_path = File.join(FetchBillsServiceSpecHelpers::ARTIFACT_ROOT, FetchBillsServiceSpecHelpers::SWAY_LOCALE, "../../etc/passwd", "metadata.json")
        expect(File.exist?(bad_meta_path)).to be(false)
      end
    end
  end

  describe "error handling in discover and backfill" do
    describe "#call_discover" do
      it "wraps Faraday::Error in BillProcessingError" do
        mock_adapter = instance_double(Legislation::Adapters::GenericLegislationAdapter)
        allow_any_instance_of(described_class).to receive(:adapter_for).and_return(mock_adapter)
        allow(mock_adapter).to receive(:discover).and_raise(Faraday::ConnectionFailed.new("connection failed"))

        expect { described_class.new(run: run).call }
          .to raise_error(BillProcessingError, /fetch_bills network error: connection failed/)
      end

      it "wraps adapter BillProcessingError containing network error in BillProcessingError" do
        mock_adapter = instance_double(Legislation::Adapters::GenericLegislationAdapter)
        allow_any_instance_of(described_class).to receive(:adapter_for).and_return(mock_adapter)
        allow(mock_adapter).to receive(:discover).and_raise(BillProcessingError.new("fetch_bills: Faraday::TimeoutError: timed out"))

        expect { described_class.new(run: run).call }
          .to raise_error(BillProcessingError, /fetch_bills network error: fetch_bills: Faraday::TimeoutError: timed out/)
      end

      it "re-raises adapter non-network BillProcessingError directly" do
        mock_adapter = instance_double(Legislation::Adapters::GenericLegislationAdapter)
        allow_any_instance_of(described_class).to receive(:adapter_for).and_return(mock_adapter)
        allow(mock_adapter).to receive(:discover).and_raise(BillProcessingError.new("fetch_bills: base_url is required"))

        expect { described_class.new(run: run).call }
          .to raise_error(BillProcessingError, "fetch_bills: base_url is required")
      end
    end

    describe "#call_backfill_missing" do
      it "wraps Faraday::Error in BillProcessingError" do
        backfill_service = described_class.new(run: run, mode: :backfill_missing)
        bill = create(:bill, external_id: "BFM-ERR-1", sway_locale: baltimore_locale)
        create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill.external_id)
        mock_adapter = instance_double(Legislation::Adapters::GenericLegislationAdapter)
        allow(backfill_service).to receive(:adapter_for).and_return(mock_adapter)
        allow(mock_adapter).to receive(:backfill_bill).and_raise(Faraday::TimeoutError.new("timed out"))

        expect { backfill_service.call }
          .to raise_error(BillProcessingError, /fetch_bills \(backfill\) network error: timed out/)
      end

      it "re-raises domain BillProcessingError directly" do
        backfill_service = described_class.new(run: run, mode: :backfill_missing)
        bill = create(:bill, external_id: "BFM-ERR-2", sway_locale: baltimore_locale)
        create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill.external_id)
        mock_adapter = instance_double(Legislation::Adapters::GenericLegislationAdapter)
        allow(backfill_service).to receive(:adapter_for).and_return(mock_adapter)
        allow(mock_adapter).to receive(:backfill_bill).and_raise(BillProcessingError.new("fetch_bills: corrupt artifact"))

        expect { backfill_service.call }
          .to raise_error(BillProcessingError, "fetch_bills: corrupt artifact")
      end
    end
  end
end
