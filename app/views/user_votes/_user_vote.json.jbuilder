json.extract! user_vote, :id, :user_id, :bill_id, :support, :created_at, :updated_at
json.url user_vote_url(user_vote, format: :json)
