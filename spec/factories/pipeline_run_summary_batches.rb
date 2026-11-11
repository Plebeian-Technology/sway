# frozen_string_literal: true

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
FactoryBot.define do
  factory :pipeline_run_summary_batch do
    legislation_pipeline_run

    sequence(:batch_id) { |n| "msgbatch_test_#{n}" }
    submitted_at { 1.minute.ago }
    expires_at { 24.hours.from_now }

    trait :expired do
      expires_at { 1.minute.ago }
    end

    trait :without_expiry do
      expires_at { nil }
    end
  end
end
