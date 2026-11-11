# frozen_string_literal: true

# @lat: [[outbound-email#Why mailers default to outreach@sway.vote and bake invite expiry into signed tokens]]
class UserLegislatorEmailResource < ApplicationResource
  attributes :id, :bill_id, :status

  attribute :legislator_id do |user_legislator_email|
    user_legislator_email.legislator.id
  end

  attribute :legislator_full_name do |user_legislator_email|
    legislator = user_legislator_email.legislator
    "#{legislator.first_name} #{legislator.last_name}"
  end
end
