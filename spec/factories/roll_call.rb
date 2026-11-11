FactoryBot.define do
  factory :roll_call do
    bill

    house_roll_call_vote_number { 142 }
    senate_roll_call_vote_number { 108 }

    initialize_with do
      new(
        {bill:, house_roll_call_vote_number:, senate_roll_call_vote_number:}
      )
    end
  end

  factory :vote, parent: :roll_call, class: "RollCall"
end
