require "rails_helper"

RSpec.describe "Pipeline start return state", type: :request do
  let(:admin) { create(:user, :sway_admin) }
  let(:sway_locale) { create(:sway_locale, :baltimore) }
  let(:stages) { %w[fetch-bills extract-text] }
  let(:pipeline_start_params) { {stages: stages, sway_locale_id: sway_locale.id, download_missing_assets: false} }

  before do
    sign_in admin
    allow(PipelinePreviewService).to receive(:fetch).and_return(nil)
  end

  # @lat: [[bill-creator-pipeline-controls-panel#Pipeline actions preserve the working address]]
  it "keeps all-bills query state and selected stages through the redirect and next page" do
    query = {bill_creator_tab: "pipeline", selected_stages: stages, download_missing_assets: "0", activity_level: "error", tags: %w[first second]}
    referer = "http://www.example.com/admin/bill_creator/new?#{query.to_query}"

    post "/bills/run_pipeline", params: pipeline_start_params, headers: {"HTTP_REFERER" => referer}, as: :json

    location = URI.parse(response.location)
    expect(location.path).to eq("/admin/bill_creator/new")
    expect(Rack::Utils.parse_nested_query(location.query)).to include(
      "bill_creator_tab" => "pipeline", "selected_stages" => stages.join(","),
      "download_missing_assets" => "0", "activity_level" => "error", "tags" => %w[first second]
    )
    follow_redirect!
    expect(inertia).to render_component(Pages::BILL_CREATOR)
    expect(inertia).to have_props(selected_stages: stages, download_missing_assets: false)
    expect(inertia.props[:tab_key]).to eq("pipeline")
    expect(LegislationPipelineRun.last&.stages).to eq(stages)
  end

  it "uses the submitted choices when the URL still holds the previous debounced selection" do
    referer = "http://www.example.com/admin/bill_creator/new?tab_key=pipeline&selected_stages[]=fetch-law&stages=fetch-law&download_missing_assets=1"

    post "/bills/run_pipeline", params: pipeline_start_params, headers: {"HTTP_REFERER" => referer}, as: :json

    follow_redirect!
    expect(inertia).to have_props(selected_stages: stages, download_missing_assets: false)
  end

  it "preserves the working selection on a refused run" do
    post "/bills/run_pipeline", params: pipeline_start_params.except(:sway_locale_id), as: :json

    follow_redirect!
    expect(inertia).to have_props(
      selected_stages: stages, download_missing_assets: false,
      errors: {pipeline: "A SwayLocale is required for all-bills pipeline runs."}
    )
  end

  it "keeps single-bill state and a pinned run in its existing query" do
    bill = create(:bill, sway_locale: sway_locale)
    pin = create(:legislation_pipeline_run, status: "succeeded", sway_locale: sway_locale)
    referer = "http://www.example.com/admin/bill_creator/#{bill.id}/pipeline?run_id=#{pin.id}&activity_level=error"

    post "/bills/run_pipeline", params: pipeline_start_params.merge(bill_id: bill.id), headers: {"HTTP_REFERER" => referer}, as: :json

    location = URI.parse(response.location)
    expect(location.path).to eq("/admin/bill_creator/#{bill.id}/pipeline")
    expect(Rack::Utils.parse_nested_query(location.query)).to include("run_id" => pin.id.to_s, "activity_level" => "error")
    follow_redirect!
    expect(inertia).to have_props(selected_stages: stages, download_missing_assets: false)
  end

  it "does not borrow query state from an external referrer" do
    post "/bills/run_pipeline", params: pipeline_start_params,
      headers: {"HTTP_REFERER" => "https://example.net/admin/bill_creator/new?unrelated=value"}, as: :json

    location = URI.parse(response.location)
    expect(location.host).to eq("www.example.com")
    expect(location.query).not_to include("unrelated")
    follow_redirect!
    expect(inertia).to have_props(selected_stages: stages)
  end

  it "preserves an explicit empty selection when the server refuses to enqueue it" do
    post "/bills/run_pipeline", params: pipeline_start_params.merge(stages: []), as: :json

    follow_redirect!
    expect(inertia).to have_props(selected_stages: [])
    expect(LegislationPipelineRun.count).to eq(0)
  end

  it "does not carry query state from a different local page" do
    post "/bills/run_pipeline", params: pipeline_start_params,
      headers: {"HTTP_REFERER" => "http://www.example.com/admin?unrelated=value"}, as: :json

    expect(URI.parse(response.location).query).not_to include("unrelated")
  end

  it "ignores a malformed referrer and returns the submitted choices" do
    post "/bills/run_pipeline", params: pipeline_start_params,
      headers: {"HTTP_REFERER" => "http://www.example.com/admin/bill_creator/new?broken=%ZZ"}, as: :json

    follow_redirect!
    expect(inertia).to have_props(selected_stages: stages, download_missing_assets: false)
  end
end
