# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pipeline and archive exclusion" do
  # @type self: PipelineArchiveExclusionSpecContext
  let(:locale) { create(:sway_locale) }
  let!(:current_session) do
    create(:legislative_session, sway_locale: locale, active: true,
      start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31))
  end
  let(:prior_session) do
    create(:legislative_session, sway_locale: locale,
      start_date: Date.new(2025, 1, 1), end_date: current_session.start_date)
  end
  let!(:old_bill) do
    create(:bill, sway_locale: locale, legislative_session: prior_session,
      introduced_date_time_utc: Time.zone.local(2025, 6, 1), scheduled_release_date_utc: nil)
  end
  let(:service) { ArchivePreviousSessionBillsService.new(sway_locale: locale) }

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Active pipeline exclusion]]
  it "refuses archiving while the locale has a running pipeline or awaits a summary batch" do
    %w[running awaiting_summary_batch].each do |status|
      run = create(:legislation_pipeline_run, sway_locale: locale, status: status)
      expect { service.call }.to raise_error(StandardError, /pipeline/i)
      expect(old_bill.reload.archived_at).to be_nil
      run.update!(status: "succeeded")
    end
    expect(service.call).to eq(1)
  end

  it "allows archiving while another locale has a running pipeline" do
    create(:legislation_pipeline_run, sway_locale: create(:sway_locale), status: "running")
    expect(service.call).to eq(1)
  end

  it "does no work when the queued run is stopped before lock acquisition completes" do
    run = create(:legislation_pipeline_run, bill: old_bill, sway_locale: locale,
      stages: ["parse-sections"], download_missing_assets: false)
    allow(ParseSectionsService).to receive(:new).and_return(instance_double(ParseSectionsService, call: nil))
    allow(PipelineLocaleLock).to receive(:with_locale).and_wrap_original do |original, *args, **kwargs, &operation|
      original.call(*args, **kwargs) do
        LegislationPipelineRun.find(run.id).mark_cancelled!
        operation.call
      end
    end

    RunLegislationPipelineJob.new.perform(run.id)
    expect(run.reload.status).to eq("cancelled")
    expect(run.pipeline_run_bills).to be_empty
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Executing pipeline exclusion]]
  it "holds exclusion during service execution even after the operator stops the run" do
    run = create(:legislation_pipeline_run, sway_locale: locale,
      stages: ["parse-sections"], download_missing_assets: false)
    create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: old_bill.external_id)
    parser = instance_double(ParseSectionsService)
    allow(ParseSectionsService).to receive(:new).and_return(parser)
    allow(parser).to receive(:call) do
      LegislationPipelineRun.find(run.id).mark_cancelled!
      expect { service.call }.to raise_error(StandardError, /pipeline/i)
      expect(old_bill.reload.archived_at).to be_nil
    end

    RunLegislationPipelineJob.new.perform(run.id)
    expect(run.reload.status).to eq("cancelled")
    expect(service.call).to eq(1)
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Batch readback exclusion]]
  it "holds exclusion while reading summary results for a stopped run" do
    run = create(:legislation_pipeline_run, sway_locale: locale, status: "cancelled")
    create(:pipeline_run_summary_batch, legislation_pipeline_run: run, batch_id: "msgbatch_exclusion")
    allow(Llm::ClaudeBatchService).to receive(:status) do
      expect { service.call }.to raise_error(StandardError, /pipeline/i)
      expect(old_bill.reload.archived_at).to be_nil
      double(processing_status: "in_progress")
    end

    SummaryBatchIngest.call(run: run)
    expect(service.call).to eq(1)
  end
end
