require "rails_helper"

# @lat: [[bills-controller-design#What bills_controller_pipeline_preview_spec.rb covers]]
RSpec.describe BillsController, type: :controller do
  include_context "SessionDouble"

  before do
    admin = create(:user, :sway_admin)
    sign_in(admin)
  end

  let(:locked_preview) do
    {
      "stages_requested" => ["parse-sections"],
      "stages_will_run" => ["fetch-bills", "fetch-law", "extract-text", "parse-sections"],
      "stages_auto_included" => ["fetch-bills", "fetch-law", "extract-text"],
      "confirmation_required" => true,
      "confirmation_message" =>
        "Selected stages require: fetch-bills, fetch-law, extract-text — these will run too. Continue?"
    }
  end

  def inertia_props_hash
    inertia&.props&.to_h&.transform_keys(&:to_s) || {}
  end

  describe "GET #new — pipeline_preview Inertia prop" do
    it "passes pipeline_preview when stages query param is present" do
      # @lat: [[bills-controller-design#What bills_controller_pipeline_preview_spec.rb covers]]
      expect(PipelinePreviewService).to receive(:fetch).with(
        hash_including(stages: ["parse-sections"])
      ).and_return(locked_preview)

      get :new, params: {stages: "parse-sections"}

      props = inertia_props_hash
      expect(props["pipeline_preview"]).to eq(locked_preview)
    end

    it "passes pipeline_preview as nil when PipelinePreviewService returns nil (unknown stage requested)" do
      expect(PipelinePreviewService).to receive(:fetch).and_return(nil)
      get :new, params: {stages: "parse-sections"}
      props = inertia_props_hash
      expect(props["pipeline_preview"]).to be_nil
    end

    it "passes pipeline_preview as nil when no stages query param is present" do
      expect(PipelinePreviewService).not_to receive(:fetch)
      get :new
      props = inertia_props_hash
      expect(props["pipeline_preview"]).to be_nil
    end

    it "splits comma-separated stages into the stages array passed to PipelinePreviewService" do
      expect(PipelinePreviewService).to receive(:fetch).with(
        hash_including(stages: ["parse-sections", "generate-diffs"])
      ).and_return(locked_preview)
      get :new, params: {stages: "parse-sections,generate-diffs"}
    end

    it "accepts an array stages param without flattening" do
      expect(PipelinePreviewService).to receive(:fetch).with(
        hash_including(stages: ["parse-sections", "generate-diffs"])
      ).and_return(locked_preview)
      get :new, params: {stages: ["parse-sections", "generate-diffs"]}
    end
  end

  describe "GET #edit — pipeline_preview Inertia prop (single-bill scope)" do
    let(:bill) { create(:bill) }

    it "calls PipelinePreviewService.fetch with stages when stages query param is present" do
      # @lat: [[bills-controller-design#What bills_controller_pipeline_preview_spec.rb covers]]
      expect(PipelinePreviewService).to receive(:fetch).with(
        hash_including(stages: ["parse-sections"])
      ).and_return(locked_preview)

      get :edit, params: {id: bill.id, stages: "parse-sections"}

      props = inertia_props_hash
      expect(props["pipeline_preview"]).to eq(locked_preview)
    end

    it "passes pipeline_preview as nil when no stages query param is present" do
      expect(PipelinePreviewService).not_to receive(:fetch)
      get :edit, params: {id: bill.id}
      props = inertia_props_hash
      expect(props["pipeline_preview"]).to be_nil
    end

    it "preserves the verify_is_sway_admin gate on #edit" do
      controller_source = Rails.root.join("app", "controllers", "bills_controller.rb").read
      expect(controller_source).to match(/before_action :verify_is_sway_admin/)
    end
  end
end
