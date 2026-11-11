# frozen_string_literal: true

module Pipeline
  # @lat: [[legislation-pipeline#Law artifact readiness]]
  module ArtifactPresence
    # @lat: [[legislation-pipeline#Law artifact readiness]]
    def self.present?(stage_key, bill: nil, sway_locale: nil)
      case stage_key
      when "fetch-bills"
        return false if bill.nil?

        # @lat: [[legislation-path-segment-safety#Segment validation]]
        segment = Legislation::Paths.external_id_segment(bill.external_id)
        return false if segment.nil?

        sway_locale_segment = Legislation::Paths.sway_locale_segment(bill.sway_locale&.name)
        return false if sway_locale_segment.nil?

        pdf_glob = Legislation::Paths.bill_pdf_glob(segment, sway_locale: sway_locale_segment)
        ::Bill.exists?(external_id: bill.external_id) && Pathname.glob(pdf_glob).any?
      when "fetch-law"
        locale = sway_locale || bill&.sway_locale
        return false if locale.nil?

        Legislation::Paths.law_section_index_file(sway_locale: locale).exist? &&
          ::LawSection.by_sway_locale(locale).exists?
      when "extract-text"
        return false if bill.nil?

        bill.extracted_text.present?
      when "parse-sections"
        return false if bill.nil?

        # @lat: [[pipeline-artifact-presence-overview#Why parse-sections has a secondary signal]]
        ::BillSectionReference.exists?(bill_id: bill.id) ||
          parse_sections_completed_for?(bill)
      when "generate-diffs"
        return false if bill.nil?

        bill.bill_llm_provisioning&.diff_content.present? || false
      when "fetch-hearings"
        return false if bill.nil?

        # @lat: [[legislation-path-segment-safety#Segment validation]]
        segment = Legislation::Paths.external_id_segment(bill.external_id)
        return false if segment.nil?

        sway_locale_segment = Legislation::Paths.sway_locale_segment(bill.sway_locale&.name)
        return false if sway_locale_segment.nil?

        Legislation::Paths.hearings_file(segment, sway_locale: sway_locale_segment).exist?
      when "clean-testimony"
        return false if bill.nil?

        clean_testimony_present?(bill.bill_llm_provisioning)
      when "summarize-bill"
        return false if bill.nil?

        bill.bill_llm_provisioning&.llm_summary.present? || false
      else
        raise ArgumentError, "Pipeline::ArtifactPresence: unknown stage_key #{stage_key.inspect}"
      end
    end

    # @lat: [[pipeline-artifact-presence-overview#The batched lookup]]
    def self.batch_for(bills:)
      return {} if bills.empty?

      eager = bills.includes(:bill_llm_provisioning).to_a
      ActiveRecord::Associations::Preloader.new(records: eager, associations: :sway_locale).call

      raw_root = Legislation::Paths.bills_raw
      hearings_root = Legislation::Paths.hearings

      candidate_keys = eager.filter_map do |bill|
        segment = Legislation::Paths.external_id_segment(bill.external_id)
        sway_locale_segment = Legislation::Paths.sway_locale_segment(bill.sway_locale&.name)
        [sway_locale_segment, segment] if segment && sway_locale_segment
      end.uniq

      # @lat: [[legislation-pipeline-external-id-ambiguity#Pipeline::ArtifactPresence.batch_for's disk sweeps]]
      if candidate_keys.size <= 10
        pdf_present_keys = Set.new(
          candidate_keys.select do |sway_locale_segment, segment|
            Pathname.glob(Legislation::Paths.bill_pdf_glob(segment, sway_locale: sway_locale_segment)).any?
          end
        )
        hearings_present_keys = Set.new(
          candidate_keys.select do |sway_locale_segment, segment|
            Legislation::Paths.hearings_file(segment, sway_locale: sway_locale_segment).exist?
          end
        )
      else
        locale_segments = candidate_keys.map(&:first).uniq
        pdf_present_keys = Set.new(
          locale_segments.flat_map do |loc_seg|
            Pathname.glob(raw_root.join(loc_seg, "*/*.pdf").to_s)
              .map { |p| [loc_seg, p.dirname.basename.to_s] }
          end
        )
        hearings_present_keys = Set.new(
          locale_segments.flat_map do |loc_seg|
            Pathname.glob(hearings_root.join(loc_seg, "*.json").to_s)
              .map { |p| [loc_seg, p.basename(".json").to_s] }
          end
        )
      end

      bill_ids = eager.map(&:id)
      section_ref_bill_ids = Set.new(
        ::BillSectionReference.where(bill_id: bill_ids).distinct.pluck(:bill_id)
      )

      # @lat: [[pipeline-artifact-presence-overview#Why parse-sections has a secondary signal]]
      eager_ext_ids = eager.map(&:external_id)
      parse_sections_completed_ext_ids = Set.new(
        ::PipelineRunBill
          .where(bill_external_id: eager_ext_ids)
          .where(
            "json_extract(stage_results, '$.parse_sections.status') IN (?, ?)",
            "succeeded", "skipped"
          )
          .distinct
          .pluck(:bill_external_id)
      )

      acc_init = {} #: Hash[String, Hash[String, bool]]

      # @lat: [[legislation-pipeline-external-id-ambiguity#The ambiguous-id set in batch_for]]
      seen = Set.new #: Set[String]
      ambiguous = Set.new #: Set[String]

      eager.each_with_object(acc_init) do |bill, acc|
        ext = bill.external_id
        next if ambiguous.include?(ext)

        if seen.include?(ext)
          Legislation::PipelineBillLookup.warn_ambiguous(ext)
          ambiguous << ext
          acc.delete(ext)
          next
        end
        seen << ext
        # @lat: [[legislation-pipeline-external-id-ambiguity#Pipeline::ArtifactPresence.batch_for's disk sweeps]]
        segment = Legislation::Paths.external_id_segment(ext)
        sway_locale_segment = Legislation::Paths.sway_locale_segment(bill.sway_locale&.name)
        key = (segment.nil? || sway_locale_segment.nil?) ? nil : [sway_locale_segment, segment]
        llm = bill.bill_llm_provisioning
        acc[ext] = {
          "fetch-bills" => !key.nil? && pdf_present_keys.include?(key) && bill.persisted?,
          "extract-text" => bill.extracted_text.present?,
          "parse-sections" =>
            section_ref_bill_ids.include?(bill.id) ||
              parse_sections_completed_ext_ids.include?(ext),
          "generate-diffs" => llm&.diff_content.present? || false,
          "fetch-hearings" => !key.nil? && hearings_present_keys.include?(key),
          "clean-testimony" => clean_testimony_present?(llm),
          "summarize-bill" => llm&.llm_summary.present? || false
        }
      end
    end

    # @lat: [[pipeline-artifact-presence-overview#Cleaned-testimony freshness and letter offsets]]
    def self.clean_testimony_present?(provisioning)
      return false if provisioning.nil?

      cleaned_at = provisioning.cleaned_testimony_at
      return false if cleaned_at.nil?

      fetched_at = provisioning.testimony_fetched_at
      fetched_at.nil? || cleaned_at >= fetched_at
    end
    private_class_method :clean_testimony_present?

    # @lat: [[pipeline-artifact-presence-overview#Why parse-sections has a secondary signal]]
    def self.parse_sections_completed_for?(bill)
      return false if bill.nil?

      ::PipelineRunBill
        .where(bill_external_id: bill.external_id)
        .where(
          "json_extract(stage_results, '$.parse_sections.status') IN (?, ?)",
          "succeeded", "skipped"
        )
        .exists?
    end
  end
end
