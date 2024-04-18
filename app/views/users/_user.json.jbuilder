json.extract! user, :id, :email, :phone, :is_registration_complete, :address_id, :last_login_utc, :is_registered_to_vote, :is_email_verified, :is_admin, :created_at, :updated_at
json.url user_url(user, format: :json)
