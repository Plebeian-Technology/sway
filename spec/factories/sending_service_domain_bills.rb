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
FactoryBot.define do
  factory :sending_service_domain_bill do
    sending_service_domain
    bill
    sender_count { 5 }
    letter_count { 5 }
    machine_sent_letter_count { 0 }
  end
end
