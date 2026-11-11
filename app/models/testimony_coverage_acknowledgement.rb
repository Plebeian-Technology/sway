# frozen_string_literal: true

# == Schema Information
#
# Table name: testimony_coverage_acknowledgements
# Database name: primary
#
#  id                          :integer          not null, primary key
#  coverage_digest             :string           not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  acknowledged_by_id          :integer          not null
#  bill_id                     :integer          not null
#  legislation_pipeline_run_id :integer
#
# Indexes
#
#  idx_on_acknowledged_by_id_9c5b8c3023                  (acknowledged_by_id)
#  idx_on_legislation_pipeline_run_id_e73c32c2d5         (legislation_pipeline_run_id)
#  index_testimony_coverage_acknowledgements_on_bill_id  (bill_id)
#  index_testimony_coverage_acks_on_bill_and_digest      (bill_id,coverage_digest) UNIQUE
#
# Foreign Keys
#
#  acknowledged_by_id           (acknowledged_by_id => users.id)
#  bill_id                      (bill_id => bills.id)
#  legislation_pipeline_run_id  (legislation_pipeline_run_id => legislation_pipeline_runs.id)
#
# @lat: [[testimony-coverage-report-invariants#Why acknowledgements are keyed by bill and coverage digest]]
class TestimonyCoverageAcknowledgement < ApplicationRecord
  belongs_to :bill
  belongs_to :acknowledged_by, class_name: "User"
  belongs_to :legislation_pipeline_run, optional: true

  validates :coverage_digest, presence: true
end
