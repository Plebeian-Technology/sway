# == Schema Information
#
# Table name: legislation_pipeline_run_bills
# Database name: primary
#
#  id                          :integer          not null, primary key
#  error_message               :text
#  finished_at                 :datetime
#  sort_order                  :integer          default(0), not null
#  stage_results               :json             not null
#  started_at                  :datetime
#  status                      :string           default("pending"), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  bill_external_id            :string           not null
#  legislation_pipeline_run_id :integer          not null
#
# Indexes
#
#  idx_on_legislation_pipeline_run_id_1cc054cf9b             (legislation_pipeline_run_id)
#  index_legislation_pipeline_run_bills_on_bill_external_id  (bill_external_id)
#  index_prb_on_run_and_bill_external_id                     (legislation_pipeline_run_id,bill_external_id) UNIQUE
#
# Foreign Keys
#
#  legislation_pipeline_run_id  (legislation_pipeline_run_id => legislation_pipeline_runs.id) ON DELETE => cascade
#
# frozen_string_literal: true

require_relative "pipeline_run_bill"

LegislationPipelineRunBill = PipelineRunBill
