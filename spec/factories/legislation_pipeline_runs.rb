# frozen_string_literal: true

# == Schema Information
#
# Table name: legislation_pipeline_runs
# Database name: primary
#
#  id                      :integer          not null, primary key
#  completed_at            :datetime
#  current_stage           :string
#  download_missing_assets :boolean          default(TRUE), not null
#  error_message           :text
#  idempotency_key         :string           not null
#  origin                  :string           default("fresh"), not null
#  stages                  :text
#  started_at              :datetime
#  status                  :string           default("queued"), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  bill_id                 :integer
#  parent_run_id           :string
#  remote_run_id           :string
#  sway_locale_id          :integer
#
# Indexes
#
#  index_legislation_pipeline_runs_on_bill_id          (bill_id)
#  index_legislation_pipeline_runs_on_idempotency_key  (idempotency_key) UNIQUE
#  index_legislation_pipeline_runs_on_parent_run_id    (parent_run_id)
#  index_legislation_pipeline_runs_on_remote_run_id    (remote_run_id) UNIQUE WHERE remote_run_id IS NOT NULL
#  index_legislation_pipeline_runs_on_status           (status)
#  index_legislation_pipeline_runs_on_sway_locale_id   (sway_locale_id)
#
# Foreign Keys
#
#  bill_id         (bill_id => bills.id)
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
FactoryBot.define do
  factory :legislation_pipeline_run do
    status { "queued" }
    stages { LegislationPipelineRun::ALLOWED_PIPELINE_STAGES }
    remote_run_id { SecureRandom.hex(8) }
    bill { nil }

    trait :running do
      status { "running" }
      current_stage { "fetch-bills" }
      started_at { 1.minute.ago }
    end

    trait :completed do
      status { "completed" }
      started_at { 2.minutes.ago }
      completed_at { 30.seconds.ago }
    end

    trait :failed do
      status { "failed" }
      error_message { "Pipeline failed at stage 'extract-text': upstream HTTPX timeout" }
      started_at { 2.minutes.ago }
      completed_at { 1.minute.ago }
    end

    trait :per_bill do
      bill
    end

    trait :awaiting_summary_batch do
      transient do
        summary_batch_expires_at { 24.hours.from_now }
      end

      status { "awaiting_summary_batch" }
      current_stage { "summarize" }
      started_at { 1.minute.ago }

      after(:create) do |run, evaluator|
        create(
          :pipeline_run_summary_batch,
          legislation_pipeline_run: run,
          expires_at: evaluator.summary_batch_expires_at
        )
      end
    end
  end
end
