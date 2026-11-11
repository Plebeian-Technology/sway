# frozen_string_literal: true

require "rails_helper"

# @lat: [[bills-controller-design#How pipeline_stage_keys_drift_spec.rb checks parity]]
RSpec.describe "BillsController::PIPELINE_STAGE_KEYS / frontend STAGES parity", type: :integration do
  # @lat: [[bills-controller-design#How pipeline_stage_keys_drift_spec.rb checks parity]]
  let(:controls_path) { Rails.root.join("app", "frontend", "components", "admin", "creator", "pipeline-controls", "stages.ts") }
  let(:controls_source) { File.read(controls_path) }

  # @lat: [[bills-controller-design#How pipeline_stage_keys_drift_spec.rb checks parity]]
  def stages_block(source)
    start_idx = source.index("const STAGES: ReadonlyArray")
    raise "STAGES literal not found in pipeline-controls/stages.ts" unless start_idx

    tail = source[start_idx..]
    end_idx = tail.index(/^\];/m)
    raise "STAGES literal closing `];` not found" unless end_idx

    tail[0..end_idx]
  end

  it "every PIPELINE_STAGE_KEY appears in pipeline-controls/stages.ts STAGES" do
    expect(controls_path).to exist

    BillsController::PIPELINE_STAGE_KEYS.each do |key|
      # Match `key: "fetch-bills"`, the object-literal form the STAGES entries
      # use, so the same string appearing elsewhere in the file — in a help link
      # or a comment — does not count as a match.
      pattern = /key:\s*["']#{Regexp.escape(key)}["']/
      expect(controls_source).to match(pattern),
        "PIPELINE_STAGE_KEYS contains #{key.inspect}, but pipeline-controls/stages.ts STAGES has no `key: \"#{key}\"`. " \
        "Add the matching `{ key, label, subtext }` entry to STAGES or remove it from PIPELINE_STAGE_KEYS."
    end
  end

  # @lat: [[bills-controller-design#How pipeline_stage_keys_drift_spec.rb checks parity]]
  it "every pipeline-controls/stages.ts STAGES key appears in PIPELINE_STAGE_KEYS" do
    expect(controls_path).to exist

    block = stages_block(controls_source)
    frontend_keys = block.scan(/key:\s*["']([a-z-]+)["']/).flatten.uniq
    expect(frontend_keys).not_to be_empty,
      "Expected at least one `{ key: \"...\" }` entry in the STAGES literal — regex extraction returned zero matches."

    extra_in_frontend = frontend_keys - BillsController::PIPELINE_STAGE_KEYS
    expect(extra_in_frontend).to be_empty,
      "pipeline-controls/stages.ts STAGES contains #{extra_in_frontend.inspect} " \
      "but PIPELINE_STAGE_KEYS does not. The checkbox would render but the click " \
      "would be filtered out of `pipeline_controls_state` — silent UX loss. " \
      "Either re-add the matching entry to PIPELINE_STAGE_KEYS or remove the " \
      "orphan checkbox from STAGES."
  end
end
