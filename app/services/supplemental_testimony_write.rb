# frozen_string_literal: true

# @lat: [[supplemental-testimony-write-rule#Why blank never clears]]
class SupplementalTestimonyWrite
  # @lat: [[supplemental-testimony-write-rule#The rule, and why each branch is what it is]]
  def self.attrs(value:, clear:, provisioning:)
    return {supplemental_testimony: nil}.merge(clear_retraction_attrs(provisioning)) if clear

    written = value.to_s.presence
    return {} if written.nil?

    {supplemental_testimony: written}.merge(evidence_retraction_attrs(written, provisioning))
  end

  # @lat: [[evidence-retraction-writers#SupplementalTestimonyWrite.evidence_retraction_attrs]]
  def self.clear_retraction_attrs(provisioning)
    drafts = provisioning.draft_org_positions
    return {} unless drafts.is_a?(::Array) && drafts.any?

    {draft_org_positions: BillLlmProvisioning.drafts_with_evidence_retracted(drafts)}
  end
  private_class_method :clear_retraction_attrs

  # @lat: [[evidence-retraction-writers#SupplementalTestimonyWrite.evidence_retraction_attrs]]
  def self.evidence_retraction_attrs(value, provisioning)
    stored = provisioning.supplemental_testimony
    return {} if stored.blank?
    return {} if value.include?(stored)

    drafts = provisioning.draft_org_positions
    return {} unless drafts.is_a?(::Array) && drafts.any?

    {draft_org_positions: BillLlmProvisioning.drafts_with_evidence_retracted(drafts)}
  end
  private_class_method :evidence_retraction_attrs
end
