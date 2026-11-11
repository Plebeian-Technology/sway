# frozen_string_literal: true

require "net/http"
require "open3"
require "rails_helper"
require "socket"

# @lat: [[pdf-extraction-mutool-ocr-fallback#Optional remote extraction service]]
module PdfExtractorMicroserviceSpecHelpers
  ARTIFACT_ROOT = LegislationTestArtifacts.root_for("pdf_extractor_microservice_system").freeze
  BILLS_RAW_ROOT = File.join(ARTIFACT_ROOT, "bills", "raw").freeze
  BILLS_TEXT_ROOT = File.join(ARTIFACT_ROOT, "bills", "text").freeze
  TEXT_LAYER_PDF_PATH = Rails.root.join("spec", "fixtures", "files", "mupdf_extractor", "text_layer.pdf").to_s.freeze
  TESSDATA_DIR = File.join(ARTIFACT_ROOT, "tessdata").freeze
  GO_SOURCE_DIR = Rails.root.join("ops", "pdf-extractor").to_s.freeze

  def self.binary_path
    existing = @binary_path
    return existing if existing && File.executable?(existing)

    out_path = Rails.root.join("tmp", "sway-pdf-extractor-#{Process.pid}").to_s
    FileUtils.mkdir_p(File.dirname(out_path))
    _stdout, stderr, status = Open3.capture3("go", "build", "-o", out_path, ".", chdir: GO_SOURCE_DIR)
    unless status.success?
      raise "Failed to build ops/pdf-extractor (exit #{status.exitstatus}): #{stderr}"
    end

    at_exit { FileUtils.rm_f(out_path) }
    @binary_path = out_path
  end

  def self.allocate_ephemeral_port
    server = TCPServer.new("127.0.0.1", 0)
    begin
      Integer(server.addr[1])
    ensure
      server.close
    end
  end

  def self.start_server!(port)
    Process.spawn(
      "env",
      "PORT=#{port}",
      "PDF_EXTRACTOR_PORT=#{port}",
      "PDF_EXTRACTOR_ALLOWED_ROOT=#{ARTIFACT_ROOT}",
      "PDF_EXTRACTOR_CONCURRENCY=1",
      "TESSDATA_PREFIX=#{TESSDATA_DIR}",
      binary_path
    )
  end

  def self.wait_until_healthy!(port, pid)
    uri = URI.parse("http://127.0.0.1:#{port}/up")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10.0

    loop do
      reaped_pid, status = Process.waitpid2(pid, Process::WNOHANG)
      if reaped_pid
        raise "ops/pdf-extractor (pid #{pid}) exited before becoming healthy (status: #{status&.exitstatus})"
      end

      begin
        res = Net::HTTP.get_response(uri)
        return if res.is_a?(Net::HTTPSuccess) && res.body == "ok"
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError, EOFError
        nil
      end

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise "ops/pdf-extractor did not become healthy on port #{port} within 10s"
      end

      sleep 0.05
    end
  end

  def self.stop_process!(pid)
    return if pid.nil?

    begin
      Process.kill("TERM", pid)
    rescue Errno::ESRCH
      nil
    end

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5.0
    loop do
      return if Process.waitpid(pid, Process::WNOHANG)

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        begin
          Process.kill("KILL", pid)
        rescue Errno::ESRCH
          nil
        end
        Process.waitpid(pid)
        return
      end

      sleep 0.05
    end
  rescue Errno::ECHILD
    nil
  end
end

# @lat: [[pdf-extraction-mutool-ocr-fallback#Optional remote extraction service]]
RSpec.describe "Admin pipeline PDF extractor microservice",
  type: :system,
  js: true do
  let(:admin_phone) { "4105550099" }
  let(:sway_locale) do
    SwayLocale.find_by(
      city: "baltimore",
      state: "MD",
      country: "United States"
    ) ||
      create(
        :sway_locale,
        city: "baltimore",
        state: "MD",
        country: "United States"
      )
  end
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:sway_admin_user) do
    create(:user, :registered, phone: admin_phone)
  end
  let(:bill) do
    create(
      :bill,
      external_id: "26-0701",
      sway_locale: sway_locale,
      legislator: legislator,
      extracted_text: nil
    )
  end

  around do |example|
    previous_admin_phones = User::ADMIN_PHONES.dup
    pid = nil

    begin
      FileUtils.rm_rf(PdfExtractorMicroserviceSpecHelpers::ARTIFACT_ROOT)
      FileUtils.mkdir_p(PdfExtractorMicroserviceSpecHelpers::BILLS_RAW_ROOT)
      FileUtils.mkdir_p(PdfExtractorMicroserviceSpecHelpers::BILLS_TEXT_ROOT)
      FileUtils.mkdir_p(PdfExtractorMicroserviceSpecHelpers::TESSDATA_DIR)
      FileUtils.touch(File.join(PdfExtractorMicroserviceSpecHelpers::TESSDATA_DIR, "eng.traineddata"))

      LiveLlmGate.apply_http_policy!
      port = PdfExtractorMicroserviceSpecHelpers.allocate_ephemeral_port
      pid = PdfExtractorMicroserviceSpecHelpers.start_server!(port)
      PdfExtractorMicroserviceSpecHelpers.wait_until_healthy!(port, pid)

      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, [admin_phone])

      with_app_config(
        :legislation,
        legislation_root: PdfExtractorMicroserviceSpecHelpers::ARTIFACT_ROOT,
        legislation_bills_raw_root: PdfExtractorMicroserviceSpecHelpers::BILLS_RAW_ROOT,
        legislation_bills_text_root: PdfExtractorMicroserviceSpecHelpers::BILLS_TEXT_ROOT,
        tessdata_prefix: PdfExtractorMicroserviceSpecHelpers::TESSDATA_DIR,
        pdf_extractor_url: "http://127.0.0.1:#{port}"
      ) do
        example.run
      end
    ensure
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, previous_admin_phones)
      PdfExtractorMicroserviceSpecHelpers.stop_process!(pid)
      FileUtils.rm_rf(PdfExtractorMicroserviceSpecHelpers::ARTIFACT_ROOT)
      LiveLlmGate.apply_http_policy!
    end
  end

  before do
    create(:user_legislator, user: sway_admin_user, legislator: legislator)
    allow(RunLegislationPipelineJob).to receive(:perform_later) do |run_id, **kwargs|
      RunLegislationPipelineJob.perform_now(run_id, **kwargs)
    rescue StageError
      nil
    end
  end

  # @lat: [[testing-the-toolchain#One example lets the real converter run]]
  it "extracts native PDF text through the live Go microservice when triggered from the browser UI" do
    raw_dir = Legislation::Paths.bill_artifact_dir(bill.external_id, sway_locale: sway_locale.name)
    FileUtils.mkdir_p(raw_dir)
    FileUtils.cp(
      PdfExtractorMicroserviceSpecHelpers::TEXT_LAYER_PDF_PATH,
      raw_dir.join("#{bill.external_id}_bill.pdf")
    )

    expect(Sway::Subprocess).not_to receive(:capture3)

    sign_in_as(sway_admin_user)
    visit "/admin/bill_creator/#{bill.id}/pipeline?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    expect(page).to have_css("[data-testid='clear-all-stages']:not([disabled])", wait: 10)
    find("[data-testid='clear-all-stages']").click
    expect(page).to have_css("[data-testid='checkbox-stage-extract-text'][data-state='unchecked']")

    find("[data-testid='checkbox-stage-extract-text']").click
    expect(page).to have_css("[data-testid='checkbox-stage-extract-text'][data-state='checked']")

    expect(page).to have_css("[data-testid='checkbox-download-missing-assets']:not([disabled])")
    find("[data-testid='checkbox-download-missing-assets']").click
    expect(page).to have_css("[data-testid='checkbox-download-missing-assets'][data-state='unchecked']")

    expect(page).to have_current_path(/download_missing_assets=0/, wait: 10)
    wait_until_loaded

    before_count = LegislationPipelineRun.count
    find("[data-testid='btn-run-pipeline']").click
    wait_until { LegislationPipelineRun.count == before_count + 1 }

    expect(page).to have_css("[data-testid='pipeline-succeeded-alert']", text: "Run succeeded", wait: 10)

    run = LegislationPipelineRun.order(:id).last!
    expect(run.status).to eq("succeeded")
    expect(run.stages).to eq(["extract-text"])
    expect(run.download_missing_assets).to be(false)

    extracted = bill.reload.extracted_text.to_s
    expect(extracted).to include("marker SWAY TEXT LAYER FIXTURE 5FLI9")

    text_artifact = Legislation::Paths.bill_text_file(bill.external_id, sway_locale: sway_locale.name)
    expect(File.exist?(text_artifact)).to be(true)
    expect(File.read(text_artifact)).to include("marker SWAY TEXT LAYER FIXTURE 5FLI9")
  end

  # @lat: [[pdf-extraction-mutool-ocr-fallback#Optional remote extraction service]]
  it "records a failed run and surfaces the failure in the browser UI when the Go microservice rejects a corrupt PDF" do
    raw_dir = Legislation::Paths.bill_artifact_dir(bill.external_id, sway_locale: sway_locale.name)
    FileUtils.mkdir_p(raw_dir)
    File.write(raw_dir.join("#{bill.external_id}_bill.pdf"), "not a valid pdf file content")

    expect(Sway::Subprocess).not_to receive(:capture3)

    sign_in_as(sway_admin_user)
    visit "/admin/bill_creator/#{bill.id}/pipeline?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    expect(page).to have_css("[data-testid='clear-all-stages']:not([disabled])", wait: 10)
    find("[data-testid='clear-all-stages']").click
    expect(page).to have_css("[data-testid='checkbox-stage-extract-text'][data-state='unchecked']")

    find("[data-testid='checkbox-stage-extract-text']").click
    expect(page).to have_css("[data-testid='checkbox-stage-extract-text'][data-state='checked']")

    expect(page).to have_css("[data-testid='checkbox-download-missing-assets']:not([disabled])")
    find("[data-testid='checkbox-download-missing-assets']").click
    expect(page).to have_css("[data-testid='checkbox-download-missing-assets'][data-state='unchecked']")

    expect(page).to have_current_path(/download_missing_assets=0/, wait: 10)
    wait_until_loaded

    before_count = LegislationPipelineRun.count
    find("[data-testid='btn-run-pipeline']").click
    wait_until { LegislationPipelineRun.count == before_count + 1 }

    expect(page).to have_css("[data-testid='pipeline-error-alert']", text: "Pipeline failed", wait: 10)
    expect(page).to have_css("[data-testid='pipeline-cached-stages']", text: "extract_text", wait: 10)
    expect(page).to have_css("[data-testid='pipeline-cached-stages']", text: "failed", wait: 10)

    run = LegislationPipelineRun.order(:id).last!
    expect(run.status).to eq("failed")

    bill_run = run.pipeline_run_bills.first!
    expect(bill_run.status).to eq("failed")
    expect(bill_run.error_message).to include("extract_text: remote pdf extractor failed")
    expect(bill_run.stage_results.dig("extract_text", "status")).to eq("failed")
    expect(bill_run.stage_results.dig("extract_text", "error")).to include("extract_text: remote pdf extractor failed")
  end
end
