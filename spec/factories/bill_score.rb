FactoryBot.define do
  factory :bill_score do
    bill
    against { 0 }
    add_attribute(:for) { 0 }

    # A Bill's after_create_commit callback already creates its BillScore
    # (create_default_bill_score), and bill_scores.bill_id now has a unique
    # index. Reuse the bill's existing score rather than inserting a second one,
    # which would raise RecordNotUnique.
    initialize_with { bill.bill_score || bill.build_bill_score }
  end
end
