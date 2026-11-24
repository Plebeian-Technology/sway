# frozen_string_literal: true

# @lat: [[bill-creator-positions-tab#Why testimony admin write controllers omit an else branch on service outcomes]]
class CampaignsController < ApplicationController
  before_action :verify_is_sway_admin
  before_action :set_bill

  def create
    permitted = params.permit(:name, :support, :summary, :content_hash)

    case ApproveCampaignPositionService.new(
      bill: @bill, actor: current_user,
      name: permitted[:name].to_s, support: permitted[:support], summary: permitted[:summary].to_s,
      content_hash: permitted[:content_hash]
    ).call
    when :summary_required
      refuse_campaign_write("A summary is required")
    when :invalid_stance
      refuse_campaign_write("Invalid stance (expected support|oppose|neutral)")
    when :identity_required
      refuse_campaign_write("A campaign was named with no draft identity to check it against")
    when :draft_not_found
      refuse_campaign_write("This campaign draft has changed since the page loaded — reload and try again")
    when :run_in_flight
      refuse_campaign_write("A clean-testimony run is in progress on this bill — wait for it to finish")
    when :no_testimony
      refuse_campaign_write("This bill's testimony is no longer present — nothing to approve a campaign position from")
    when :coverage_not_acknowledged
      refuse_campaign_write("Acknowledge the missing testimony before approving a campaign position")
    when :approved
      answer_campaign_write("Approved a campaign position on #{@bill.external_id}.")
    when :approved_replacing_draft
      # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why replacing an earlier decision is reported as success]]
      answer_campaign_write("Approved a campaign position on #{@bill.external_id}, replacing an earlier decision " \
        "approved for this campaign name from a different draft.")
    end
  end

  # @lat: [[campaign-draft-rejection#The problem: a campaign draft has no row]]
  def reject_draft
    apply_draft_decision(:rejected)
  end

  # @lat: [[campaign-draft-rejection#The problem: a campaign draft has no row]]
  def restore_draft
    apply_draft_decision(:restored)
  end

  # @lat: [[campaign-draft-rejection#Releasing drafts to individual letters]]
  def mark_individual_draft
    apply_draft_decision(:marked_individual)
  end

  # @lat: [[campaign-organization-link#Why this is a second approval and not part of the first]]
  def link_organization
    permitted = params.permit(:id, :decision, :organization_id, :organization_name)
    campaign = Campaign.find_by(id: permitted[:id])

    if campaign.nil?
      return redirect_to(positions_bill_creator_path(@bill),
        inertia: {errors: {campaign_organization: "That campaign no longer exists — reload and try again"}})
    end

    case LinkCampaignOrganizationService.new(
      bill: @bill, campaign: campaign, actor: current_user,
      decision: permitted[:decision].to_s,
      organization_id: permitted[:organization_id],
      organization_name: permitted[:organization_name]
    ).call
    when :campaign_not_on_bill
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {campaign_organization: "That campaign belongs to a different bill"}}
    when :invalid_decision
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {campaign_organization: "Invalid decision (expected linked|none|undetermined)"}}
    when :organization_required
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {campaign_organization: "Choose an organization, or record that there is none"}}
    when :organization_name_too_long
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {campaign_organization: "Organization name must be #{Campaign::MAX_NAME_CHARS} characters or fewer"}}
    when :organization_not_found
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {campaign_organization: "That organization no longer exists — reload and try again"}}
    when :organization_wrong_locale
      redirect_to positions_bill_creator_path(@bill),
        inertia: {errors: {campaign_organization: "That organization belongs to a different locale than this bill"}}
    when :linked
      flash[:notice] = "Recorded the organization behind this campaign on #{@bill.external_id}."
      redirect_to positions_bill_creator_path(@bill)
    when :recorded_no_organization
      flash[:notice] = "Recorded that no organization is behind this campaign on #{@bill.external_id}."
      redirect_to positions_bill_creator_path(@bill)
    when :recorded_undetermined
      flash[:notice] = "Recorded this campaign's organization as not determinable yet on #{@bill.external_id}."
      redirect_to positions_bill_creator_path(@bill)
    end
  end

  private

  # @lat: [[campaign-draft-rejection#Why the key is a content hash]]
  def apply_draft_decision(decision)
    content_hash = params.permit(:content_hash)[:content_hash].to_s.strip
    provisioning = @bill.bill_llm_provisioning

    return refuse_campaign_write("A campaign draft was named with no identity to check it against") if content_hash.empty?

    if provisioning.nil?
      return refuse_campaign_write("This campaign draft has changed since the page loaded — reload and try again")
    end

    changed =
      case decision
      when :rejected
        provisioning.reject_campaign_draft!(content_hash)
      when :marked_individual
        provisioning.mark_campaign_draft_individual!(content_hash)
      else
        provisioning.restore_campaign_draft!(content_hash)
      end

    log_draft_decision(decision, content_hash) if changed

    answer_campaign_write(
      case decision
      when :rejected
        "Rejected a campaign draft on #{@bill.external_id}."
      when :marked_individual
        "Marked a campaign draft as individual letters on #{@bill.external_id}."
      else
        "Restored a campaign draft on #{@bill.external_id}."
      end
    )
  end

  # @lat: [[mobile-bill-creator#Sections#The campaign drafts section#Answering campaign writes in JSON]]
  def answer_campaign_write(notice)
    respond_after_write(positions_bill_creator_path(@bill), notice: notice, json: {notice: notice})
  end

  def refuse_campaign_write(reason)
    respond_after_write(positions_bill_creator_path(@bill), errors: {campaign_position: reason})
  end

  # @lat: [[campaign-draft-rejection#The activity log]]
  def log_draft_decision(decision, content_hash)
    draft_view = Struct.new(:id, :organization_name).new(
      "#{@bill.id}-campaign-#{content_hash}",
      "Campaign draft"
    )
    PipelineActivityLogger.log_org_position_decision!(
      bill: @bill, draft: draft_view, decision: decision, actor: current_user
    )
  end

  def set_bill
    @bill = Bill.find(params[:bill_id])
  end
end
