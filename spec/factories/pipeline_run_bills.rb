# frozen_string_literal: true

# Factory for PipelineRunBill. It is wrapped in defined?(PipelineRunBill) so
# that factory_bot's eager load does not crash on a checkout where the model
# has not been created yet.

if defined?(PipelineRunBill)
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
  FactoryBot.define do
    factory :pipeline_run_bill do
      legislation_pipeline_run

      sequence(:bill_external_id) { |n| "bill_test_#{n}" }
      status { "pending" }
      sort_order { 0 }
      started_at { nil }
      finished_at { nil }
      error_message { nil }

      trait :running do
        status { "running" }
        started_at { 1.minute.ago }
      end

      trait :succeeded do
        status { "succeeded" }
        started_at { 2.minutes.ago }
        finished_at { 30.seconds.ago }
      end

      trait :failed do
        status { "failed" }
        error_message { "Stage 'extract-text' failed: upstream HTTPX timeout" }
        started_at { 2.minutes.ago }
        finished_at { 1.minute.ago }
      end

      trait :skipped do
        status { "skipped" }
      end
    end
  end
end
