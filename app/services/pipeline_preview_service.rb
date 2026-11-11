# frozen_string_literal: true

# @lat: [[pipeline-preview-reply-shape#PipelinePreviewService's reply shape]]
# @lat: [[pipeline-preview-service-design#Why DAG_ORDER borrows LegislationPipelineRun's stage order]]
class PipelinePreviewService
  # @lat: [[pipeline-preview-reply-shape#PipelinePreviewService's reply shape]]
  PREVIEW_RESPONSE_KEYS = %w[
    stages_requested
    stages_will_run
    stages_auto_included
    confirmation_required
    confirmation_message
    prereq_violations
  ].freeze

  # @lat: [[pipeline-preview-service-design#Why DAG_ORDER borrows LegislationPipelineRun's stage order]]
  DAG_ORDER = LegislationPipelineRun::ALLOWED_PIPELINE_STAGES

  # @lat: [[pipeline-preview-reply-shape#PipelinePreviewService's reply shape]]
  MISSING_ARTIFACT_TOKENS = {
    "fetch-bills" => "bill_pdf",
    "fetch-law" => "section_index.json",
    "extract-text" => "extracted_text",
    "parse-sections" => "bill_section_references",
    "generate-diffs" => "diff_content",
    "fetch-hearings" => "hearings_json",
    "summarize-bill" => "llm_summary"
  }.freeze

  def self.fetch(stages:, download_missing_assets: true, bills: nil)
    new.fetch(stages: stages, download_missing_assets: download_missing_assets, bills: bills)
  end

  def fetch(stages:, download_missing_assets: true, bills: nil)
    stages_array = Array(stages).compact.map(&:to_s).reject(&:empty?)
    return nil if stages_array.empty?

    unknown = stages_array - DAG_ORDER
    if unknown.any?
      # @lat: [[pipeline-preview-service-design#Why an unknown stage name returns nil rather than an error]]
      SwayLogging.warn(
        "[PipelinePreviewService] unknown stages requested: #{unknown.inspect}"
      )
      return nil
    end

    # @lat: [[pipeline-preview-service-design#One batched query, not one per bill]]
    empty_presence_map = {} #: Hash[String, Hash[String, bool]]
    presence_map = bills.nil? ? empty_presence_map : Pipeline::ArtifactPresence.batch_for(bills: bills)

    will_run = compute_will_run(stages_array, presence_map, download_missing_assets)
    auto_included = will_run - stages_array
    confirmation_required = auto_included.any?
    confirmation_message =
      if confirmation_required
        "Selected stages require: #{auto_included.join(", ")} — these will run too. Continue?"
      end
    prereq_violations = compute_prereq_violations(stages_array, presence_map, download_missing_assets)

    response = {
      "stages_requested" => stages_array,
      "stages_will_run" => will_run,
      "stages_auto_included" => auto_included,
      "confirmation_required" => confirmation_required,
      "confirmation_message" => confirmation_message,
      "prereq_violations" => prereq_violations
    }
    response.slice(*PREVIEW_RESPONSE_KEYS)
  end

  private

  # @lat: [[pipeline-preview-service-design#The fetch-law exception to per-bill presence data]]
  def compute_will_run(stages_array, presence_map, download_missing_assets)
    closure = Pipeline::StageDeps.transitive_closure(stages_array)
    ordered = DAG_ORDER & closure

    if !download_missing_assets
      return DAG_ORDER & stages_array
    end

    return ordered if presence_map.empty?

    operator_set = stages_array.to_set
    ordered.reject do |stage|
      next false if operator_set.include?(stage)
      next false unless per_bill_stage?(stage)

      presence_map.values.all? { |stages_hash| stages_hash[stage] == true }
    end
  end

  # @lat: [[pipeline-preview-service-design#One batched query, not one per bill]]
  def compute_prereq_violations(stages_array, presence_map, download_missing_assets)
    violations = [] #: Array[PipelinePreviewService::prereq_violation]
    return violations if download_missing_assets
    return violations if presence_map.empty?

    operator_set = stages_array.to_set
    stages_array.each do |checked_stage|
      prereqs = Pipeline::StageDeps.transitive_closure([checked_stage]) - [checked_stage]
      prereqs.each do |prereq|
        next if operator_set.include?(prereq)
        next unless per_bill_stage?(prereq)

        bill_count = presence_map.count { |_ext, stages_hash| stages_hash[prereq] != true }
        next if bill_count.zero?

        violations << {
          "stage" => checked_stage,
          "prerequisite" => prereq,
          "missing_artifact" => MISSING_ARTIFACT_TOKENS.fetch(prereq, prereq),
          "bill_count" => bill_count
        }
      end
    end
    violations
  end

  # @lat: [[pipeline-preview-service-design#The fetch-law exception to per-bill presence data]]
  def per_bill_stage?(stage)
    stage != "fetch-law"
  end
end
