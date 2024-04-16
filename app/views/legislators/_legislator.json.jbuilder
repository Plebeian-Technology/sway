json.extract! legislator, :id, :external_id, :active, :link, :email, :district, :title, :first_name, :last_name, :phone, :fax, :address_id, :party, :photo_url, :created_at, :updated_at
json.url legislator_url(legislator, format: :json)
