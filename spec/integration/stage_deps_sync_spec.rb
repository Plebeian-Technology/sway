# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pipeline::STAGE_DEPS cross-language parity", type: :integration do
  # @lat: [[legislation-pipeline-stage-deps-graph#Why EMPTY_DEPS carries a steep:ignore]]
  before(:all) { Pipeline::StageDeps }

  it "Ruby Pipeline::STAGE_DEPS is deeply frozen" do
    expect(Pipeline::STAGE_DEPS).to be_frozen
    Pipeline::STAGE_DEPS.each_value do |deps|
      expect(deps).to be_frozen
    end
  end

  it "TypeScript StageKey union matches Ruby Pipeline::StageKeys::KEY_TO_SYMBOL.keys" do
    # Make Zeitwerk load app/models/pipeline/stage_keys.rb, so
    # Pipeline::StageKeys::KEY_TO_SYMBOL exists before the code below reaches
    # for it.

    ts_path = Rails.root.join("app", "frontend", "components", "admin", "creator", "pipeline-controls", "stages.ts")
    source = File.read(ts_path)
    union_body = source[/export type StageKey\s*=\s*([^;]+);/m, 1] ||
      raise("stages.ts: 'export type StageKey = …;' union not found — has the file shape changed?")
    ts_keys = union_body.scan(/"([^"]+)"/).flatten.sort
    ruby_keys = Pipeline::StageKeys::KEY_TO_SYMBOL.keys.sort
    expect(ts_keys).to eq(ruby_keys),
      "TS StageKey ↔ Ruby KEY_TO_SYMBOL drift\n  TS:   #{ts_keys.inspect}\n  Ruby: #{ruby_keys.inspect}"
  end

  it "Ruby Pipeline::StageKeys::KEY_TO_SYMBOL.keys matches RBS stage_key literal-union" do
    # The signature file mirrors the app path Zeitwerk uses:
    # sig/models/pipeline/stage_keys.rbs, not sig/pipeline/stage_keys.rbs. That
    # convention follows sig/models/pipeline/stage_deps.rbs.
    rbs_path = Rails.root.join("sig", "models", "pipeline", "stage_keys.rbs")
    source = File.read(rbs_path)
    union_body = source[/type stage_key\s*=\s*([^\n]+(?:\n\s*\|[^\n]+)*)/m, 1] ||
      raise("stage_keys.rbs: 'type stage_key = …' literal-union not found — has the file shape changed?")
    rbs_keys = union_body.scan(/"([^"]+)"/).flatten.sort
    ruby_keys = Pipeline::StageKeys::KEY_TO_SYMBOL.keys.sort
    expect(rbs_keys).to eq(ruby_keys),
      "RBS stage_key ↔ Ruby KEY_TO_SYMBOL drift\n  RBS:  #{rbs_keys.inspect}\n  Ruby: #{ruby_keys.inspect}"
  end

  # @lat: [[pipeline-stage-auto-include-reduced-work#Why the auto-included stage chips are comma-separated with a screen-reader-only comma]]
  # Both mechanisms below are derived from the job here, not restated by hand.
  it "TypeScript REDUCED_WHEN_AUTO_INCLUDED matches the stages the job really reduces" do
    ruby_reduced =
      (RunLegislationPipelineJob::BILL_LEVEL_STAGES + [:fetch_bills])
        .map { |symbol| Pipeline::StageKeys::SYMBOL_TO_KEY.fetch(symbol) }
        .sort

    ts_path = Rails.root.join("app", "frontend", "components", "admin", "creator", "pipeline-controls", "stages.ts")
    source = File.read(ts_path)
    body = source[/export const REDUCED_WHEN_AUTO_INCLUDED[^=]*=\s*\[([^\]]*)\]/m, 1] ||
      raise("stages.ts: 'export const REDUCED_WHEN_AUTO_INCLUDED = [...]' not found — has the file shape changed?")
    ts_reduced = body.scan(/"([^"]+)"/).flatten.sort

    expect(ts_reduced).to eq(ruby_reduced),
      "TS REDUCED_WHEN_AUTO_INCLUDED ↔ job behaviour drift\n" \
      "  TS:   #{ts_reduced.inspect}\n  Ruby: #{ruby_reduced.inspect}"
  end

  # Guards the sentence from the other side. fetch_law is the only stage the
  # job treats the same whether it was chosen or added, and the note in the
  # picker is worded around that being so.
  it "fetch_law is the only stage that does the same work chosen or added" do
    unreduced =
      Pipeline::StageKeys::KEY_TO_SYMBOL.values -
      (RunLegislationPipelineJob::BILL_LEVEL_STAGES + [:fetch_bills])

    expect(unreduced).to eq([:fetch_law])
  end
end
