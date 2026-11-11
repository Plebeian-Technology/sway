# frozen_string_literal: true

require "rails_helper"

# @lat: [[testimony-letters#Reading the letters inside a testimony bundle#Browsing constituent testimony in the modal]]
RSpec.describe "Bills::PublicTestimonyLetters", type: :request do
  # @type self: PublicTestimonyLettersRequestSpecContext
  include_context "SessionDouble"
  include_context "Setup"

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:user) { sway_locale_and_user.last }
  let(:bill) { create(:bill, sway_locale:, legislator: sway_locale.legislators.first) }
  let(:token) { "public-testimony-letters-token" }
  let(:bearer_headers) { {"Authorization" => "Bearer #{token}", "Accept" => "application/json"} }
  let(:letter_body) { "I strongly support this bill for our community." }
  let(:cleaned_testimony) do
    {
      "text" => "Header info\nFrom: test@example.com\n\n#{letter_body}",
      "letters" => [
        {
          "position" => 1,
          "source_kind" => "person_speaking_for_self",
          "stance" => "support",
          "characters" => 71,
          "character_offset" => 12
        }
      ]
    }
  end
  let(:expected_letters) do
    [{"position" => 1, "label" => "Constituent Letter #1", "stance" => "support", "body_text" => letter_body}]
  end

  before do
    create(:api_key, token:, bearer: user)
    session_hash.delete(:user_id)
  end

  describe "GET /bills/:bill_id/public_testimony_letters" do
    # @lat: [[testimony-letters#Reading the letters inside a testimony bundle#Browsing constituent testimony in the modal]]
    it "gives a signed-in reader the bill's letters and nothing else" do
      create(:bill_llm_provisioning, bill:, cleaned_testimony:)

      get "/bills/#{bill.id}", headers: bearer_headers
      page_letters = response.parsed_body.fetch("public_testimony_letters")

      get "/bills/#{bill.id}/public_testimony_letters", headers: bearer_headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body).to eq(expected_letters)
      expect(response.parsed_body).to eq(page_letters)
      expect(response.parsed_body.first.keys).to match_array(%w[position label stance body_text])
      expect(response.body).not_to include("test@example.com")
    end

    it "gives a signed-in reader an empty list for a bill with no letters" do
      get "/bills/#{bill.id}/public_testimony_letters", headers: bearer_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    # @lat: [[testimony-letters#Reading the letters inside a testimony bundle#Presenting public testimony on bill pages#Signed-out readers receive no public testimony]]
    it "gives a signed-out reader the null the bill page's optional prop carries" do
      create(:bill_llm_provisioning, bill:, cleaned_testimony:)

      get "/bills/#{bill.id}", headers: {"Accept" => "application/json"}
      expect(response.parsed_body.fetch("public_testimony_letters")).to be_nil

      get "/bills/#{bill.id}/public_testimony_letters", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("null")
      expect(response.body).not_to include(letter_body)
    end

    it "answers 404 for an unknown bill id to a signed-in and a signed-out reader" do
      create(:bill_llm_provisioning, bill:, cleaned_testimony:)
      get "/bills/#{bill.id}/public_testimony_letters", headers: bearer_headers
      expect(response).to have_http_status(:ok)

      get "/bills/0/public_testimony_letters", headers: bearer_headers
      expect(response).to have_http_status(:not_found)

      get "/bills/0/public_testimony_letters", headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:not_found)
    end

    it "does not serve an HTML page" do
      create(:bill_llm_provisioning, bill:, cleaned_testimony:)
      get "/bills/#{bill.id}/public_testimony_letters", headers: bearer_headers
      expect(response).to have_http_status(:ok)

      get "/bills/#{bill.id}/public_testimony_letters", headers: bearer_headers.merge("Accept" => "text/html")

      expect(response).to have_http_status(:not_acceptable)
      expect(response.body).not_to include(letter_body)
    end

    it "serves the letters of every bill the bill page opens, archived, inactive or from another locale" do
      other_locale = create(:sway_locale, (sway_locale.city == "congress") ? :maryland : :congress)
      opened_bills = [
        create(:bill, sway_locale:, legislator: sway_locale.legislators.first, archived_at: Time.current),
        create(:bill, sway_locale:, legislator: sway_locale.legislators.first, active: false),
        create(:bill, sway_locale: other_locale)
      ]

      opened_bills.each do |opened_bill|
        create(:bill_llm_provisioning, bill: opened_bill, cleaned_testimony:)

        get "/bills/#{opened_bill.id}", headers: bearer_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.fetch("public_testimony_letters")).to eq(expected_letters)

        get "/bills/#{opened_bill.id}/public_testimony_letters", headers: bearer_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq(expected_letters)
      end
    end
  end
end
