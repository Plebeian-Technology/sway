# frozen_string_literal: true

# @lat: [[bill-draft-org-positions-controller#Why this endpoint's admin guard is tested with a non-real bill id, and why the message says "look at the list", not "reload"]]
class BillDraftOrgPositionsController < ApplicationController
  before_action :verify_is_sway_admin

  # @lat: [[bill-draft-org-positions-controller#The composite id]]
  def update
    bill_id, index = parse_composite_id(params[:id])
    # @lat: [[bill-draft-org-positions-controller#Why a malformed id is a 422, not a 404]]
    if bill_id.nil? || index.nil?
      return render(
        json: {error: "malformed_composite_id", message: "Expected '<bill_id>-<index>' (positive integers)"},
        status: :unprocessable_content
      )
    end
    bill = Bill.find(bill_id)
    provisioning = bill.bill_llm_provisioning
    if provisioning.nil?
      return render(
        json: {error: "no_provisioning_row", message: "Bill has no bill_llm_provisioning"},
        status: :unprocessable_content
      )
    end

    # @lat: [[bill-draft-org-positions-controller#Reject is idempotent; edit is not]]
    rejecting = ActiveModel::Type::Boolean.new.cast(params[:rejected])

    # @lat: [[bill-draft-org-positions-controller#Why an edit naming no field is refused]]
    if !rejecting && edit_params.to_h.empty?
      return render(
        json: {
          error: "no_change",
          message: "Send rejected=true, or at least one of org_name/stance/summary"
        },
        status: :unprocessable_content
      )
    end

    # @lat: [[draft-field-validation#DRAFT_POSITIONS: the three words a draft's stance may hold]]
    support_val = edit_params[:support] || edit_params[:stance]
    if !rejecting && (edit_params.key?(:support) || edit_params.key?(:stance)) &&
        !BillLlmProvisioning.draft_support_valid?(support_val)
      return render(
        json: {
          error: "invalid_stance",
          message: "support must be one of: #{BillLlmProvisioning::DRAFT_POSITIONS.join(", ")}"
        },
        status: :unprocessable_content
      )
    end

    # @lat: [[draft-field-validation#DRAFT_TEXT_MAX_CHARS: the longest an org name and a summary may be]]
    if !rejecting
      over_long = edit_params.to_h.keys.find { |field| BillLlmProvisioning.draft_text_too_long?(field, edit_params[field]) }
      if over_long
        return render(
          json: {
            error: "value_too_long",
            message: "#{over_long} must be #{BillLlmProvisioning::DRAFT_TEXT_MAX_CHARS.fetch(over_long)} characters or fewer"
          },
          status: :unprocessable_content
        )
      end
    end

    outcome = apply_draft_decision(provisioning, index, rejecting)

    case outcome[:status]
    when :already_removed
      if rejecting
        return redirect_to(
          positions_bill_creator_path(id: bill.id),
          notice: "Draft already removed."
        )
      end
      return render(
        json: {error: "draft_not_found", message: "No draft org position at index #{index.inspect}"},
        status: :not_found
      )
    when :identity_mismatch
      return redirect_to(
        positions_bill_creator_path(id: bill.id),
        inertia: {errors: {org_position: DraftOrgPositionRefusals::LIST_CHANGED}}
      )
    when :identity_required
      # @lat: [[bill-draft-org-positions-controller#Why :identity_required is its own outcome, not :identity_mismatch]]
      return render(
        json: {
          error: "identity_required",
          message: "Send draft_token (preferred) or draft_org_name naming the draft at this index"
        },
        status: :unprocessable_content
      )
    end

    entry = outcome.fetch(:entry)
    decision = outcome.fetch(:decision)

    # @lat: [[bill-draft-org-positions-controller#The activity-log Struct stand-in]]
    draft_view = Struct.new(:id, :organization_name).new(
      params[:id].to_s,
      (entry["org_name"] || "unknown").to_s
    )
    PipelineActivityLogger.log_org_position_decision!(
      bill: bill,
      draft: draft_view,
      decision: decision,
      actor: current_user
    )

    # @lat: [[bill-draft-org-positions-controller#Why the success notice names the bill and organization]]
    org_label = (entry["org_name"] || "draft").to_s
    notice =
      case decision
      when :rejected
        "Rejected #{org_label} on #{bill.external_id}."
      when :edited
        "Updated #{org_label} on #{bill.external_id}."
      else
        "Draft updated"
      end
    redirect_to positions_bill_creator_path(id: bill.id), notice: notice
  end

  private

  # @lat: [[bill-draft-org-positions-controller#Locking in apply_draft_decision]]
  def apply_draft_decision(provisioning, index, rejecting)
    provisioning.with_lock do
      drafts = Array(provisioning.draft_org_positions).dup
      # @type var drafts: Array[untyped]

      # @lat: [[bill-draft-org-positions-controller#Why identity is checked before bounds]]
      unless BillLlmProvisioning.draft_identity_asserted?(
        name: params[:draft_org_name], token: params[:draft_token]
      )
        next {status: :identity_required}
      end

      # @lat: [[bill-draft-org-positions-controller#Why this endpoint's admin guard is tested with a non-real bill id, and why the message says "look at the list", not "reload"]]
      if index < 0 || index >= drafts.length
        # @lat: [[bill-draft-org-positions-controller#Two different answers for an out-of-range index]]
        next {status: draft_named_elsewhere?(drafts) ? :identity_mismatch : :already_removed}
      end

      raw_entry = drafts[index]

      # @lat: [[bill-draft-org-positions-controller#Why both branches re-check identity against the entry at the index]]
      next {status: :identity_mismatch} if BillLlmProvisioning.draft_identity_mismatch?(
        raw_entry, name: params[:draft_org_name], token: params[:draft_token]
      )

      entry = raw_entry.is_a?(Hash) ? raw_entry.dup : {}
      # @type var entry: Hash[String, untyped]

      # @lat: [[bill-draft-org-positions-controller#Why decision is assigned from the if/else's value]]
      decision =
        if rejecting
          # @lat: [[bill-draft-org-positions-controller#Why reject deletes the entry instead of flagging it]]
          drafts.delete_at(index)
          :rejected
        else
          # @lat: [[bill-draft-org-positions-controller#Why edit_params excludes :rejected]]
          # @lat: [[internal-draft-marks#DRAFT_SUMMARY_EDITED_KEY]]
          previous_summary = entry["summary"]
          updates = edit_params.to_h
          if updates.key?("support")
            updates["stance"] = updates["support"] if entry.key?("stance")
          elsif updates.key?("stance")
            updates["support"] = updates["stance"] if entry.key?("support")
          end
          entry.merge!(updates)
          entry = BillLlmProvisioning.draft_with_summary_edited(
            entry, previous_summary: previous_summary
          )
          entry["summary"] = nil if neutral_draft?(entry)
          drafts[index] = entry
          :edited
        end

      provisioning.update!(draft_org_positions: drafts)
      {status: :applied, decision: decision, entry: entry}
    end
  end

  # @lat: [[organization-position-removal#A Neutral position carries no testimony]]
  def neutral_draft?(entry)
    OrganizationBillPosition.neutral_support?(entry["support"] || entry["stance"])
  end

  # @lat: [[bill-draft-org-positions-controller#Two different answers for an out-of-range index]]
  def draft_named_elsewhere?(drafts)
    drafts.any? do |entry|
      !BillLlmProvisioning.draft_identity_mismatch?(
        entry, name: params[:draft_org_name], token: params[:draft_token]
      )
    end
  end

  # @lat: [[bill-draft-org-positions-controller#Why a malformed id is a 422, not a 404]]
  def parse_composite_id(raw)
    str = raw.to_s
    m = str.match(/\A(\d+)-(\d+)\z/)
    return [nil, nil] unless m
    [m[1].to_i, m[2].to_i]
  end

  # @lat: [[bill-draft-org-positions-controller#Why edit_params excludes :rejected]]
  def edit_params
    params.permit(:org_name, :stance, :support, :summary)
  end
end
