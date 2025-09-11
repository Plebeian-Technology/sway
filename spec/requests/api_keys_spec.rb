require "rails_helper"

RSpec.describe "ApiKeys", type: :request, inertia: true do
  include_context "SessionDouble"
  include_context "Setup"

  describe "GET /index" do
    it "lists all the current api keys" do
      _, user = setup

      api_key = create(:api_key, bearer: user)

      get "/api_keys"

      expect(inertia.props[:api_keys].to_a).to eql([api_key])
    end
  end

  describe "POST /create" do
    it "creates a new api key for a user" do
      _, user = setup

      expect(user.api_keys).to be_empty

      post "/api_keys", params: {}

      expect(user.api_keys).to_not be_empty
    end

    it "can only create 1 api key for a user" do
      _, user = setup

      post "/api_keys", params: {}
      expect(user.api_keys.size).to eq(1)
      post "/api_keys", params: {}
      expect(user.api_keys.size).to eq(1)
    end
  end

  describe "PUT /update" do
    it "updates the name of the api key" do
      _, user = setup

      api_key = create(:api_key, bearer: user)

      expect(api_key.name).to_not equal("Taco")
      put "/api_keys/#{api_key.id}",
          params: {
            api_keys_update_params: {
              name: "Taco",
            },
          }
      expect(api_key.name).to_not equal("Taco")
    end

    it "does not permit other parameters" do
      _, user = setup

      api_key = create(:api_key, bearer: user)
      digest = api_key.token_digest

      expect(api_key.bearer.id).to equal(user.id)

      put "/api_keys/#{api_key.id}",
          params: {
            api_keys_update_params: {
              bearer_id: 30,
            },
          }
      expect(api_key.token_digest).to equal(digest)
      expect(api_key.bearer.id).to equal(user.id)
      expect(api_key.bearer.id).to_not equal(30)
    end
  end

  describe "DELETE /delete" do
    it "deletes a user's API key" do
      _, user = setup

      api_key = create(:api_key, bearer: user)

      delete "/api_keys/#{api_key.id}"

      expect(user.api_keys).to be_empty
    end
  end
end
