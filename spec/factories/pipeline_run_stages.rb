# frozen_string_literal: true

# Factory for PipelineRunStage. It is wrapped in defined?(PipelineRunStage) so
# that factory_bot's eager load does not crash on a checkout where the model
# has not been created yet.

if defined?(PipelineRunStage)
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
  FactoryBot.define do
    factory :pipeline_run_stage do
      legislation_pipeline_run

      sequence(:stage_name) { |n| "stage_test_#{n}" }
      status { "pending" }
      started_at { nil }
      finished_at { nil }
      error_message { nil }
      completed_bill_external_ids { [] }
      remaining_bill_external_ids { [] }
      output_summary { nil }

      trait :running do
        status { "running" }
        started_at { 1.minute.ago }
        remaining_bill_external_ids { ["bill_1", "bill_2", "bill_3"] }
      end

      trait :succeeded do
        status { "succeeded" }
        started_at { 2.minutes.ago }
        finished_at { 30.seconds.ago }
        completed_bill_external_ids { ["bill_1", "bill_2", "bill_3"] }
        remaining_bill_external_ids { [] }
      end

      trait :failed do
        status { "failed" }
        error_message { "Stage failed: upstream HTTPX timeout" }
        started_at { 2.minutes.ago }
        finished_at { 1.minute.ago }
      end

      trait :skipped do
        status { "skipped" }
      end

      trait :cancelled do
        status { "cancelled" }
      end

      trait :with_extract_text_summary do
        stage_name { "extract-text" }
        output_summary do
          {"pages" => 12, "ocr_used" => false, "tesseract_invocations" => 0, "output_path" => "/tmp/extract_text/test.txt"}
        end
      end
    end
  end
end
