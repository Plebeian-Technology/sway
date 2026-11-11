# frozen_string_literal: true

# @lat: [[bill-creator-artifact-panel-serializers#ResourceCachePanelSerializer]]
module BillCreator
  class ResourceCachePanelSerializer
    TIERS = %w[pdf extracted_text parsed_sections diff summary].freeze #: Array[tier_name]

    # @lat: [[bill-creator-artifact-panel-serializers#ResourceCachePanelSerializer]]
    TIER_TO_STAGE = {
      "extracted_text" => "extract_text",
      "parsed_sections" => "parse_sections",
      "diff" => "generate_diffs"
    }.freeze

    # @lat: [[legislation-path-root-resolution#Where the root comes from]]
    def self.bills_raw_root
      Legislation::Paths.bills_raw
    end

    # @lat: [[bill-creator-artifact-panel-serializers#ResourceCachePanelSerializer#Why a missing tier is left out of the array rather than sent as "not cached"]]
    def self.call(bill)
      return [] if bill.nil?

      latest_run_bill = PipelineRunBill
        .where(bill_external_id: bill.external_id)
        .joins(:legislation_pipeline_run)
        .order("legislation_pipeline_runs.created_at DESC")
        .first

      provisioning = bill.bill_llm_provisioning

      TIERS.map { |tier| build_row(tier, bill, latest_run_bill, provisioning) }.compact
    end

    # @lat: [[bill-creator-artifact-panel-serializers#ResourceCachePanelSerializer]]
    def self.build_row(tier, bill, latest_run_bill, provisioning)
      case tier
      when "pdf"
        # @lat: [[bill-creator-artifact-panel-serializers#ResourceCachePanelSerializer#Why pdf and summary are handled outside TIER_TO_STAGE]]
        pdf_path = pdf_path_for(bill)
        return nil if pdf_path.nil?

        {
          tier: "pdf",
          last_generated_at: Time.zone.at(pdf_path.mtime),
          version_id: nil,
          stale: false,
          source_artifact_id: nil
        } #: row

      when "summary"
        llm_generated_at = provisioning&.llm_generated_at
        return nil if llm_generated_at.nil?

        {
          tier: "summary",
          last_generated_at: llm_generated_at,
          version_id: nil,
          stale: false,
          source_artifact_id: nil
        } #: row
      else
        return nil if latest_run_bill.nil?

        stage_key = TIER_TO_STAGE[tier]
        stage_entry = (latest_run_bill.stage_results || {})[stage_key]
        return nil if stage_entry.nil?

        status = stage_entry.is_a?(Hash) ? stage_entry["status"] : nil
        return nil unless status == "succeeded"

        # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Where a stage's completion time is written]]
        stage_finished_at = stage_entry.is_a?(Hash) ? stage_entry["at"] : nil
        last_generated_at = parse_time(stage_finished_at) ||
          latest_run_bill.finished_at ||
          latest_run_bill.updated_at

        {
          tier: tier,
          last_generated_at: last_generated_at,
          version_id: nil,
          stale: false,
          source_artifact_id: nil
        } #: row
      end
    end

    # @lat: [[bill-creator-artifact-panel-serializers#ResourceCachePanelSerializer]]
    def self.pdf_path_for(bill)
      segment = Legislation::Paths.external_id_segment(bill.external_id)
      return nil if segment.nil?

      sway_locale_segment = Legislation::Paths.sway_locale_segment(bill.sway_locale&.name)
      return nil if sway_locale_segment.nil?

      Pathname.glob(Legislation::Paths.bill_pdf_glob(segment, sway_locale: sway_locale_segment)).first
    end

    def self.parse_time(value)
      return nil if value.blank?
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
