# frozen_string_literal: true

module Campaigns
  # @lat: [[campaign-organization-link#How candidates are proposed, and why the evidence travels with them]]
  class OrganizationCandidatesService
    SIGNATURE_BLOCK = "signature_block"
    BILL_POSITION = "bill_position"

    Candidate = Data.define(:organization_id, :organization_name, :evidence_kind, :letter_count, :claimed_name)

    class << self
      def call(campaign:)
        new(bill: campaign.bill).call(campaign)
      end

      # @lat: [[campaign-organization-link#Why an organization from another locale is refused]]
      def call_all(bill:, campaigns:)
        service = new(bill: bill)
        campaigns.each_with_object({}) do |campaign, by_campaign_id|
          by_campaign_id[campaign.id] = service.call(campaign)
        end
      end
    end

    def initialize(bill:)
      @bill = bill
    end

    def call(campaign)
      candidates = signature_block_candidates(campaign) + bill_position_candidates
      deduplicate(candidates).sort_by do |candidate|
        [evidence_rank(candidate.evidence_kind), -candidate.letter_count, candidate.organization_name.to_s.downcase]
      end
    end

    private

    attr_reader :bill

    def evidence_rank(kind)
      (kind == SIGNATURE_BLOCK) ? 0 : 1
    end

    # @lat: [[campaign-organization-link#How candidates are proposed, and why the evidence travels with them]]
    def deduplicate(candidates)
      candidates
        .group_by(&:organization_id)
        .values
        .filter_map { |group| group.min_by { |candidate| evidence_rank(candidate.evidence_kind) } }
    end

    # @lat: [[campaign-organization-link#How candidates are proposed, and why the evidence travels with them]]
    def signature_block_candidates(campaign)
      claims = claimed_organization_names(campaign)
      return [] if claims.empty?

      claims.filter_map do |downcased, claim|
        organization = organizations_by_downcased_name.fetch(downcased, nil)
        next if organization.nil?

        Candidate.new(
          organization_id: organization.id,
          organization_name: organization.name,
          evidence_kind: SIGNATURE_BLOCK,
          letter_count: claim.fetch(:count),
          claimed_name: claim.fetch(:as_written)
        )
      end
    end

    # @lat: [[campaign-organization-link#How candidates are proposed, and why the evidence travels with them]]
    def bill_position_candidates
      @bill_position_candidates ||=
        OrganizationBillPosition
          .where(bill_id: bill.id, active: true)
          .includes(:organization)
          .filter_map do |position|
            organization = position.organization

            Candidate.new(
              organization_id: organization.id,
              organization_name: organization.name,
              evidence_kind: BILL_POSITION,
              letter_count: 0,
              claimed_name: nil
            )
          end
    end

    def claimed_organization_names(campaign)
      names = campaign_letters(campaign).filter_map do |letter|
        raw_name = letter.dig("source_evidence", "org_name").presence || letter.dig("extracted_org", "org_name")
        raw_name.to_s.squeeze(" ").strip.presence
      end

      names.each_with_object({}) do |name, claims|
        claim = claims[name.downcase] ||= {count: 0, as_written: name}
        claim[:count] += 1
      end
    end

    def campaign_letters(campaign)
      hash = campaign.source_campaign_draft_hash
      return [] if hash.blank?

      current = artifact
      return [] unless current.is_a?(Hash)

      drafts = current["campaign_drafts"] || [] #: Array[Hash[String, untyped]]
      letters = current["letters"] || [] #: Array[Hash[String, untyped]]

      drafts.each do |draft|
        next unless draft["id"].to_s == hash.to_s

        positions = (draft["letter_positions"] || []).to_set
        return letters.select do |letter|
          positions.include?(letter["position"]) && letter["repeat"] != true && letter["excluded"] != true
        end
      end

      []
    end

    def artifact
      return @artifact if defined?(@artifact)

      @artifact = bill.bill_llm_provisioning&.cleaned_testimony
    end

    # @lat: [[campaign-organization-link#Why an organization from another locale is refused]]
    def organizations_by_downcased_name
      @organizations_by_downcased_name ||=
        Organization
          .where(sway_locale_id: bill.sway_locale_id)
          .index_by { |organization| organization.name.to_s.downcase }
    end
  end
end
