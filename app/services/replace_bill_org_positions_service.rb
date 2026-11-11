# frozen_string_literal: true

# @lat: [[replace-bill-org-positions-service-design#Why the write upserts by (bill, organization) instead of deleting and re-inserting]]
class ReplaceBillOrgPositionsService
  class Result
    attr_reader :kind, :http_status, :error, :message, :payload

    def initialize(kind:, http_status: nil, error: nil, message: nil, payload: nil)
      @kind = kind
      @http_status = http_status
      @error = error
      @message = message
      @payload = payload
    end

    def ok?
      kind == :ok
    end

    def empty?
      kind == :empty
    end
  end

  def self.call(positions:, actor:)
    new(positions: positions, actor: actor).call
  end

  def initialize(positions:, actor:)
    @positions = positions
    @actor = actor
  end

  def call
    return Result.new(kind: :empty) if @positions.blank?

    raw_positions = @positions

    # @lat: [[replace-bill-org-positions-service-design#Why the write upserts by (bill, organization) instead of deleting and re-inserting]]
    bill_ids = raw_positions.pluck(:bill_id).compact.uniq
    if bill_ids.empty?
      return error(:unprocessable_content, "missing_bill_id", "Every position must declare a bill_id")
    end
    if bill_ids.size > 1
      return error(:unprocessable_content, "mixed_bill_ids", "All positions in one request must share a bill_id")
    end
    bill = Bill.find_by(id: bill_ids.first)
    if bill.nil?
      return error(:not_found, "bill_not_found", "No bill with id=#{bill_ids.first}")
    end

    normalized_positions = raw_positions.map(&:to_h)

    # @lat: [[replace-bill-org-positions-service-design#Why every position is validated as a batch BEFORE any position is validated individually, and both before any write]]
    normalized_positions.each do |pos|
      needs_summary = !neutral?(pos["support"])
      if pos["bill_id"].blank? || pos["organization_id"].blank? ||
          (needs_summary && pos["summary"].to_s.strip.empty?)
        return error(
          :unprocessable_content,
          "incomplete_position",
          "Every position must include bill_id, organization_id, and — unless it is neutral — a non-blank summary"
        )
      end
    end

    invalid_stance = nil #: (String | Symbol)?
    normalized_positions.each do |pos|
      original = pos["support"].to_s
      if original.empty?
        invalid_stance = :missing
        break
      end
      mapped = OrganizationBillPosition.normalize_support(original)
      if mapped.nil?
        invalid_stance = original
        break
      end
      pos["support"] = mapped
    end
    if invalid_stance
      message =
        if invalid_stance == :missing
          "Each position must include a `support` value (one of: support|oppose|neutral|FOR|AGAINST|ABSTAIN)"
        else
          "Unknown support value #{invalid_stance.inspect}; expected support|oppose|neutral|FOR|AGAINST|ABSTAIN"
        end
      return error(:unprocessable_content, "invalid_stance", message)
    end

    # @lat: [[replace-bill-org-positions-service-design#Why organization ids are validated before the delete runs]]
    org_ids = normalized_positions.map { |pos| pos["organization_id"].to_i }
    if org_ids.uniq.size != org_ids.size
      return error(
        :unprocessable_content,
        "duplicate_organization_id",
        "Each organization may appear at most once per request"
      )
    end
    if Organization.where(id: org_ids, sway_locale_id: bill.sway_locale_id).count != org_ids.size
      return error(:not_found, "organization_not_found", "One or more organization_ids do not exist in this bill's jurisdiction")
    end

    # @lat: [[replace-bill-org-positions-service-design#Why the write upserts by (bill, organization) instead of deleting and re-inserting]]
    upserted = [] #: Array[OrganizationBillPosition]
    retried = false
    begin
      ActiveRecord::Base.transaction do
        OrganizationBillPosition
          .where(bill_id: bill.id, active: true)
          .where.not(organization_id: org_ids)
          .find_each { |absent| absent.update!(active: false) }
        upserted = normalized_positions.map do |pos|
          position = OrganizationBillPosition.find_or_initialize_by(
            bill_id: bill.id, organization_id: pos["organization_id"]
          )
          position.support = pos["support"]
          position.summary = summary_for(pos)
          position.active = true
          position.save!
          position
        end
      end
    rescue ActiveRecord::RecordNotUnique
      # @lat: [[replace-bill-org-positions-service-design#Why the write upserts by (bill, organization) instead of deleting and re-inserting]]
      raise if retried
      retried = true
      retry
    end

    # @lat: [[replace-bill-org-positions-service-design#Why the write upserts by (bill, organization) instead of deleting and re-inserting]]
    RecomputeBillInterestingScoreJob.perform_later(bill.id)

    raw_positions.each do |pos|
      org_name =
        Organization.find_by(id: pos[:organization_id])&.name.to_s.presence || "unknown"
      draft_view = Struct.new(:id, :organization_name).new(
        "approved-#{pos[:bill_id]}-#{pos[:organization_id]}",
        org_name
      )
      PipelineActivityLogger.log_org_position_decision!(
        bill: bill,
        draft: draft_view,
        decision: :approved,
        actor: @actor
      )
    end

    # @lat: [[replace-bill-org-positions-service-design#Why the write upserts by (bill, organization) instead of deleting and re-inserting]]
    Result.new(
      kind: :ok,
      payload: OrganizationBillPositionResource.new(upserted).serializable_hash
    )
  end

  private

  def error(http_status, code, message)
    Result.new(kind: :error, http_status: http_status, error: code, message: message)
  end

  def neutral?(support)
    OrganizationBillPosition.neutral_support?(support)
  end

  # @lat: [[organization-position-removal#A Neutral position carries no testimony]]
  def summary_for(pos)
    return OrganizationBillPosition::DEFAULT_SUMMARY if neutral?(pos["support"])

    pos["summary"]
  end
end
