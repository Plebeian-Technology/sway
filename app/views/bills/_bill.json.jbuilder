json.extract! bill, :id, :external_id, :external_version, :title, :link, :chamber, :house_vote_date_time_utc, :senate_vote_date_time_utc, :chamber, :introduced_date_time_utc, :category, :sponsor_id, :level, :created_at, :updated_at
json.url bill_url(bill, format: :json)
