# frozen_string_literal: true

require "rails_helper"

RSpec.describe RunLegislationPipelineJob, "Congress discovery failures" do
  let(:congress_locale) { create(:sway_locale, :congress) }
  let(:run) do
    create(:legislation_pipeline_run, sway_locale: congress_locale, stages: %w[fetch-bills fetch-law extract-text])
  end
  let(:congress_discovery_response_status) { 404 }
  let(:response_body) { '{"error":"upstream response details"}' }

  before do
    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.get(%r{\A/v3/bill/\d+\z}) { [congress_discovery_response_status, {"content-type" => "application/json"}, response_body] }
    connection = Faraday.new(url: "https://api.congress.gov/v3") { |f| f.adapter :test, stubs }
    allow(Sway::FaradayStack).to receive(:congress_gov).and_return(connection)
    allow(PipelineRunChannel).to receive(:broadcast_to)
  end

  # @lat: [[legislation-pipeline#Congress API paths and discovery failures]]
  [401, 403, 404, 500].each do |status|
    context "when discovery returns HTTP #{status}" do
      let(:congress_discovery_response_status) { status }

      it "fails discovery before downloading the law corpus or attempting extraction" do
        expect(FetchLawService).not_to receive(:new)

        expect { described_class.new.perform(run.id) }
          .to raise_error(StageError, /fetch_bills: Congress.gov HTTP #{status}/)

        expect(run.reload.status).to eq("failed")
        expect(run.current_stage).to eq("fetch_bills")
        expect(run.pipeline_run_bills.count).to eq(0)
        expect(run.error_message).not_to include("upstream response details")
      end
    end
  end

  context "when Congress successfully returns no bills" do
    let(:congress_discovery_response_status) { 200 }
    let(:response_body) { '{"bills":[]}' }

    it "reports no discovered bills at fetch-bills rather than blaming extraction" do
      expect(FetchLawService).not_to receive(:new)

      expect { described_class.new.perform(run.id) }
        .to raise_error(StageError, /fetch_bills: no bills were discovered for congress-congress-united_states/)

      expect(run.reload.status).to eq("failed")
      expect(run.current_stage).to eq("fetch_bills")
    end
  end
end
