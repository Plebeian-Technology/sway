# frozen_string_literal: true

class LegislatorTermResource < ApplicationResource
  attributes :term_start_year, :term_end_year, :title

  # @lat: [[legislator-resource-design#Why historical terms serialize agreement scores alongside session metadata]]
  attribute :began_on do |term|
    term.began_on&.iso8601
  end

  attribute :ended_on do |term|
    term.ended_on&.iso8601
  end

  one :district, resource: DistrictResource
end
