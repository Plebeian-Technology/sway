FactoryBot.define do
  factory :user_bill_reminder do
    user
    bill
    sent_at { Time.current }
  end
end
