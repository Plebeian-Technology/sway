# frozen_string_literal: true

# @lat: [[campaign-approval-outcomes#ApproveCampaignPositionService outcomes]]
# @lat: [[campaign-approval-guard-chain#Identity is mandatory, with no exempt caller#Why position is not part of the identity]]
# @lat: [[campaign-scope-and-identity#How one campaign is told from another]]
class ApproveCampaignPositionService
  class DraftNotFound < StandardError; end
  private_constant :DraftNotFound

  class RunInFlight < StandardError; end
  private_constant :RunInFlight

  class CoverageNotAcknowledged < StandardError; end
  private_constant :CoverageNotAcknowledged

  class NoTestimony < StandardError; end
  private_constant :NoTestimony

  def initialize(bill:, actor:, name:, support:, summary:, content_hash: nil)
    @bill = bill
    @actor = actor
    @name = name.to_s.strip[0, Campaign::MAX_NAME_CHARS] #: String
    @support_raw = support
    @summary = summary.to_s
    @content_hash = content_hash
  end

  def call
    return :summary_required if @summary.strip.empty?

    support = Campaign.normalize_support(@support_raw)
    return :invalid_stance if support.nil?

    return :identity_required unless asserted_identity?

    return :draft_not_found if draft_missing?
    return :run_in_flight if run_in_flight?
    return :no_testimony if bill_testimony_missing?
    return :coverage_not_acknowledged if coverage_not_acknowledged?

    approve(support)
  rescue DraftNotFound
    :draft_not_found
  rescue RunInFlight
    :run_in_flight
  rescue NoTestimony
    :no_testimony
  rescue CoverageNotAcknowledged
    :coverage_not_acknowledged
  end

  private

  def approve(support)
    ActiveRecord::Base.transaction do
      reconfirm_guards
      outcome = upsert_campaign(support)
      log_decision(outcome)
      outcome
    end
  end

  def asserted_identity?
    @content_hash.present?
  end

  def drafts(provisioning = nil)
    provisioning ||= @bill.bill_llm_provisioning
    artifact = provisioning&.cleaned_testimony
    return [] if artifact.blank?

    artifact["campaign_drafts"] || []
  end

  # @lat: [[campaign-approval-guard-chain#Identity is mandatory, with no exempt caller#Why position is not part of the identity]]
  def draft_by_hash(list)
    return nil if @content_hash.blank?

    list.find { |entry| entry["id"].to_s == @content_hash.to_s }
  end

  def draft_missing?(list = nil)
    draft_by_hash(list || drafts).nil?
  end

  def bill_testimony_missing?(provisioning = nil)
    provisioning ||= @bill.bill_llm_provisioning
    !provisioning&.testimony_present?
  end

  def run_in_flight?(provisioning = nil)
    provisioning ||= @bill.bill_llm_provisioning
    return false if provisioning.nil?

    # @lat: [[campaign-approval-guard-chain#run_in_flight?]]
    provisioning.pending? || provisioning.generating? || LegislationPipelineRun.cleaning_testimony_for(@bill).exists?
  end

  def coverage_not_acknowledged?(provisioning = nil)
    provisioning ||= @bill.bill_llm_provisioning
    return false if provisioning.nil?

    report = Testimony::CoverageReport.call(bill: @bill, provisioning: provisioning)
    Testimony::CoverageReport.coverage_gap?(report) && !report.acknowledged
  end

  # @lat: [[campaign-approval-guard-chain#Nothing to write back]]
  def reconfirm_guards
    provisioning = @bill.bill_llm_provisioning || raise(DraftNotFound)

    provisioning.with_lock do
      raise DraftNotFound if draft_missing?(drafts(provisioning))
      raise RunInFlight if run_in_flight?(provisioning)
      raise NoTestimony if bill_testimony_missing?(provisioning)
      raise CoverageNotAcknowledged if coverage_not_acknowledged?(provisioning)

      provisioning.restore_campaign_draft!(@content_hash)
    end
  end

  # @lat: [[campaign-scope-and-identity#Recording which draft a campaign came from]]
  def upsert_campaign(support)
    entry = draft_by_hash(drafts)
    existing = matched_campaign
    @replaced_draft_hash = existing&.source_campaign_draft_hash

    # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why replacing an earlier decision is reported as success]]
    replacing = existing.present? && @replaced_draft_hash.to_s != @content_hash.to_s

    campaign = existing || Campaign.new(bill: @bill, name: @name.presence)
    campaign.support = support
    campaign.summary = @summary
    campaign.sender_count = entry && entry["sender_count"]
    campaign.letter_count = entry && entry["letter_count"]
    campaign.source_campaign_draft_hash = @content_hash.to_s
    campaign.active = true
    campaign.save!
    replacing ? :approved_replacing_draft : :approved
  end

  def matched_campaign
    return nil if @name.empty?

    Campaign
      .where(bill: @bill)
      .where("LOWER(name) = ?", @name.downcase)
      .order(:id)
      .first
  end

  # @lat: [[campaign-scope-and-identity#Recording which draft a campaign came from]]
  def log_decision(outcome)
    draft_view = Struct.new(:id, :organization_name).new(
      "#{@bill.id}-campaign-#{@content_hash}",
      @name.presence || "Unnamed campaign"
    )
    extra = (outcome == :approved_replacing_draft) ? {replaced_draft_hash: @replaced_draft_hash} : {}
    PipelineActivityLogger.log_org_position_decision!(
      bill: @bill, draft: draft_view, decision: outcome, actor: @actor, extra: extra
    )
  end
end
