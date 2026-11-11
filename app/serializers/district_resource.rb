# frozen_string_literal: true

# @lat: [[serializer-whitelist-endpoints#Why DistrictResource's field list matches the old to_builder and raw index shapes]]
class DistrictResource < ApplicationResource
  attributes :id, :name, :sway_locale_id, :number, :region_code
end
