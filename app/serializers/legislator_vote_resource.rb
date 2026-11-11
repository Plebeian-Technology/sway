# frozen_string_literal: true

class LegislatorVoteResource < ApplicationResource
  attributes :id, :legislator_id, :bill_id, :support
end
