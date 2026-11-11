# frozen_string_literal: true

module Legislation
  # @lat: [[legislation-pipeline-external-id-ambiguity#Legislation::PipelineBillLookup: the shared implementation]]
  module PipelineBillLookup
    def self.find(external_id, sway_locale_id: nil)
      matches = scope_for([external_id], sway_locale_id).limit(2).to_a
      return matches.first if matches.size == 1
      return nil if matches.empty?

      warn_ambiguous(external_id)
      nil
    end

    # @lat: [[legislation-pipeline-external-id-ambiguity#Legislation::PipelineBillLookup: the shared implementation]]
    def self.title_map(external_ids, sway_locale_id: nil)
      return {} if external_ids.empty?

      scope_for(external_ids, sway_locale_id)
        .pluck(:external_id, :title)
        .group_by(&:first)
        .each_with_object({}) do |(external_id, rows), map|
          if rows.size > 1
            warn_ambiguous(external_id)
            next
          end

          map[external_id] = rows.first.last
        end
    end

    # @lat: [[legislation-pipeline-external-id-ambiguity#Legislation::PipelineBillLookup: the shared implementation]]
    def self.run_bills_for(bill)
      runs = ::LegislationPipelineRun.where(bill_id: bill.id)
      runs = runs.or(::LegislationPipelineRun.where(bill_id: nil, sway_locale_id: bill.sway_locale_id))
      runs = runs.or(::LegislationPipelineRun.where(bill_id: nil, sway_locale_id: nil)) if unique_external_id?(bill)

      ::PipelineRunBill.where(bill_external_id: bill.external_id, legislation_pipeline_run: runs)
    end

    def self.unique_external_id?(bill)
      unique = ::Bill.where(external_id: bill.external_id).limit(2).count == 1
      warn_ambiguous(bill.external_id) unless unique
      unique
    end
    private_class_method :unique_external_id?

    def self.scope_for(external_ids, sway_locale_id)
      scope = ::Bill.where(external_id: external_ids)
      sway_locale_id.nil? ? scope : scope.where(sway_locale_id: sway_locale_id)
    end
    private_class_method :scope_for

    # @lat: [[legislation-pipeline-external-id-ambiguity#Legislation::PipelineBillLookup: the shared implementation]]
    def self.warn_ambiguous(external_id)
      SwayLogging.warn(
        "[Legislation::PipelineBillLookup] external_id #{external_id.to_s[0, 120].inspect} matches " \
        "bills in more than one sway_locale; refusing to guess. Artifact paths are keyed on " \
        "external_id alone, so neither bill can be processed until the collision is resolved."
      )
    end
  end
end
