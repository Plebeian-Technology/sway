# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BillOfTheMonth", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:build_bill_of_the_month) do
    lambda do |sway_locale|
      legislator = create(:legislator)
      create(
        :bill,
        legislator:,
        sway_locale:,
        summary: "Tacos are great",
        scheduled_release_date_utc: Time.zone.now
      )
    end
  end

  describe "GET /bill_of_the_month" do
    it "gets the bill of the month" do
      sway_locale, _user = setup
      bill = build_bill_of_the_month.call(sway_locale)

      get "/bill_of_the_month"

      expect(inertia).to render_component Pages::BILL_OF_THE_MONTH
      expect(inertia.props[:bill]["id"]).to eql(bill.id)
      expect(inertia.props.keys).to include("bill", "bill_score", "user_vote")
      expect(inertia.props.keys).not_to include("legislators")

      inertia_versioned_reload_only("legislators")
      expect(inertia.props.keys).to include("legislators")
    end

    # @lat: [[bill-of-the-month-no-redirect-on-empty#Why an empty Bill of the Month stays on the page]]
    it "renders the page with no bill when the locale has nothing featured" do
      setup

      get "/bill_of_the_month"

      expect(response).not_to have_http_status(:redirect)
      expect(inertia).to render_component Pages::BILL_OF_THE_MONTH
      expect(inertia.props[:bill]).to be_nil
    end

    it "ships a whitelisted legislator resource (not raw AR) for ?with=legislator" do
      sway_locale, _user = setup
      build_bill_of_the_month.call(sway_locale)

      get "/bill_of_the_month?with=legislator"

      legislator = inertia.props[:legislator]
      expect(legislator).to be_present
      expect(legislator.keys.map(&:to_s)).to match_array(
        %w[
          id external_id active link email title first_name last_name
          full_name phone fax party photo_url twitter sway_locale_id district
          term_start_year term_end_year began_on ended_on terms
        ]
      )
    end

    it "does NOT redirect on GET /bill_of_the_month with queries" do
      sway_locale, _user = setup
      build_bill_of_the_month.call(sway_locale)

      get "/bill_of_the_month?sway_locale_id=#{sway_locale.id}&with=legislator"

      expect(response).to have_http_status(:ok)
      expect(response).not_to have_http_status(:redirect)
      expect(inertia).to render_component Pages::BILL_OF_THE_MONTH
    end

    # @lat: [[identity-and-access#The admin gate is a lint rule#An admin affordance in the reader's page is a convenience, not a gate]]
    describe "admin edit link visibility" do
      it "ships is_admin on the bill of the month page for a sway admin" do
        sway_locale, _user = setup
        build_bill_of_the_month.call(sway_locale)

        get "/bill_of_the_month"

        expect(inertia.props[:user]).to include(is_admin: true)
      end

      it "omits is_admin from the bill of the month page for a non-admin" do
        sway_locale, _user = setup
        build_bill_of_the_month.call(sway_locale)
        stub_const("User::ADMIN_PHONES", ["+19999999999"])

        get "/bill_of_the_month"

        user_data = inertia.props[:user] || {}
        expect(user_data).not_to have_key(:is_admin)
        expect(user_data).not_to have_key("is_admin")
      end

      it "omits is_admin from the bill of the month page for a signed-out visitor" do
        sway_locale = create(:sway_locale)
        build_bill_of_the_month.call(sway_locale)

        get "/bill_of_the_month?sway_locale_id=#{sway_locale.id}"

        user_data = inertia.props[:user] || {}
        expect(user_data).not_to have_key(:is_admin)
        expect(user_data).not_to have_key("is_admin")
      end
    end
  end

  describe "API reader routes" do
    let(:raw_token) { "test-bearer-#{SecureRandom.hex(8)}" }

    it "serves JSON for GET /api/bill_of_the_month" do
      sway_locale, user = setup
      bill = build_bill_of_the_month.call(sway_locale)
      ApiKey.create!(bearer: user, token: raw_token)

      get "/api/bill_of_the_month", headers: {"Authorization" => "Bearer #{raw_token}"}

      expect(response).to have_http_status(:ok)
      body = json_body
      expect(body).to have_key(:bill)
      expect(body[:bill][:id]).to eq(bill.id)
    end
  end

  # @lat: [[testimony-letters#Reading the letters inside a testimony bundle#Presenting public testimony on bill pages#Signed-out readers receive no public testimony]]
  describe "public testimony visibility" do
    let(:letter_text) { "I strongly support this bill for our community." }
    let(:provision_letters) do
      lambda do |bill|
        create(
          :bill_llm_provisioning,
          bill:,
          cleaned_testimony: {
            "text" => "Header info\nFrom: test@example.com\n\n#{letter_text}",
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
        )
      end
    end

    it "sends public testimony counts and letters to a signed-in reader" do
      sway_locale, _user = setup
      provision_letters.call(build_bill_of_the_month.call(sway_locale))

      get "/bill_of_the_month"

      expect(inertia.props[:public_testimony_counts]).to eq(
        {"total" => 1, "support" => 1, "oppose" => 0, "neutral" => 0}
      )

      inertia_versioned_reload_only("public_testimony_letters")

      expect(inertia.props[:public_testimony_letters].length).to eq(1)
    end

    it "sends no public testimony counts or letters to a signed-out reader" do
      sway_locale = create(:sway_locale)
      provision_letters.call(build_bill_of_the_month.call(sway_locale))

      get "/bill_of_the_month?sway_locale_id=#{sway_locale.id}"

      expect(inertia).to render_component Pages::BILL_OF_THE_MONTH
      expect(inertia.props[:public_testimony_counts]).to be_nil

      inertia_versioned_reload_only("public_testimony_letters")

      expect(inertia.props[:public_testimony_letters]).to be_nil
      expect(response.body).not_to include(letter_text)
    end

    it "sends no public testimony counts or letters to a signed-out JSON reader" do
      sway_locale = create(:sway_locale)
      provision_letters.call(build_bill_of_the_month.call(sway_locale))

      get "/bill_of_the_month?sway_locale_id=#{sway_locale.id}", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(json_body[:public_testimony_counts]).to be_nil
      expect(json_body[:public_testimony_letters]).to be_nil
      expect(response.body).not_to include(letter_text)
    end
  end
end
