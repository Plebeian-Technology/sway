json.extract! user_legislator_score, :id, :user_legislator_id, :count_agreed, :count_disagreed, :count_no_legislator_vote, :count_legislator_abstained, :created_at, :updated_at
json.url user_legislator_score_url(user_legislator_score, format: :json)
