# == Schema Information
#
# Table name: sending_service_domains
# Database name: primary
#
#  id              :integer          not null, primary key
#  confirmed_at    :datetime
#  domain          :string           not null
#  label           :string           default("none"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  confirmed_by_id :integer
#
# Indexes
#
#  index_sending_service_domains_on_confirmed_by_id  (confirmed_by_id)
#  index_sending_service_domains_on_domain           (domain) UNIQUE
#
# Foreign Keys
#
#  confirmed_by_id  (confirmed_by_id => users.id)
#
FactoryBot.define do
  factory :sending_service_domain do
    sequence(:domain) { |n| "campaign-tool-#{n}.example.com" }

    trait :proposed do
      label { SendingServiceDomain::PROPOSED }
    end

    trait :confirmed do
      label { SendingServiceDomain::CONFIRMED }
      confirmed_by { association :user }
      confirmed_at { Time.zone.now }
    end
  end
end
