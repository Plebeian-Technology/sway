# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-of-the-month-schedule-admin-guard-order#Bill of the Month schedule: admin guard order and tab redirect default]]
RSpec.describe "BillOfTheMonthScheduleController admin gate", type: :request do
  include_examples "requires sway admin",
    verb: :put,
    path: "/bill_of_the_month_schedule/0",
    params: {bill_of_the_month_schedule: {bill_id: 1}}
end

# @lat: [[bill-of-the-month-schedule-admin-guard-order#Bill of the Month schedule: admin guard order and tab redirect default]]
RSpec.describe "BillOfTheMonthScheduleController admin gate — discriminating", type: :request do
  include_context "SessionDouble"

  it "blocks a registration-complete non-admin from mutating the schedule" do
    sway_locale = create(:sway_locale)
    legislator = create(:legislator)
    bill = create(:bill, sway_locale: sway_locale, legislator: legislator, scheduled_release_date_utc: nil)

    non_admin = create(:user)
    complete_registration_with_active_link(non_admin)
    session_hash[:user_id] = non_admin.id

    put "/bill_of_the_month_schedule/#{bill.id}",
      params: {
        bill_of_the_month_schedule: {
          bill_id: bill.id,
          tab_key: nil,
          scheduled_release_date_utc: Time.zone.today.to_s
        }
      }

    expect(response).to redirect_to(root_path)
    expect(bill.reload.scheduled_release_date_utc).to be_nil
  end

  it "refuses a non-admin before bill lookup, redirecting on a nonexistent bill ID instead of returning 404" do
    non_admin = create(:user)
    complete_registration_with_active_link(non_admin)
    session_hash[:user_id] = non_admin.id

    put "/bill_of_the_month_schedule/99999999",
      params: {
        bill_of_the_month_schedule: {
          bill_id: 99_999_999,
          tab_key: nil,
          scheduled_release_date_utc: Time.zone.today.to_s
        }
      }

    expect(response).to redirect_to(root_path)
    expect(response).not_to have_http_status(:not_found)
  end
end

RSpec.describe "Admin bill of the month schedule", type: :request do
  let(:admin) { create(:user, :sway_admin) }
  let(:sway_locale) { create(:sway_locale) }
  let(:legislator) { create(:legislator) }
  let(:bill) do
    create(:bill, sway_locale: sway_locale, legislator: legislator)
  end

  before { sign_in admin }

  describe "PUT /bill_of_the_month_schedule/:id as admin" do
    it "allows admin to update the schedule" do
      put "/bill_of_the_month_schedule/#{bill.id}",
        params: {
          bill_of_the_month_schedule: {
            bill_id: bill.id,
            tab_key: nil,
            scheduled_release_date_utc: Time.zone.today.to_s
          }
        }

      expect(response).to have_http_status(:see_other).or have_http_status(
        :found
      )
      expect(response.location).to include("/admin/bill_creator/#{bill.id}/schedule")
    end

    it "redirects to root when a logged-out user attempts to update" do
      sign_out admin

      put "/bill_of_the_month_schedule/#{bill.id}",
        params: {
          bill_of_the_month_schedule: {
            bill_id: bill.id,
            tab_key: nil,
            scheduled_release_date_utc: Time.zone.today.to_s
          }
        }

      # authenticate_sway_user! sends logged-out users to root/registration
      expect(response).to have_http_status(:redirect)
    end

    it "returns 404 when the bill is not found" do
      put "/bill_of_the_month_schedule/99999999",
        params: {
          bill_of_the_month_schedule: {
            bill_id: 99_999_999,
            tab_key: nil,
            scheduled_release_date_utc: Time.zone.today.to_s
          }
        }

      expect(response).to have_http_status(:not_found)
    end

    it "surfaces validation errors via flash + inertia when update fails" do
      errors = ActiveModel::Errors.new(bill)
      errors.add(:scheduled_release_date_utc, "is invalid")
      allow_any_instance_of(Bill).to receive(:update).and_return(false)
      allow_any_instance_of(Bill).to receive(:errors).and_return(errors)

      put "/bill_of_the_month_schedule/#{bill.id}",
        params: {
          bill_of_the_month_schedule: {
            bill_id: bill.id,
            tab_key: nil,
            scheduled_release_date_utc: "not-a-date"
          }
        }

      expect(response).to have_http_status(:see_other).or have_http_status(
        :found
      )
      expect(flash[:alert]).to eq("Failed to update bill schedule.")
    end
  end
end
