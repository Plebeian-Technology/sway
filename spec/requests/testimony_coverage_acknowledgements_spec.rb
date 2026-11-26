# frozen_string_literal: true

require "rails_helper"

# The endpoint behind Surface 3's "Acknowledge the
# missing testimony" button.

RSpec.describe "TestimonyCoverageAcknowledgements admin gate", type: :request do
  include_examples "requires sway admin",
    verb: :post,
    path: "/bills/1/testimony_coverage_acknowledgement"
end

RSpec.describe "POST /bills/:bill_id/testimony_coverage_acknowledgement", type: :request do
  include_context "SessionDouble"
  include_context "Setup"
  include TestimonySpecHelpers

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:user) { sway_locale_and_user.last }

  let(:bill) do
    legislator = sway_locale.legislators.first
    create(:bill, sway_locale: sway_locale, legislator: legislator)
  end

  describe "a successful acknowledgement" do
    let!(:provisioning) do
      create(:bill_llm_provisioning, bill: bill, extracted_testimony: "R" * (max_chars + 500))
    end

    it "redirects to the positions tab and stores a row naming the acknowledging admin" do
      post bill_testimony_coverage_acknowledgement_path(bill), params: {digest: current_digest}

      expect(response).to redirect_to(positions_bill_creator_path(bill))
      ack = TestimonyCoverageAcknowledgement.sole
      expect(ack.bill).to eq(bill)
      expect(ack.acknowledged_by).to eq(user)
    end

    it "reports back a success notice, not an error" do
      post bill_testimony_coverage_acknowledgement_path(bill), params: {digest: current_digest}
      follow_redirect!

      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props[:errors]).to be_blank
    end

    it "flashes the acknowledged notice naming the bill" do
      post bill_testimony_coverage_acknowledgement_path(bill), params: {digest: current_digest}
      follow_redirect!

      expect(inertia).to have_flash(notice: "Acknowledged the missing testimony on #{bill.external_id}.")
    end
  end

  describe "every refusal reaches the operator by name" do
    let!(:provisioning) do
      create(:bill_llm_provisioning, bill: bill, extracted_testimony: "R" * (max_chars + 500))
    end

    it "refuses with a message while a clean-testimony run is in progress" do
      create(:legislation_pipeline_run, bill: bill, status: "cleaning_testimony")

      post bill_testimony_coverage_acknowledgement_path(bill), params: {digest: "whatever"}
      expect(response).to redirect_to(positions_bill_creator_path(bill))
      follow_redirect!

      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props[:errors][:testimony_coverage]).to match(/progress/i)
      expect(TestimonyCoverageAcknowledgement.count).to eq(0)
    end

    it "refuses with a message when the report finds nothing to acknowledge" do
      provisioning.update!(
        extracted_testimony: "R" * 900,
        cleaned_testimony: {
          "version" => 1, "text" => "C" * 900,
          "counts" => {"raw_chars" => 900, "cleaned_chars" => 900},
          # The letter spans the WHOLE cleaned text — production's
          # LetterSplitter always partitions it fully, so a shorter letter
          # here would leave chars unaccounted for and read as a real gap.
          "letters" => [
            {"position" => 0, "character_offset" => 0, "characters" => 900,
             "sender_address" => nil, "sender_domain" => nil,
             "source_kind" => "named_organization", "source_evidence" => nil}
          ],
          "campaign_drafts" => []
        },
        cleaned_testimony_at: 1.hour.ago
      )

      post bill_testimony_coverage_acknowledgement_path(bill), params: {digest: current_digest}
      follow_redirect!

      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props[:errors][:testimony_coverage]).to match(/nothing to acknowledge/i)
      expect(TestimonyCoverageAcknowledgement.count).to eq(0)
    end

    it "refuses with a message when the digest sent no longer matches the current numbers" do
      post bill_testimony_coverage_acknowledgement_path(bill), params: {digest: "a-stale-digest"}
      follow_redirect!

      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props[:errors][:testimony_coverage]).to match(/changed/i)
      expect(TestimonyCoverageAcknowledgement.count).to eq(0)
    end
  end
end

# @lat: [[mobile-bill-creator#Sections#The testimony coverage section#Answering the acknowledgement in JSON]]
RSpec.describe "POST /bills/:bill_id/testimony_coverage_acknowledgement for a bearer request", type: :request do
  include TestimonySpecHelpers

  let(:admin) { create(:user, :sway_admin) }
  let(:bill) { create(:bill) }
  let(:json_headers) { authenticate_as(admin).merge("Accept" => "application/json") }
  let(:non_admin_headers) do
    user = create(:user)
    create(:user_legislator, user: user)
    user.complete!
    authenticate_as(user).merge("Accept" => "application/json")
  end

  let!(:provisioning) do
    create(:bill_llm_provisioning, bill: bill, extracted_testimony: "R" * (max_chars + 500))
  end

  it "records the acknowledgement and answers 200 JSON" do
    post bill_testimony_coverage_acknowledgement_path(bill), params: {digest: current_digest}, headers: json_headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq({})
    expect(TestimonyCoverageAcknowledgement.sole.acknowledged_by).to eq(admin)
  end

  it "answers a stale digest with 422 and the web's reason under testimony_coverage" do
    post bill_testimony_coverage_acknowledgement_path(bill), params: {digest: "a-stale-digest"}, headers: json_headers

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
    expect(response.parsed_body.dig("error", "details", "testimony_coverage")).to match(/changed/i)
    expect(TestimonyCoverageAcknowledgement.count).to eq(0)
  end

  it "answers a clean-testimony run in progress with 422 and the web's reason" do
    create(:legislation_pipeline_run, bill: bill, status: "cleaning_testimony")

    post bill_testimony_coverage_acknowledgement_path(bill), params: {digest: current_digest}, headers: json_headers

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig("error", "details", "testimony_coverage")).to match(/progress/i)
    expect(TestimonyCoverageAcknowledgement.count).to eq(0)
  end

  it "answers nothing left out with 422 and the web's reason" do
    provisioning.update!(extracted_testimony: nil)

    post bill_testimony_coverage_acknowledgement_path(bill), params: {digest: current_digest}, headers: json_headers

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig("error", "details", "testimony_coverage")).to match(/nothing to acknowledge/i)
  end

  it "answers a non-admin with 403 JSON" do
    post bill_testimony_coverage_acknowledgement_path(bill), params: {digest: current_digest}, headers: non_admin_headers

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
    expect(TestimonyCoverageAcknowledgement.count).to eq(0)
  end
end
