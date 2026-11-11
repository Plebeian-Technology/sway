# frozen_string_literal: true

# @lat: [[bill-creator-positions-tab#Why testimony report resources expose raw counts and evidence without confidence scores]]
class SendingServiceDomainResource < ApplicationResource
  attributes :id, :domain, :label

  attribute :sender_count do |domain|
    domain.sender_count
  end

  attribute :machine_sent_letter_count do |domain|
    domain.machine_sent_letter_count
  end

  attribute :letter_count do |domain|
    domain.letter_count
  end

  attribute :bill_count do |domain|
    domain.bill_count
  end
end
