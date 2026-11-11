# frozen_string_literal: true

require "rails_helper"

# @lat: [[supplemental-testimony-clear-endpoint-rationale#UpdateSupplementalTestimonyService implementation notes]]

RSpec.describe "Bills supplemental_testimony admin gate", type: :request do
  include_examples "requires sway admin",
    verb: :patch,
    path: "/bills/1/supplemental_testimony"
end

RSpec.describe "PATCH /bills/:id/supplemental_testimony", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:user) { sway_locale_and_user.last }

  let(:bill) do
    legislator = sway_locale.legislators.first
    create(:bill, sway_locale: sway_locale, legislator: legislator)
  end

  let!(:provisioning) { create(:bill_llm_provisioning, bill: bill) }

  # The whole reason this endpoint exists. If it ever starts enqueuing a job,
  # the Clear button quietly turns into a button that costs money.
  it "enqueues no generation job" do
    provisioning.update!(supplemental_testimony: "Testimony to remove.")

    expect {
      patch supplemental_testimony_bill_path(bill), params: {clear_supplemental_testimony: "1"}
    }.not_to have_enqueued_job(GenerateBillSummaryJob)
  end

  it "clears the column on an explicit clear" do
    provisioning.update!(supplemental_testimony: "Testimony to remove.")

    patch supplemental_testimony_bill_path(bill), params: {clear_supplemental_testimony: "1"}

    expect(provisioning.reload.supplemental_testimony).to be_nil
  end

  it "saves a paste without generating" do
    patch supplemental_testimony_bill_path(bill), params: {supplemental_testimony: "Pasted testimony."}

    expect(provisioning.reload.supplemental_testimony).to eq("Pasted testimony.")
  end

  # Same rule about blank values as the two generate actions. All three go
  # through SupplementalTestimonyWrite so they cannot drift apart.
  it "does not destroy a stored paste on a blank value" do
    provisioning.update!(supplemental_testimony: "Testimony another operator pasted.")

    patch supplemental_testimony_bill_path(bill), params: {supplemental_testimony: ""}

    expect(provisioning.reload.supplemental_testimony).to eq("Testimony another operator pasted.")
  end

  it "ignores a non-String value rather than coercing it into the column" do
    provisioning.update!(supplemental_testimony: "Testimony another operator pasted.")

    patch supplemental_testimony_bill_path(bill), params: {supplemental_testimony: {"a" => "b"}}

    expect(provisioning.reload.supplemental_testimony).to eq("Testimony another operator pasted.")
  end

  # Post, then redirect, then get. The redirect is what refills the operator's
  # textarea, because the client takes the field's value from the server on
  # that follow-up GET.
  it "redirects to the positions tab so Inertia re-renders from fresh props" do
    patch supplemental_testimony_bill_path(bill), params: {clear_supplemental_testimony: "1"}

    expect(response).to redirect_to(positions_bill_creator_path(bill))
  end

  it "creates the provisioning row when the bill has none yet" do
    provisioning.destroy!

    patch supplemental_testimony_bill_path(bill), params: {supplemental_testimony: "First paste."}

    expect(bill.reload.bill_llm_provisioning&.supplemental_testimony).to eq("First paste.")
  end
end
