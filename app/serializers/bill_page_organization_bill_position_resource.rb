# frozen_string_literal: true

# @lat: [[bills-controller-design#BillsController design#The bill page returns active organization positions as flat rows]]
class BillPageOrganizationBillPositionResource < ApplicationResource
  attributes :id, :bill_id

  attribute :organization do |position|
    BillPageOrganizationResource.new(position.organization).serializable_hash
  end

  attributes :support

  attribute :summary do |position|
    position.summary_for_readers
  end

  attribute :summary_ai_unreviewed do |position|
    position.summary_ai_unreviewed?
  end
end
