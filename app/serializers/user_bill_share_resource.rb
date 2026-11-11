# frozen_string_literal: true

# @lat: [[domain-entities#People and identity]]
class UserBillShareResource < ApplicationResource
  attributes :id, :bill_id, :share_uuid, :share_path
end
