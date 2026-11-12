# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_summary_reports
# Database name: primary
#
#  id                    :integer          not null, primary key
#  admin_notes           :text
#  details               :text
#  ip_address            :string
#  reason                :string           not null
#  resolved_at           :datetime
#  status                :integer          default("pending"), not null
#  summary_ai_unreviewed :boolean          default(TRUE), not null
#  summary_snapshot      :text
#  user_agent            :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  bill_id               :integer          not null
#  resolved_by_id        :integer
#  user_id               :integer
#
# Indexes
#
#  index_bill_summary_reports_on_bill_id                    (bill_id)
#  index_bill_summary_reports_on_bill_id_and_created_at     (bill_id,created_at)
#  index_bill_summary_reports_on_bill_id_and_status         (bill_id,status)
#  index_bill_summary_reports_on_ip_address_and_created_at  (ip_address,created_at)
#  index_bill_summary_reports_on_resolved_by_id             (resolved_by_id)
#  index_bill_summary_reports_on_status                     (status)
#  index_bill_summary_reports_on_user_id                    (user_id)
#
# Foreign Keys
#
#  bill_id         (bill_id => bills.id) ON DELETE => cascade
#  resolved_by_id  (resolved_by_id => users.id) ON DELETE => nullify
#  user_id         (user_id => users.id) ON DELETE => nullify
#
FactoryBot.define do
  factory :bill_summary_report do
    bill
    user { nil }
    reason { "factual_inaccuracy" }
    details { "The summary misstates the tax credit percentages." }
    status { :pending }
    sequence(:ip_address) { |n| "192.168.1.#{n % 250 + 1}" }
    user_agent { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" }
    summary_snapshot { bill&.summary || "Summary text." }
    summary_ai_unreviewed { true }

    trait :reviewed do
      status { :reviewed }
    end

    trait :resolved do
      status { :resolved }
      resolved_by factory: %i[user sway_admin]
      resolved_at { Time.current }
      admin_notes { "Updated summary via Bill Creator." }
    end
  end
end
