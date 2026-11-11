require "rails_helper"

RSpec.describe "ApiKeys", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "GET /index" do
    it "renders the ApiKeys component" do
      _, _user = setup

      get "/api_keys"

      expect(inertia).to render_component Pages::API_KEYS
    end

    it "lists all the current api keys" do
      _, user = setup

      api_key = create(:api_key, bearer: user)
      device = create(:user_device, user: user)
      create(:api_key, bearer: user, user_device: device, name: "mobile-ios-#{device.id}")

      get "/api_keys"

      props = inertia.props[:api_keys].to_a
      expect(props.length).to eq(1)
      expect(props.first["id"]).to eq(api_key.id)
    end

    # The list page sends ApiKey#to_sway_json, not the raw database rows. token_digest
    # is the secret a token is checked against, and bearer_id and bearer_type are
    # internal plumbing the frontend has no use for. None of them may reach the browser.
    # If this test fails, a secret has been exposed again.
    it "does not expose token_digest, bearer_id, or bearer_type" do
      _, user = setup
      create(:api_key, bearer: user)

      get "/api_keys"

      payload = inertia.props[:api_keys].to_a.first
      expect(payload).not_to have_key("token_digest")
      expect(payload).not_to have_key("bearer_id")
      expect(payload).not_to have_key("bearer_type")
    end

    it "passes the api_keys prop" do
      _, _user = setup

      get "/api_keys"

      expect(inertia).to have_props { |p| p.key?(:api_keys) }
    end
  end

  describe "POST /create" do
    it "creates a new api key for a user" do
      _, user = setup

      expect(user.api_keys).to be_empty

      post "/api_keys", params: {}

      expect(user.api_keys).to_not be_empty
    end

    # @lat: [[one-time-secret-flash-no-store#Why new_api_key_token reaches the page at all]]
    it "surfaces new_api_key_token in the Inertia flash prop after create" do
      _, _user = setup

      post "/api_keys", params: {}
      follow_redirect!

      flash_prop = inertia.props[:flash] || {}
      token = flash_prop["new_api_key_token"] || flash_prop[:new_api_key_token]
      expect(token).to be_present
      expect(token).to be_a(String)
    end

    # @lat: [[identity-and-access#The one response whose body carries a secret is never stored]]
    it "forbids storing the one response whose body carries the secret" do
      _, _user = setup

      post "/api_keys", params: {}
      follow_redirect!

      expect(response.body).to include(flash[:new_api_key_token].to_s)
      expect(response.headers["Cache-Control"]).to eq("no-store")
    end

    # Measured before the guard was written: the secret is gone by the next
    # request. This pins that, so a change that keeps it in the session for
    # longer is visible rather than silent — every extra request is another
    # response whose body carries the secret.
    it "carries the secret for exactly one response" do
      _, _user = setup

      post "/api_keys", params: {}
      token = flash[:new_api_key_token].to_s
      expect(token).to be_present

      follow_redirect!
      expect(response.body).to include(token)

      get "/api_keys"
      expect(response.body).not_to include(token)
      expect(response.headers["Cache-Control"]).not_to eq("no-store")
    end

    it "can only create 1 api key for a user" do
      _, user = setup

      post "/api_keys", params: {}
      expect(user.api_keys.size).to eq(1)
      post "/api_keys", params: {}
      expect(user.api_keys.size).to eq(1)
    end

    it "allows creating 1 developer api key even when the user already has a mobile device api key" do
      _, user = setup
      device = create(:user_device, user: user)
      create(:api_key, bearer: user, user_device: device, name: "mobile-ios-#{device.id}")

      expect {
        post "/api_keys", params: {}
      }.to change { user.api_keys.where(user_device_id: nil).count }.from(0).to(1)
    end
  end

  describe "PUT /update" do
    it "updates the name of the api key" do
      _, user = setup

      api_key = create(:api_key, bearer: user, name: "Original")

      expect(api_key.name).to eq("Original")
      put "/api_keys/#{api_key.id}",
        params: {
          api_keys_update_params: {
            name: "Taco"
          }
        }
      api_key.reload
      expect(api_key.name).to eq("Taco")
    end

    it "does not rename a mobile device api key" do
      _, user = setup
      device = create(:user_device, user: user)
      mobile_key = create(:api_key, bearer: user, user_device: device, name: "mobile-ios-#{device.id}")

      put "/api_keys/#{mobile_key.id}",
        params: {
          api_keys_update_params: {
            name: "Renamed"
          }
        }

      expect(mobile_key.reload.name).to eq("mobile-ios-#{device.id}")
    end

    it "does not permit other parameters" do
      _, user = setup

      api_key = create(:api_key, bearer: user)
      digest = api_key.token_digest

      expect(api_key.bearer.id).to eq(user.id)

      put "/api_keys/#{api_key.id}",
        params: {
          api_keys_update_params: {
            bearer_id: 30
          }
        }
      api_key.reload
      expect(api_key.token_digest).to eq(digest)
      expect(api_key.bearer.id).to eq(user.id)
      expect(api_key.bearer.id).to_not eq(30)
    end
  end

  describe "DELETE /delete" do
    it "deletes a user's API key" do
      _, user = setup

      api_key = create(:api_key, bearer: user)

      delete "/api_keys/#{api_key.id}"

      expect(user.api_keys).to be_empty
    end

    it "does not delete a mobile device api key" do
      _, user = setup
      device = create(:user_device, user: user)
      mobile_key = create(:api_key, bearer: user, user_device: device, name: "mobile-ios-#{device.id}")

      expect {
        delete "/api_keys/#{mobile_key.id}"
      }.not_to change { ApiKey.exists?(mobile_key.id) }
    end
  end

  describe "authorization (API_USER_PHONES gate)" do
    it "redirects a non-API user to root_path and refuses to create an API key" do
      _, user = setup
      User.send(:remove_const, :API_USER_PHONES)
      User.const_set(:API_USER_PHONES, ["4109999999"].freeze)

      get "/api_keys"
      expect(response).to redirect_to(root_path)

      expect {
        post "/api_keys", params: {}
      }.not_to change { user.api_keys.count }
      expect(response).to redirect_to(root_path)
    end
  end
end
