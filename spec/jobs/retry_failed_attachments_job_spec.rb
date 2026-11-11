# frozen_string_literal: true

require "rails_helper"

RSpec.describe RetryFailedAttachmentsJob do
  let(:baltimore) { create(:sway_locale, :baltimore) }
  let(:bill) { create(:bill, external_id: "TEST-200", sway_locale: baltimore) }
  let(:download_url) { "https://baltimore.legistar1.com/attachments/981.pdf" }

  def create_attempt_entry(bill:, attachment_id: 981, url: download_url, filename: "testimony_981.pdf",
    outcome: "failed", error: "Faraday::ConnectionFailed: connection refused",
    created_at: 25.hours.ago)
    entry = PipelineActivityLogEntry.create!(
      event_type: "attachment_download_attempt",
      subject_type: "Bill",
      subject_id: bill.id.to_s,
      severity: "info",
      title: "Attachment download attempt",
      message: "Attachment #{attachment_id} download #{outcome}",
      payload: {
        "bill_id" => bill.id,
        "bill_external_id" => bill.external_id,
        "sway_locale_id" => bill.sway_locale_id,
        "attachment_id" => attachment_id,
        "filename" => filename,
        "url" => url,
        "status" => outcome,
        "outcome" => outcome,
        "error" => error,
        "attempted_at" => created_at.iso8601
      }
    )
    PipelineActivityLogEntry.where(id: entry.id).update_all(created_at: created_at)
    entry
  end

  before do
    allow(PipelineActivityLogger::Transport).to receive(:dispatch)
  end

  # @lat: [[attachment-attempts#Attachment download attempts#Later retry selection rules]]
  describe "#perform" do
    it "retries an attachment whose last attempt was a transport failure older than the wait window and updates the testimony mirror through the existing writer" do
      bill.create_bill_llm_provisioning!(
        testimony_attachments: [
          {
            "filename" => "testimony_981.pdf",
            "attachment_id" => "981",
            "download_status" => "failed",
            "extraction_status" => "skipped",
            "error" => "Faraday::ConnectionFailed: connection refused"
          }
        ],
        extracted_testimony: nil
      )

      create_attempt_entry(
        bill: bill,
        attachment_id: 981,
        url: download_url,
        outcome: "failed",
        error: "Faraday::ConnectionFailed: connection refused",
        created_at: 25.hours.ago
      )

      stub_request(:get, download_url)
        .to_return(
          status: 200,
          body: "%PDF-1.4 mock pdf content for testimony",
          headers: {"Content-Type" => "application/pdf"}
        )

      extractor = instance_double(TestimonyTextExtractor, call: "Dear Council Members, I support this bill.")
      allow(TestimonyTextExtractor).to receive(:new).and_return(extractor)

      expect {
        described_class.new.perform
      }.to change { PipelineActivityLogEntry.count }.by(1)

      latest_entry = PipelineActivityLogEntry.order(id: :desc).first!
      expect(latest_entry.event_type).to eq("attachment_download_attempt")
      expect(latest_entry.payload["outcome"]).to eq("succeeded")
      expect(latest_entry.payload["attachment_id"].to_s).to eq("981")

      provisioning = bill.reload.bill_llm_provisioning
      mirror = provisioning.testimony_attachments
      expect(mirror).to be_an(Array)
      retried_entry = mirror.find { |e| e["attachment_id"] == "981" }
      expect(retried_entry).to be_present
      expect(retried_entry["download_status"]).to eq("succeeded")
      expect(retried_entry["extraction_status"]).to eq("succeeded")
      expect(retried_entry["error"]).to be_nil
      expect(provisioning.extracted_testimony).to include("Dear Council Members, I support this bill.")
    end

    it "retries an attachment whose last attempt was a budget skip older than the wait window and succeeds" do
      bill.create_bill_llm_provisioning!(
        testimony_attachments: [
          {
            "filename" => "testimony_981.pdf",
            "attachment_id" => "981",
            "download_status" => "skipped_time_budget",
            "extraction_status" => "not_attempted",
            "error" => "this bill's 900s download budget was exhausted"
          }
        ]
      )

      create_attempt_entry(
        bill: bill,
        attachment_id: 981,
        url: download_url,
        outcome: "skipped_time_budget",
        error: "this bill's 900s download budget was exhausted before this attachment was reached",
        created_at: 26.hours.ago
      )

      stub_request(:get, download_url)
        .to_return(status: 200, body: "%PDF-1.4 budget retry content")

      extractor = instance_double(TestimonyTextExtractor, call: "Recovered testimony text.")
      allow(TestimonyTextExtractor).to receive(:new).and_return(extractor)

      expect {
        described_class.new.perform
      }.to change { PipelineActivityLogEntry.count }.by(1)

      provisioning = bill.reload.bill_llm_provisioning
      retried_entry = provisioning.testimony_attachments.find { |e| e["attachment_id"] == "981" }
      expect(retried_entry["download_status"]).to eq("succeeded")
      expect(retried_entry["extraction_status"]).to eq("succeeded")
      expect(provisioning.extracted_testimony).to include("Recovered testimony text.")
    end

    it "does NOT retry an attachment whose last attempt was a permanent rejection" do
      permanent_errors = [
        "blocked url: host=evil.com is not an allowed Legistar attachment host",
        "too many redirects (limit 3)",
        "attachment has no download url",
        "response body is not a PDF (magic-byte check failed)",
        "HTTP 404",
        "response advertises 40000000 bytes, over the 33554432-byte cap"
      ]

      permanent_errors.each_with_index do |err, idx|
        url = err.include?("evil.com") ? "https://evil.com/attachments/#{1000 + idx}.pdf" : "https://baltimore.legistar1.com/attachments/#{1000 + idx}.pdf"
        create_attempt_entry(
          bill: bill,
          attachment_id: 1000 + idx,
          url: url,
          outcome: "failed",
          error: err,
          created_at: 30.hours.ago
        )
      end

      expect {
        described_class.new.perform
      }.not_to change { PipelineActivityLogEntry.count }
    end

    it "does NOT retry an attachment that has already exhausted the attempt limit (MAX_ATTEMPTS = 3)" do
      3.times do |i|
        create_attempt_entry(
          bill: bill,
          attachment_id: 981,
          url: download_url,
          outcome: "failed",
          error: "Faraday::TimeoutError: execution expired",
          created_at: (30 + i).hours.ago
        )
      end

      expect {
        described_class.new.perform
      }.not_to change { PipelineActivityLogEntry.count }
    end

    it "does NOT retry an attachment whose first attempt aged past the 14-day lookback window" do
      create_attempt_entry(
        bill: bill,
        attachment_id: 981,
        url: download_url,
        outcome: "failed",
        error: "Faraday::TimeoutError: execution expired",
        created_at: 15.days.ago
      )
      create_attempt_entry(
        bill: bill,
        attachment_id: 981,
        url: download_url,
        outcome: "failed",
        error: "Faraday::TimeoutError: execution expired",
        created_at: 26.hours.ago
      )

      expect {
        described_class.new.perform
      }.not_to change { PipelineActivityLogEntry.count }
    end

    it "does NOT retry an attachment attempted more recently than the wait window (24 hours)" do
      create_attempt_entry(
        bill: bill,
        attachment_id: 981,
        url: download_url,
        outcome: "failed",
        error: "Faraday::ConnectionFailed",
        created_at: 4.hours.ago
      )

      expect {
        described_class.new.perform
      }.not_to change { PipelineActivityLogEntry.count }
    end

    it "does NOT retry an attachment for a bill that is currently running an active pipeline" do
      create_attempt_entry(
        bill: bill,
        attachment_id: 981,
        url: download_url,
        outcome: "failed",
        error: "Faraday::ConnectionFailed",
        created_at: 25.hours.ago
      )

      create(:legislation_pipeline_run, bill: bill, status: "running")

      expect {
        described_class.new.perform
      }.not_to change { PipelineActivityLogEntry.count }
    end

    it "does NOT retry an attachment that is already marked succeeded in the bill testimony mirror" do
      bill.create_bill_llm_provisioning!(
        testimony_attachments: [
          {
            "filename" => "testimony_981.pdf",
            "attachment_id" => "981",
            "download_status" => "succeeded",
            "extraction_status" => "succeeded",
            "error" => nil
          }
        ]
      )

      create_attempt_entry(
        bill: bill,
        attachment_id: 981,
        url: download_url,
        outcome: "failed",
        error: "Faraday::ConnectionFailed",
        created_at: 25.hours.ago
      )

      expect {
        described_class.new.perform
      }.not_to change { PipelineActivityLogEntry.count }
    end

    it "raises ArgumentError when retry_single_attachment! is called with an invalid attachment_id" do
      service = FetchHearingsService.new(bill: bill)
      expect {
        service.retry_single_attachment!(
          attachment_id: "invalid_id",
          url: download_url,
          filename: "testimony.pdf"
        )
      }.to raise_error(ArgumentError, /invalid attachment_id/)
    end
  end

  describe "recurring.yml schedule registration" do
    let(:recurring_config) { YAML.load_file(Rails.root.join("config", "recurring.yml")) }

    %w[development production].each do |env|
      it "registers retry_failed_attachments under #{env}: on the background queue with a Fugit-parseable cron schedule" do
        require "fugit"
        entry = recurring_config[env]["retry_failed_attachments"]
        expect(entry).to be_present, "expected #{env}: block to include retry_failed_attachments"
        expect(entry["class"]).to eq("RetryFailedAttachmentsJob")
        expect(entry["queue"]).to eq("background")
        expect(entry).to have_key("schedule")
        expect(entry).not_to have_key("cron")

        parsed = Fugit.parse(entry["schedule"])
        expect(parsed).to be_a(Fugit::Cron)
        expect(parsed.next_time).to be_present
      end
    end

    it "survives solid_queue's has_key?(:schedule) registration filter in development and production" do
      symbolized = ActiveSupport::ConfigurationFile
        .parse(Rails.root.join("config", "recurring.yml"))
        .deep_symbolize_keys

      %i[development production].each do |env|
        registered = symbolized[env]
          .select { |_id, options| options.is_a?(Hash) && options.key?(:schedule) }
          .values
          .map { |options| options[:class] }

        expect(registered).to include("RetryFailedAttachmentsJob"),
          "expected #{env}: to register RetryFailedAttachmentsJob"
      end
    end
  end
end
