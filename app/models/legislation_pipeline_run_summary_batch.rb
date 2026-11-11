# == Schema Information
#
# Table name: legislation_pipeline_run_summary_batches
# Database name: primary
#
#  id                          :integer          not null, primary key
#  attempt                     :integer          default(1), not null
#  canceled_count              :integer          default(0), not null
#  errored_count               :integer          default(0), not null
#  expired_count               :integer          default(0), not null
#  expires_at                  :datetime
#  ingested_at                 :datetime
#  item_count                  :integer          default(0), not null
#  model                       :string
#  submitted_at                :datetime
#  succeeded_count             :integer          default(0), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  batch_id                    :string           not null
#  legislation_pipeline_run_id :integer          not null
#
# Indexes
#
#  index_legislation_pipeline_run_summary_batches_on_batch_id     (batch_id) UNIQUE
#  index_legislation_pipeline_run_summary_batches_on_ingested_at  (ingested_at)
#  index_pipeline_run_summary_batches_on_run_id                   (legislation_pipeline_run_id)
#
# Foreign Keys
#
#  legislation_pipeline_run_id  (legislation_pipeline_run_id => legislation_pipeline_runs.id) ON DELETE => cascade
#
# frozen_string_literal: true

require_relative "pipeline_run_summary_batch"

LegislationPipelineRunSummaryBatch = PipelineRunSummaryBatch
