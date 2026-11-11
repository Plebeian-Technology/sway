# frozen_string_literal: true

# @lat: [[org-position-approval-guard-chain#Why this class exists separately from the controller]]
# @lat: [[approve-org-position-outcomes#ApproveOrgPositionService outcomes]]
# @lat: [[news-org-position-persistence#Approval of news-sourced draft positions]]
class ApproveOrgPositionService
  # @lat: [[private-individual-guard-regions#What the backstop reads, and what it deliberately does not]]
  MIN_BACKSTOP_NAME_CHARS = 6

  # @lat: [[private-individual-guard-regions#Character bounds, not marker-based]]
  BACKSTOP_HEADER_CHARS = 350

  # @lat: [[private-individual-guard-regions#Character bounds, not marker-based]]
  BACKSTOP_SIGNATURE_CHARS = 150

  # @lat: [[private-individual-guard-regions#Direct organization evidence stands the guard down]]
  ORG_EVIDENCE_WINDOW_CHARS = 120

  class DraftIdentityMismatch < StandardError; end
  private_constant :DraftIdentityMismatch

  class EvidenceRetracted < StandardError; end
  private_constant :EvidenceRetracted

  class NoTestimony < StandardError; end
  private_constant :NoTestimony

  class RunInFlight < StandardError; end
  private_constant :RunInFlight

  # @lat: [[org-position-approval-guard-chain#Why call wraps the whole write chain in one outer transaction]]
  class PrivateIndividualSource < StandardError; end
  private_constant :PrivateIndividualSource

  # @lat: [[org-position-approval-guard-chain#Why call wraps the whole write chain in one outer transaction]]
  class CoverageNotAcknowledged < StandardError; end
  private_constant :CoverageNotAcknowledged

  # @lat: [[org-position-draft-identity-exemption#draft_org_name and draft_token]]
  class ClaimedAffiliationNotFound < StandardError; end
  private_constant :ClaimedAffiliationNotFound

  class OrganizationHasUsers < StandardError; end
  private_constant :OrganizationHasUsers

  # @lat: [[org-position-draft-identity-exemption#draft_org_name and draft_token]]
  def initialize(bill:, actor:, org_name:, support:, summary:, index: nil, draft_org_name: nil, draft_token: nil,
    claimed_affiliation_position: nil, override_private_individual: false)
    @bill = bill
    @actor = actor
    @org_name = org_name.to_s.strip
    @support_raw = support
    @summary = summary.to_s
    @index = index
    @draft_org_name = draft_org_name
    @draft_token = draft_token
    @claimed_affiliation_position = claimed_affiliation_position
    @override_private_individual = ActiveModel::Type::Boolean.new.cast(override_private_individual) || false
    @private_individual_override_used = false
  end

  def call
    return :org_name_required if @org_name.empty?

    # @lat: [[organization-position-removal#A Neutral position carries no testimony]]
    @summary = OrganizationBillPosition::DEFAULT_SUMMARY if neutral_position?

    # @lat: [[org-position-approval-guard-chain#The pre-check / re-check split]]
    return :summary_required if @summary.strip.empty?

    support = OrganizationBillPosition.normalize_support(@support_raw)
    return :invalid_stance if support.nil?

    return :identity_required if @index.present? && !asserted_identity?
    return :draft_index_required if asserted_identity? && @index.blank?

    # @lat: [[org-position-approval-guard-chain#The pre-check / re-check split]]
    return :draft_index_mismatch if draft_index_mismatch?

    return :organization_has_users if matched_organization_has_users?

    # @lat: [[org-position-approval-guard-chain#The pre-check / re-check split]]
    return :evidence_retracted if draft_evidence_retracted?

    # @lat: [[org-position-bill-testimony-check#A missing provisioning row counts as missing testimony]]
    return :no_testimony if bill_testimony_missing?

    # @lat: [[org-position-approval-guard-chain#The pre-check / re-check split]]
    return :run_in_flight if run_in_flight?

    # @lat: [[org-position-approval-guard-chain#Why call wraps the whole write chain in one outer transaction]]
    return :private_individual if draft_names_private_individual? && !@override_private_individual
    return :coverage_not_acknowledged if coverage_not_acknowledged?
    return :claimed_affiliation_not_found if claimed_affiliation_missing?
    ActiveRecord::Base.transaction do
      reconfirm_claimed_affiliation_guards
      organization = find_or_create_organization
      upsert_position(organization, support, ai_summary: approved_ai_summary)
      delete_approved_draft
      log_decision
    end
    :approved
  rescue DraftIdentityMismatch
    # @lat: [[org-position-approval-guard-chain#Why call wraps the whole write chain in one outer transaction]]
    :draft_index_mismatch
  rescue EvidenceRetracted
    :evidence_retracted
  rescue NoTestimony
    :no_testimony
  rescue RunInFlight
    :run_in_flight
  rescue PrivateIndividualSource
    :private_individual
  rescue CoverageNotAcknowledged
    :coverage_not_acknowledged
  rescue ClaimedAffiliationNotFound
    :claimed_affiliation_not_found
  rescue OrganizationHasUsers
    :organization_has_users
  end

  private

  # @lat: [[org-position-draft-identity-exemption#draft_org_name and draft_token]]
  def news_sourced?(drafts = nil)
    return false if @index.blank?

    drafts ||= Array(@bill.bill_llm_provisioning&.draft_org_positions)
    entry = draft_at(drafts)
    return false unless entry.is_a?(::Hash)

    BillLlmProvisioning.draft_news_sourced?(entry)
  end

  def testimony_sourced?(drafts = nil)
    return true if @claimed_affiliation_position.present?
    return false if @index.blank?

    !news_sourced?(drafts)
  end

  def claimed_affiliation_missing?(provisioning = nil)
    return false if @claimed_affiliation_position.blank?
    provisioning ||= @bill.bill_llm_provisioning
    artifact = provisioning&.cleaned_testimony
    return true if artifact.blank?
    letters = artifact["letters"] || [] #: Array[Hash[String, untyped]]
    letters.none? do |letter|
      letter["position"].to_s == @claimed_affiliation_position.to_s &&
        letter["source_kind"] == "person_speaking_for_org"
    end
  end

  def reconfirm_claimed_affiliation_guards
    return if @claimed_affiliation_position.blank?
    provisioning = @bill.bill_llm_provisioning || raise(NoTestimony)
    provisioning.with_lock do
      raise NoTestimony if bill_testimony_missing?(provisioning)
      raise RunInFlight if run_in_flight?(provisioning)
      raise ClaimedAffiliationNotFound if claimed_affiliation_missing?(provisioning)
      guard_private_individual!(provisioning)
      raise CoverageNotAcknowledged if coverage_not_acknowledged?(provisioning)
    end
  end

  def asserted_identity?
    BillLlmProvisioning.draft_identity_asserted?(name: @draft_org_name, token: @draft_token)
  end

  # @lat: [[org-position-index-resolution#draft_index_mismatch?: an unresolved index is a mismatch, not a no-op]]
  def draft_at(drafts)
    idx = draft_index
    return nil if idx.nil? || idx.negative? || idx >= drafts.length

    drafts[idx]
  end

  # @lat: [[org-position-index-resolution#draft_index_mismatch?: an unresolved index is a mismatch, not a no-op]]
  def draft_index
    case @index
    when ::Integer then @index
    when ::String then Integer(@index, 10, exception: false)
    end
  end

  def draft_index_mismatch?(drafts = nil)
    return false if @index.blank?

    drafts ||= Array(@bill.bill_llm_provisioning&.draft_org_positions)
    entry = draft_at(drafts)

    # @lat: [[org-position-index-resolution#draft_index_mismatch?: an unresolved index is a mismatch, not a no-op]]
    return asserted_identity? if entry.nil?

    BillLlmProvisioning.draft_identity_mismatch?(
      entry, name: @draft_org_name, token: @draft_token
    )
  end

  # @lat: [[evidence-retraction#The frontend's IOrgPosition.evidence_retracted_at]]
  # @lat: [[org-position-approval-guard-chain#The pre-check / re-check split]]
  def draft_evidence_retracted?(drafts = nil)
    return false if @index.blank?

    drafts ||= Array(@bill.bill_llm_provisioning&.draft_org_positions)
    entry = draft_at(drafts)

    # @lat: [[org-position-approval-guard-chain#Why draft_evidence_retracted? returns false, not the retraction, for a nil entry]]
    return false if entry.nil?
    return true if BillLlmProvisioning.draft_evidence_retracted?(entry)

    if BillLlmProvisioning.draft_news_sourced?(entry)
      return true unless NewsOrgPositionGroundingService.entry_still_grounded?(entry, bill: @bill)
    end

    false
  end

  # @lat: [[org-position-bill-testimony-check#A missing provisioning row counts as missing testimony]]
  def bill_testimony_missing?(provisioning = nil, drafts = nil)
    drafts ||= provisioning ? Array(provisioning.draft_org_positions) : nil
    return false unless testimony_sourced?(drafts)

    provisioning ||= @bill.bill_llm_provisioning
    !provisioning&.testimony_present?
  end

  # @lat: [[org-position-approval-guard-chain#The pre-check / re-check split]]
  # @lat: [[campaign-approval-guard-chain#run_in_flight?]]
  def run_in_flight?(provisioning = nil, drafts = nil)
    drafts ||= provisioning ? Array(provisioning.draft_org_positions) : nil
    return false if @index.blank? && @claimed_affiliation_position.blank?

    provisioning ||= @bill.bill_llm_provisioning
    return false if provisioning.nil?

    if news_sourced?(drafts)
      provisioning.pending? || provisioning.generating?
    else
      provisioning.pending? || provisioning.generating? || LegislationPipelineRun.cleaning_testimony_for(@bill).exists?
    end
  end

  # @lat: [[private-individual-guard-regions#Private-individual guard regions#What the backstop reads, and what it deliberately does not]]
  def draft_names_private_individual?(provisioning = nil, drafts = nil)
    drafts ||= provisioning ? Array(provisioning.draft_org_positions) : nil
    return false unless testimony_sourced?(drafts)
    return false if @org_name.blank?
    return false if @org_name.strip.length < MIN_BACKSTOP_NAME_CHARS

    pattern = /\b#{Testimony::ExtractedText.phrase_source(@org_name)}\b/i
    provisioning ||= @bill.bill_llm_provisioning
    return false if organization_letter_texts(provisioning).any? { |text| pattern.match?(text) }

    private_individual_letter_texts(provisioning).any? { |text| pattern.match?(text) }
  end

  # @lat: [[private-individual-guard-override#Honoured at both check sites]]
  def guard_private_individual!(provisioning, drafts = nil)
    return unless draft_names_private_individual?(provisioning, drafts)
    raise PrivateIndividualSource unless @override_private_individual

    @private_individual_override_used = true
  end

  def private_individual_letter_texts(provisioning)
    artifact = provisioning&.cleaned_testimony
    return [] if artifact.blank?

    full_text = artifact["text"].to_s
    letters = artifact["letters"] || [] #: Array[Hash[String, untyped]]
    letters.filter_map do |letter|
      next unless letter["source_kind"] == "person_speaking_for_self"

      offset = letter["character_offset"].to_i
      length = letter["characters"].to_i
      full_text[offset, length]
    end.flat_map { |text| authorship_regions(text) }
  end

  # @lat: [[private-individual-guard-regions#Character bounds, not marker-based]]
  def authorship_regions(text)
    return [text] if text.length <= BACKSTOP_HEADER_CHARS + BACKSTOP_SIGNATURE_CHARS

    header = text[0, BACKSTOP_HEADER_CHARS] #: String
    signature = text[-BACKSTOP_SIGNATURE_CHARS, BACKSTOP_SIGNATURE_CHARS] #: String
    [header, signature]
  end

  # @lat: [[private-individual-guard-regions#Direct organization evidence stands the guard down]]
  def organization_letter_texts(provisioning)
    artifact = provisioning&.cleaned_testimony
    return [] if artifact.blank?

    full_text = artifact["text"].to_s
    letters = artifact["letters"] || [] #: Array[Hash[String, untyped]]
    letters.filter_map { |letter|
      next unless %w[named_organization public_body].include?(letter["source_kind"])

      offset = letter["character_offset"].to_i
      length = letter["characters"].to_i
      full_text[offset, length]
    }.flat_map { |text| organization_self_identification_regions(text) }
  end

  # @lat: [[private-individual-guard-regions#Only where the letter identifies itself]]
  def organization_self_identification_regions(text)
    authorship_regions(text) + self_identification_windows(text)
  end

  # @lat: [[private-individual-guard-regions#Only where the letter identifies itself]]
  def self_identification_windows(text)
    patterns = Testimony::SourceKindRules::NAMED_ORGANIZATION_PATTERNS +
      Testimony::SourceKindRules::PUBLIC_BODY_PATTERNS
    patterns.flat_map { |pattern| phrase_windows(text, pattern) }
  end

  # @lat: [[private-individual-guard-regions#Only where the letter identifies itself]]
  def phrase_windows(text, pattern)
    windows = [] #: Array[String]
    position = 0
    while (match = pattern.match(text, position))
      match_begin = match.begin(0) #: Integer
      windows << text[match_begin, match[0].length + ORG_EVIDENCE_WINDOW_CHARS].to_s
      match_end = match.end(0) #: Integer
      position = (match_end > match_begin) ? match_end : match_begin + 1
    end
    windows
  end

  # @lat: [[org-position-approval-guard-chain#Acknowledging testimony coverage gaps]]
  def coverage_not_acknowledged?(provisioning = nil, drafts = nil)
    drafts ||= provisioning ? Array(provisioning.draft_org_positions) : nil
    return false unless testimony_sourced?(drafts)

    provisioning ||= @bill.bill_llm_provisioning
    return false if provisioning.nil?

    report = Testimony::CoverageReport.call(bill: @bill, provisioning: provisioning)
    Testimony::CoverageReport.coverage_gap?(report) && !report.acknowledged
  end

  # @lat: [[organization-position-removal#Renaming an organization changes it everywhere in its locale]]
  def find_or_create_organization
    matched = NewsOrgPositionGroundingService.match_existing_organization(@bill, @org_name)
    raise OrganizationHasUsers if NewsOrgPositionGroundingService.organization_has_users?(matched)

    matched || Organization.create!(name: @org_name, sway_locale: @bill.sway_locale)
  end

  def matched_organization_has_users?
    matched = NewsOrgPositionGroundingService.match_existing_organization(@bill, @org_name)
    NewsOrgPositionGroundingService.organization_has_users?(matched)
  end

  def neutral_position?
    OrganizationBillPosition.neutral_support?(@support_raw)
  end

  # @lat: [[org-position-ai-summary-attribution#approved_ai_summary: three ways the answer is nil]]
  def upsert_position(org, support, ai_summary:)
    position = OrganizationBillPosition.find_or_initialize_by(bill: @bill, organization: org)
    position.support = support
    position.summary = @summary
    position.ai_summary = ai_summary
    position.active = true
    position.save!
  end

  # @lat: [[org-position-ai-summary-attribution#approved_ai_summary: three ways the answer is nil]]
  def approved_ai_summary
    return nil if @index.blank?

    entry = draft_at(Array(@bill.bill_llm_provisioning&.draft_org_positions))
    return nil unless entry.is_a?(::Hash)
    return nil if BillLlmProvisioning.draft_news_sourced?(entry)
    return nil if BillLlmProvisioning.draft_summary_edited?(entry)

    stored = entry["summary"]
    return nil if stored.to_s != @summary

    stored.to_s
  end

  # @lat: [[org-position-approval-guard-chain#The pre-check / re-check split]]
  def delete_approved_draft
    return if @index.blank?

    # @lat: [[org-position-approval-guard-chain#Why a missing provisioning row raises rather than returning inside the lock]]
    provisioning = @bill.bill_llm_provisioning || raise(DraftIdentityMismatch)

    provisioning.with_lock do
      drafts = Array(provisioning.draft_org_positions).dup

      # @lat: [[org-position-approval-guard-chain#The pre-check / re-check split]]
      raise DraftIdentityMismatch if draft_index_mismatch?(drafts)
      raise EvidenceRetracted if draft_evidence_retracted?(drafts)
      raise NoTestimony if bill_testimony_missing?(provisioning, drafts)
      raise RunInFlight if run_in_flight?(provisioning, drafts)
      guard_private_individual!(provisioning, drafts)
      raise CoverageNotAcknowledged if coverage_not_acknowledged?(provisioning, drafts)

      # @lat: [[org-position-approval-guard-chain#Why call wraps the whole write chain in one outer transaction]]
      idx = draft_index || raise(DraftIdentityMismatch)
      drafts.delete_at(idx)
      provisioning.update!(draft_org_positions: drafts)
    end
  end

  # @lat: [[org-position-draft-identity-exemption#draft_org_name and draft_token]]
  def log_decision
    extra = @private_individual_override_used ? {private_individual_override: true} : {}
    PipelineActivityLogger.log_org_position_decision!(
      bill: @bill, draft: Struct.new(:id, :organization_name).new(logged_draft_id, @org_name),
      decision: :approved, actor: @actor, extra: extra
    )
  end

  def logged_draft_id
    if @index.present?
      "#{@bill.id}-#{@index}"
    elsif @claimed_affiliation_position.present?
      "#{@bill.id}-letter-#{@claimed_affiliation_position}"
    end
  end
end
