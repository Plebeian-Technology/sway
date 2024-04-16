json.extract! legislator_vote, :id, :legislator_id, :bill_id, :support, :created_at, :updated_at
json.url legislator_vote_url(legislator_vote, format: :json)
