# frozen_string_literal: true

class AddSwayLocaleToLegislationPipelineRuns < ActiveRecord::Migration[8.1]
  def change
    add_reference :legislation_pipeline_runs, :sway_locale, foreign_key: true, index: true, null: true
  end
end
