json.extract! vote, :id, :voted_on_utc, :bill_id, :created_at, :updated_at
json.url vote_url(vote, format: :json)
