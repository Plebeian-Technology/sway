# == Schema Information
#
# Table name: legislation_pipeline_run_stages
# Database name: primary
#
#  id                          :integer          not null, primary key
#  completed_bill_external_ids :text             default([]), not null
#  error_message               :text
#  finished_at                 :datetime
#  output_summary              :text
#  remaining_bill_external_ids :text             default([]), not null
#  stage_name                  :string           not null
#  started_at                  :datetime
#  status                      :string           default("pending"), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  legislation_pipeline_run_id :integer          not null
#
# Indexes
#
#  idx_on_legislation_pipeline_run_id_c51e3ef6b9  (legislation_pipeline_run_id)
#  index_prs_on_run_and_stage_name                (legislation_pipeline_run_id,stage_name) UNIQUE
#
# Foreign Keys
#
#  legislation_pipeline_run_id  (legislation_pipeline_run_id => legislation_pipeline_runs.id) ON DELETE => cascade
#
# frozen_string_literal: true

require_relative "pipeline_run_stage"

LegislationPipelineRunStage = PipelineRunStage
