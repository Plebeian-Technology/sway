# frozen_string_literal: true

module Testimony
  # @lat: [[testimony-coverage-report-invariants#How CoverageReport computes call-time reach, freshness, and coverage gaps]]
  class CoverageReport
    # @lat: [[testimony-coverage-report-invariants#How CoverageReport computes call-time reach, freshness, and coverage gaps]]
    Result = Data.define(
      :state,
      :total_chars, :reached_chars, :removed_chars, :repair_added_chars, :left_out_chars,
      :total_letters, :reached_letters, :removed_letters, :left_out_letters,
      :individual_letter_count, :model_fallback_letter_count, :repeat_letter_count,
      :attachment_cut_count, :attachment_cut_cap,
      :paste_present, :paste_chars, :paste_share_of_limit, :displaced_letter_count,
      :digest, :acknowledged, :acknowledged_by_email, :acknowledged_at
    )

    class << self
      def call(bill:, provisioning: nil)
        new(bill: bill, provisioning: provisioning).call
      end

      # @lat: [[testimony-coverage-report-invariants#How CoverageReport computes call-time reach, freshness, and coverage gaps]]
      def coverage_gap?(result)
        return true if %i[failed stale].include?(result.state)
        return true if result.state == :never_run && (result.total_chars - result.paste_chars).positive?
        return true if result.left_out_chars.positive?

        (result.left_out_letters || 0).positive?
      end
    end

    # @lat: [[testimony-coverage-report-invariants#How CoverageReport computes call-time reach, freshness, and coverage gaps]]
    def initialize(bill:, provisioning: nil)
      @bill = bill
      @provisioning = provisioning || bill.bill_llm_provisioning
    end

    def call
      Result.new(
        state: state,
        total_chars: total_chars, reached_chars: reached_chars,
        removed_chars: removed_chars, repair_added_chars: repair_added_chars, left_out_chars: left_out_chars,
        total_letters: total_letters, reached_letters: reached_letters,
        removed_letters: removed_letters, left_out_letters: left_out_letters,
        individual_letter_count: individual_letter_count,
        model_fallback_letter_count: model_fallback_letter_count,
        repeat_letter_count: repeat_letter_count,
        attachment_cut_count: attachment_cut_count, attachment_cut_cap: attachment_cut_cap,
        paste_present: paste_present?, paste_chars: paste_chars,
        paste_share_of_limit: paste_share_of_limit, displaced_letter_count: displaced_letter_count,
        digest: digest, acknowledged: acknowledged?,
        acknowledged_by_email: acknowledged_by_email, acknowledged_at: acknowledged_at
      )
    end

    private

    attr_reader :bill, :provisioning

    def state
      return :no_testimony if no_testimony?
      return :running if running?
      return :failed if failed?
      return :stale if stale?
      return :cleaned if fresh_artifact_present?

      :never_run
    end

    def no_testimony?
      raw_text_length.zero? && paste_chars.zero? && !artifact_present?
    end

    # @lat: [[testimony-coverage-report-invariants#How CoverageReport computes call-time reach, freshness, and coverage gaps]]
    def running?
      LegislationPipelineRun.active_for_bill(bill).where(status: "cleaning_testimony").exists?
    end

    # @lat: [[testimony-coverage-report-invariants#How CoverageReport computes call-time reach, freshness, and coverage gaps]]
    def last_clean_testimony_stage_status
      return @last_clean_testimony_stage_status if defined?(@last_clean_testimony_stage_status)

      @last_clean_testimony_stage_status =
        Legislation::PipelineBillLookup.run_bills_for(bill)
          .where.not("json_extract(stage_results, '$.clean_testimony.status') IS NULL")
          .joins(:legislation_pipeline_run)
          .order("legislation_pipeline_runs.created_at DESC")
          .limit(1)
          .pick(Arel.sql("json_extract(stage_results, '$.clean_testimony.status')"))
    end

    def failed?
      !running? && last_clean_testimony_stage_status == "failed"
    end

    def artifact_present?
      artifact.present?
    end

    # @lat: [[testimony-coverage-report-invariants#How CoverageReport computes call-time reach, freshness, and coverage gaps]]
    def fresh_artifact_present?
      artifact_present? && reach.source == :cleaned
    end

    # @lat: [[testimony-coverage-report-invariants#How CoverageReport computes call-time reach, freshness, and coverage gaps]]
    def stale?
      artifact_present? && reach.source == :extracted
    end

    def artifact
      provisioning&.cleaned_testimony
    end

    # @lat: [[rbs-signatures#Why a provably-safe value still needs a guard]]
    def cleaned_counts
      current = artifact
      return {} if current.nil?

      current.fetch("counts", {})
    end

    def letters
      current = artifact
      return [] if current.nil?

      current.fetch("letters", []) #: Array[Hash[String, untyped]]
    end

    def raw_text_length
      provisioning&.extracted_testimony.to_s.length
    end

    # @lat: [[testimony-coverage-report-invariants#How CoverageReport computes call-time reach, freshness, and coverage gaps]]
    def total_chars
      fresh_artifact_present? ? cleaned_counts.fetch("raw_chars", 0).to_i : raw_text_length + paste_chars
    end

    # @lat: [[testimony-coverage-report-invariants#How CoverageReport computes call-time reach, freshness, and coverage gaps]]
    def reach
      @reach ||= BillPositionsPromptBuilder.new(bill, provisioning: provisioning).testimony_reach
    end

    def cleaned_chars
      reach.total_chars
    end

    # @lat: [[testimony-coverage-report-invariants#removed_chars clamps to zero; repair_added_chars is the separate growth field]]
    def removed_chars
      [total_chars - cleaned_chars, 0].max
    end

    def repair_added_chars
      [cleaned_chars - total_chars, 0].max
    end

    def reached_chars
      reach.reached_chars
    end

    def left_out_chars
      cleaned_chars - reached_chars
    end

    def total_letters
      fresh_artifact_present? ? letters.length : nil
    end

    # @lat: [[testimony-coverage-report-invariants#How CoverageReport computes call-time reach, freshness, and coverage gaps]]
    def reached_letters
      return nil unless fresh_artifact_present?

      reach.reached_letters || 0
    end

    def removed_letters
      fresh_artifact_present? ? 0 : nil
    end

    def left_out_letters
      return nil unless fresh_artifact_present?

      total_letters.to_i - reached_letters.to_i
    end

    def individual_letter_count
      return nil unless fresh_artifact_present?

      letters.count { |letter| letter["source_kind"] == "person_speaking_for_self" && letter["excluded"] != true }
    end

    # @lat: [[testimony-coverage-report-invariants#How CoverageReport computes call-time reach, freshness, and coverage gaps]]
    def model_fallback_letter_count
      return nil unless fresh_artifact_present?

      cleaned_counts["source_kind_model_fallbacks"]&.to_i
    end

    # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why a repeat letter is marked, not hidden]]
    # @lat: [[testimony-duplicate-letter-marking#Why the coverage report's letter totals were left alone]]
    def repeat_letter_count
      return nil unless fresh_artifact_present?

      cleaned_counts["repeat_letters"]&.to_i
    end

    # @lat: [[testimony-composition-size-limits#A second, higher cap for name-confirmed testimony#Why the routing proxy is a name match, not the model verdict]]
    def cut_attachment_entries
      raw = provisioning&.testimony_attachments
      return [] unless raw.is_a?(::Array)

      raw.select { |entry| entry.is_a?(::Hash) && entry["error"].to_s.start_with?("extracted text truncated to") }
    end

    def attachment_cut_count
      cut_attachment_entries.length
    end

    # @lat: [[testimony-composition-size-limits#A second, higher cap for name-confirmed testimony#Why the routing proxy is a name match, not the model verdict]]
    def attachment_cut_cap
      caps = cut_attachment_entries.filter_map do |entry|
        entry["error"].to_s[/truncated to (\d+) chars/, 1]&.to_i
      end
      return nil if caps.empty?

      caps.max
    end

    def paste_present?
      provisioning&.supplemental_testimony.present?
    end

    def paste_chars
      paste_present? ? provisioning&.supplemental_testimony.to_s.length : 0
    end

    def paste_share_of_limit
      return nil unless paste_present?

      paste_chars.to_f / BillPositionsPromptBuilder.max_testimony_chars
    end

    # @lat: [[testimony-coverage-report-invariants#How CoverageReport computes call-time reach, freshness, and coverage gaps]]
    def displaced_letter_count
      paste_present? ? left_out_letters : 0
    end

    # @lat: [[testimony-coverage-report-invariants#The acknowledgement digest includes state]]
    def digest
      @digest ||= Digest::SHA256.hexdigest(JSON.generate(digest_fields.transform_keys(&:to_s).sort.to_h))
    end

    def digest_fields
      {
        state: state,
        total_chars: total_chars, reached_chars: reached_chars,
        removed_chars: removed_chars, repair_added_chars: repair_added_chars, left_out_chars: left_out_chars,
        total_letters: total_letters, reached_letters: reached_letters,
        removed_letters: removed_letters, left_out_letters: left_out_letters,
        individual_letter_count: individual_letter_count,
        attachment_cut_count: attachment_cut_count, attachment_cut_cap: attachment_cut_cap,
        paste_present: paste_present?, paste_chars: paste_chars,
        paste_share_of_limit: paste_share_of_limit, displaced_letter_count: displaced_letter_count
      }
    end

    def acknowledgement
      return @acknowledgement if defined?(@acknowledgement)

      @acknowledgement = TestimonyCoverageAcknowledgement.find_by(bill: bill, coverage_digest: digest)
    end

    def acknowledged?
      acknowledgement.present?
    end

    def acknowledged_by_email
      acknowledgement&.acknowledged_by&.email
    end

    def acknowledged_at
      acknowledgement&.created_at
    end
  end
end
