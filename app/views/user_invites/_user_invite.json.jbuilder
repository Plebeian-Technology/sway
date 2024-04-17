json.extract! user_invite, :id, :user_id, :invitee_email, :invite_expires_on_utc, :invite_accepted_on_utc, :created_at, :updated_at
json.url user_invite_url(user_invite, format: :json)
