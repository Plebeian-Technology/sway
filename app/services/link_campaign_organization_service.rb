# frozen_string_literal: true

# @lat: [[campaign-organization-link#Why this is a second approval and not part of the first]]
class LinkCampaignOrganizationService
  def initialize(bill:, campaign:, actor:, decision:, organization_id: nil, organization_name: nil)
    @bill = bill
    @campaign = campaign
    @actor = actor
    @decision = decision.to_s
    @organization_id = organization_id.presence
    @organization_name = organization_name.to_s.squeeze(" ").strip.presence
  end

  def call
    return :campaign_not_on_bill unless @campaign.bill_id == @bill.id
    return :invalid_decision unless Campaign::ORGANIZATION_LINK_DECISIONS.include?(@decision)

    (@decision == Campaign::LINKED) ? link : clear
  end

  private

  def link
    if @organization_id.present?
      organization = Organization.find_by(id: @organization_id)
      return :organization_not_found if organization.nil?

      # @lat: [[campaign-organization-link#Why an organization from another locale is refused]]
      return :organization_wrong_locale unless organization.sway_locale_id == @bill.sway_locale_id

      write(decision: Campaign::LINKED, organization: organization)
      :linked
    elsif (name = @organization_name) && !name.empty?
      return :organization_name_too_long if name.length > Campaign::MAX_NAME_CHARS

      ActiveRecord::Base.transaction do
        organization = find_or_create_organization(name)
        write(decision: Campaign::LINKED, organization: organization)
      end
      :linked
    else
      :organization_required
    end
  end

  def find_or_create_organization(name)
    existing = Organization.where(sway_locale_id: @bill.sway_locale_id).where("LOWER(name) = ?", name.downcase).first
    return existing if existing

    Organization.create!(name: name, sway_locale: @bill.sway_locale)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    Organization.where(sway_locale_id: @bill.sway_locale_id).where("LOWER(name) = ?", name.downcase).first || raise(e)
  end

  def clear
    write(decision: @decision, organization: nil)
    (@decision == Campaign::NO_ORGANIZATION) ? :recorded_no_organization : :recorded_undetermined
  end

  # @lat: [[campaign-organization-link#Why an organization from another locale is refused]]
  def write(decision:, organization:)
    @campaign.with_lock do
      @campaign.organization = organization
      @campaign.organization_link_decision = decision
      @campaign.save!
    end
    log_decision(decision, organization)
  end

  # @lat: [[campaign-organization-link#Why this is a second approval and not part of the first]]
  def log_decision(decision, organization)
    campaign_view = Struct.new(:id, :organization_name).new(
      "#{@bill.id}-campaign-#{@campaign.id}-organization",
      organization&.name || @campaign.name.presence || "Unnamed campaign"
    )
    PipelineActivityLogger.log_org_position_decision!(
      bill: @bill,
      draft: campaign_view,
      decision: :"organization_#{decision}",
      actor: @actor,
      extra: {campaign_id: @campaign.id, organization_id: organization&.id}
    )
  end
end
