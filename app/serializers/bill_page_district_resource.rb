# frozen_string_literal: true

class BillPageDistrictResource < ApplicationResource
  attributes :name, :number

  attribute :region_code do |district|
    district.region_code
  end
end
