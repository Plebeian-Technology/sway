FactoryBot.define do
  factory :bill_score do
    association :bill
    against { 0 }
    add_attribute(:for) { 0 }
  end
end
