# frozen_string_literal: true

require "rails_helper"

# @lat: [[user-legislator-emails-controller-notes#Browser coverage for the modal (spec/system/email_legislators_spec.rb)]]
RSpec.describe "UserLegislatorEmails", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  def make_sendable(user)
    user.update!(
      email: "sender@example.com",
      is_email_verified: true,
      full_name: "Taylor Voter"
    )
  end

  describe "POST /user_legislator_emails" do
    it "creates a UserLegislatorEmail per user-legislator for the bill locale (recovered baseline)" do
      sway_locale, user = setup
      make_sendable(user)
      bill = create(:bill, sway_locale: sway_locale)

      expect do
        post user_legislator_emails_path,
          params: {user_legislator_email: {bill_id: bill.id}}
      end.to change(UserLegislatorEmail, :count).by(1)

      expect(response).to redirect_to(bill_path(bill.id))
      expect(UserLegislatorEmail.last!.bill).to eq(bill)
      expect(UserLegislatorEmail.last!.user).to eq(user)
    end

    it "is idempotent — a re-POST creates no duplicate rows" do
      sway_locale, user = setup
      make_sendable(user)
      bill = create(:bill, sway_locale: sway_locale)

      post user_legislator_emails_path,
        params: {user_legislator_email: {bill_id: bill.id}}

      expect do
        post user_legislator_emails_path,
          params: {user_legislator_email: {bill_id: bill.id}}
      end.not_to change(UserLegislatorEmail, :count)
    end

    it "redirects to /bills with an alert when the bill is missing" do
      _sway_locale, user = setup
      make_sendable(user)

      post user_legislator_emails_path,
        params: {user_legislator_email: {bill_id: 999_999}}

      expect(response).to redirect_to(bills_path)
      expect(flash[:alert]).to eq("Bill not found.")
    end

    it "rejects an unverified sender and creates nothing" do
      sway_locale, user = setup
      user.update!(full_name: "Taylor Voter") # named, but email unverified
      bill = create(:bill, sway_locale: sway_locale)

      expect do
        post user_legislator_emails_path,
          params: {user_legislator_email: {bill_id: bill.id}}
      end.not_to change(UserLegislatorEmail, :count)

      expect(response).to have_http_status(:redirect)
    end

    it "captures full_name inline when the user has none (deleted Users::UserDetailsController's job)" do
      sway_locale, user = setup
      user.update!(email: "sender@example.com", is_email_verified: true)
      bill = create(:bill, sway_locale: sway_locale)

      expect do
        post user_legislator_emails_path,
          params: {user_legislator_email: {bill_id: bill.id, full_name: "Jordan Q. Public"}}
      end.to change(UserLegislatorEmail, :count).by(1)

      expect(user.reload.full_name).to eq("Jordan Q. Public")
    end

    it "rejects an unsigned send (no full_name on the user, none supplied)" do
      sway_locale, user = setup
      user.update!(email: "sender@example.com", is_email_verified: true)
      bill = create(:bill, sway_locale: sway_locale)

      expect do
        post user_legislator_emails_path,
          params: {user_legislator_email: {bill_id: bill.id}}
      end.not_to change(UserLegislatorEmail, :count)

      expect(response).to have_http_status(:redirect)
    end

    it "re-enqueues the send job for an existing FAILED row (manual re-trigger)" do
      sway_locale, user = setup
      make_sendable(user)
      bill = create(:bill, sway_locale: sway_locale)
      user_legislator = user.user_legislators_by_locale(sway_locale).first #: UserLegislator
      failed_row = UserLegislatorEmail.create!(
        user_legislator: user_legislator,
        bill: bill,
        status: UserLegislatorEmail.statuses["failed"]
      )
      allow(OnUserEmailSavedSendEmailToLegislatorJob).to receive(:perform_later)

      expect do
        post user_legislator_emails_path,
          params: {user_legislator_email: {bill_id: bill.id}}
      end.not_to change(UserLegislatorEmail, :count)

      expect(OnUserEmailSavedSendEmailToLegislatorJob)
        .to have_received(:perform_later).with(failed_row)
    end

    it "does NOT re-enqueue a SENT row (never double-send)" do
      sway_locale, user = setup
      make_sendable(user)
      bill = create(:bill, sway_locale: sway_locale)
      user_legislator = user.user_legislators_by_locale(sway_locale).first #: UserLegislator
      UserLegislatorEmail.create!(
        user_legislator: user_legislator,
        bill: bill,
        status: UserLegislatorEmail.statuses["sent"]
      )
      allow(OnUserEmailSavedSendEmailToLegislatorJob).to receive(:perform_later)

      post user_legislator_emails_path,
        params: {user_legislator_email: {bill_id: bill.id}}

      expect(OnUserEmailSavedSendEmailToLegislatorJob).not_to have_received(:perform_later)
    end
  end
end
