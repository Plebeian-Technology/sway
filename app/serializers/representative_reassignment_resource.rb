# frozen_string_literal: true

class RepresentativeReassignmentResource < ApplicationResource
  attributes :id, :reassignment_type, :dismissed_at, :created_at

  one :district, resource: DistrictResource
  one :previous_district, resource: DistrictResource
  one :legislator, resource: LegislatorResource
  one :previous_legislator, resource: LegislatorResource
end
