# frozen_string_literal: true

# == Schema Information
#
# Table name: sending_service_domain_bills
# Database name: primary
#
#  id                        :integer          not null, primary key
#  letter_count              :integer          not null
#  machine_sent_letter_count :integer          not null
#  sender_count              :integer          not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  bill_id                   :integer          not null
#  sending_service_domain_id :integer          not null
#
# Indexes
#
#  index_sending_service_domain_bills_on_bill_id          (bill_id)
#  index_sending_service_domain_bills_on_domain_and_bill  (sending_service_domain_id,bill_id) UNIQUE
#
# Foreign Keys
#
#  bill_id                    (bill_id => bills.id)
#  sending_service_domain_id  (sending_service_domain_id => sending_service_domains.id)
#
class SendingServiceDomainBill < ApplicationRecord
  belongs_to :sending_service_domain
  belongs_to :bill

  validates :bill_id, uniqueness: {scope: :sending_service_domain_id}
  validates :sender_count, :letter_count, :machine_sent_letter_count,
    presence: true,
    numericality: {greater_than_or_equal_to: 0, only_integer: true}

  # @lat: [[domain-panel-totals#Where the domain panel's totals come from]]
  def self.record_contribution!(sending_service_domain:, bill:, sender_count:, letter_count:, machine_sent_letter_count:)
    contribution = find_or_initialize_by(sending_service_domain:, bill:)
    contribution.update!(
      sender_count: sender_count,
      letter_count: letter_count,
      machine_sent_letter_count: machine_sent_letter_count
    )
    contribution
  end
end
