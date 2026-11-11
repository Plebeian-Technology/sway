# frozen_string_literal: true

# @lat: [[system-shape#System shape#One process, two languages#Why a payload goes through a resource rather than the record]]
class UserVoteResource < ApplicationResource
  attributes :id, :bill_id, :support
end
