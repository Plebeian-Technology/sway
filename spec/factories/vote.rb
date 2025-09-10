FactoryBot.define do
    factory :vote do
        bill

        # https://clerk.house.gov/Votes/2024142
        house_roll_call_vote_number { 142 }

        # OLD: https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00154.xml
        # NEW: https://www.senate.gov/legislative/LIS/roll_call_votes/vote1191/vote_119_1_00108.xml
        senate_roll_call_vote_number { 108 }

        initialize_with { new({ bill:, house_roll_call_vote_number:, senate_roll_call_vote_number: }) }
    end
end
