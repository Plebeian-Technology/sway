# frozen_string_literal: true

# @lat: [[organization-bill-position-ai-summary-flag#Why OrganizationBillPositionResource mirrors PUBLIC_FIELDS]]
class OrganizationBillPositionResource < ApplicationResource
  attributes :id, :organization_id, :bill_id, :support, :active,
    :created_at

  # @lat: [[organization-position-removal#A Neutral position carries no testimony]]
  attribute :summary do |position|
    position.summary_for_readers
  end

  # @lat: [[organization-bill-position-ai-summary-flag#Why OrganizationBillPositionResource mirrors PUBLIC_FIELDS]]
  attribute :summary_ai_unreviewed do |position|
    position.summary_ai_unreviewed?
  end
end
