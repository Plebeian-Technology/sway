# frozen_string_literal: true

# @lat: [[org-position-approval-guard-chain#Acknowledging testimony coverage gaps]]
class AcknowledgeTestimonyCoverageService
  def initialize(bill:, actor:, digest:)
    @bill = bill
    @actor = actor
    @digest = digest.to_s
  end

  def call
    report = Testimony::CoverageReport.call(bill: @bill)

    return :run_in_flight if report.state == :running
    return :nothing_left_out unless Testimony::CoverageReport.coverage_gap?(report)
    return :digest_mismatch if @digest != report.digest

    store_acknowledgement(report.digest)
    :acknowledged
  end

  private

  def store_acknowledgement(coverage_digest)
    TestimonyCoverageAcknowledgement.find_or_create_by!(bill: @bill, coverage_digest: coverage_digest) do |ack|
      ack.acknowledged_by = @actor
      ack.legislation_pipeline_run = last_clean_testimony_pipeline_run
    end
  rescue ActiveRecord::RecordNotUnique
    # @lat: [[org-position-approval-guard-chain#Acknowledging testimony coverage gaps]]
  end

  def last_clean_testimony_pipeline_run
    Legislation::PipelineBillLookup.run_bills_for(@bill)
      .where.not("json_extract(stage_results, '$.clean_testimony.status') IS NULL")
      .joins(:legislation_pipeline_run)
      .order("legislation_pipeline_runs.created_at DESC")
      .limit(1)
      .first
      &.legislation_pipeline_run
  end
end
