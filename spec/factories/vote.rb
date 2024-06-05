
FactoryBot.define do
  factory :vote do
    bill

    # https://clerk.house.gov/Votes/2024142
    house_roll_call_vote_number { 142 }

    # https://www.senate.gov/legislative/LIS/roll_call_votes/vote1182/vote_118_2_00154.xml
    senate_roll_call_vote_number { 154 }

    initialize_with { new({ bill:, house_roll_call_vote_number:, senate_roll_call_vote_number: }) }
  end
end
