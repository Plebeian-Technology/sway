# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BillOfTheMonthSchedules", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:build_bill_for_schedule) do
    lambda do |sway_locale|
      legislator = create(:legislator)
      create(:bill, legislator: legislator, sway_locale: sway_locale, summary: "Tacos are great")
    end
  end

  describe "PUT /update" do
    context "with canonical endpoint and envelope" do
      # @lat: [[bill-of-the-month-schedule-admin-guard-order#Envelope parameter extraction]]
      it "redirects to edit_bill_creator_path and renders BILL_CREATOR with updated bill" do
        sway_locale, _user = setup
        bill = build_bill_for_schedule.call(sway_locale)

        put "/bill_of_the_month_schedule/#{bill.id}",
          params: {
            bill_of_the_month_schedule: {
              bill_id: bill.id,
              tab_key: nil,
              scheduled_release_date_utc: Time.zone.today.to_s
            }
          }

        expect(response).to have_http_status(:see_other).or have_http_status(:found)
        expect(response.location).to include("/admin/bill_creator/#{bill.id}/schedule")
        expect(flash[:notice]).to include("schedule")

        follow_redirect!

        expect(inertia).to render_component Pages::BILL_CREATOR
        expect(inertia.props[:bill][:id]).to eql(bill.id)
        expect(
          Date.parse(inertia.props[:bill][:scheduled_release_date_utc].to_s)
        ).to eql(Time.zone.today)
      end
    end

    context "with JSON numbers and form encoding" do
      it "handles raw JSON body with numeric bill_id and the canonical tab name" do
        sway_locale, _user = setup
        bill = build_bill_for_schedule.call(sway_locale)

        put "/bill_of_the_month_schedule/#{bill.id}",
          params: {
            bill_of_the_month_schedule: {
              bill_id: bill.id,
              bill_creator_tab: "schedule",
              scheduled_release_date_utc: "2026-09-08"
            }
          }.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:see_other).or have_http_status(:found)
        expect(response).to redirect_to(schedule_bill_creator_path(id: bill.id))
        expect(bill.reload.scheduled_release_date_utc).to eq(Date.new(2026, 9, 8))
      end

      it "handles form-encoded submission with string bill_id" do
        sway_locale, _user = setup
        bill = build_bill_for_schedule.call(sway_locale)

        put "/bill_of_the_month_schedule/#{bill.id}",
          params: {
            "bill_of_the_month_schedule" => {
              "bill_id" => bill.id.to_s,
              "tab_key" => "schedule",
              "scheduled_release_date_utc" => "2026-09-08"
            }
          }

        expect(response).to have_http_status(:see_other).or have_http_status(:found)
        expect(response).to redirect_to(schedule_bill_creator_path(id: bill.id))
        expect(bill.reload.scheduled_release_date_utc).to eq(Date.new(2026, 9, 8))
      end

      it "handles unenveloped top-level payload fallback" do
        sway_locale, _user = setup
        bill = build_bill_for_schedule.call(sway_locale)

        put "/bill_of_the_month_schedule/#{bill.id}",
          params: {
            bill_id: bill.id,
            tab_key: "schedule",
            scheduled_release_date_utc: "2026-09-08"
          }

        expect(response).to have_http_status(:see_other).or have_http_status(:found)
        expect(bill.reload.scheduled_release_date_utc).to eq(Date.new(2026, 9, 8))
      end
    end

    context "with empty string and nil cancellation" do
      it "cancels the schedule and sets column to nil when scheduled_release_date_utc is empty string" do
        sway_locale, _user = setup
        bill = build_bill_for_schedule.call(sway_locale)
        bill.update_column(:scheduled_release_date_utc, Date.new(2026, 9, 8))

        put "/bill_of_the_month_schedule/#{bill.id}",
          params: {
            bill_of_the_month_schedule: {
              bill_id: bill.id,
              tab_key: nil,
              scheduled_release_date_utc: ""
            }
          }

        expect(response).to have_http_status(:see_other).or have_http_status(:found)
        expect(bill.reload.scheduled_release_date_utc).to be_nil
        expect(flash[:notice]).to eq("Bill - #{bill.title} - removed from schedule.")
      end

      it "cancels the schedule and sets column to nil when scheduled_release_date_utc is nil" do
        sway_locale, _user = setup
        bill = build_bill_for_schedule.call(sway_locale)
        bill.update_column(:scheduled_release_date_utc, Date.new(2026, 9, 8))

        put "/bill_of_the_month_schedule/#{bill.id}",
          params: {
            bill_of_the_month_schedule: {
              bill_id: bill.id,
              tab_key: nil,
              scheduled_release_date_utc: nil
            }
          }

        expect(response).to have_http_status(:see_other).or have_http_status(:found)
        expect(bill.reload.scheduled_release_date_utc).to be_nil
        expect(flash[:notice]).to eq("Bill - #{bill.title} - removed from schedule.")
      end
    end

    context "with the bare calendar day the schedule tab sends" do
      # @lat: [[bill-schedule-calendar-dates#Why a picked day travels as a bare day]]
      it "stores the day that was submitted" do
        sway_locale, _user = setup
        bill = build_bill_for_schedule.call(sway_locale)

        put "/bill_of_the_month_schedule/#{bill.id}",
          params: {
            bill_of_the_month_schedule: {
              bill_id: bill.id,
              tab_key: nil,
              scheduled_release_date_utc: "2026-09-08"
            }
          }

        expect(bill.reload.scheduled_release_date_utc).to eq(Date.new(2026, 9, 8))
      end

      it "would have stored the day before had an instant been sent from east of UTC" do
        sway_locale, _user = setup
        bill = build_bill_for_schedule.call(sway_locale)

        put "/bill_of_the_month_schedule/#{bill.id}",
          params: {
            bill_of_the_month_schedule: {
              bill_id: bill.id,
              tab_key: nil,
              scheduled_release_date_utc: "2026-09-07T15:00:00.000Z"
            }
          }

        expect(bill.reload.scheduled_release_date_utc).to eq(Date.new(2026, 9, 7))
      end
    end

    context "with invalid params" do
      it "redirects back to edit_bill_creator_path with errors carried via inertia: {}" do
        sway_locale, _user = setup
        bill = build_bill_for_schedule.call(sway_locale)

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

        expect(response).to have_http_status(:see_other).or have_http_status(:found)
        expect(response.location).to include("/admin/bill_creator/#{bill.id}/schedule")
        expect(flash[:alert]).to eq("Failed to update bill schedule.")

        follow_redirect!

        expect(inertia).to render_component Pages::BILL_CREATOR
        expect(inertia.props[:errors]).to be_present
        expect(
          inertia.props[:errors][:scheduled_release_date_utc]
        ).to be_present
      end
    end

    # @lat: [[bill-creator-shell#The Bill Creator shell#Why tab URLs retain legacy compatibility]]
    context "tab parameter dispatch" do
      {
        "creator" => "creator",
        "schedule" => "schedule",
        "pipeline" => "pipeline",
        "pipeline_llm" => "pipeline",
        "summary" => "summary"
      }.each do |submitted, segment|
        it "redirects to /#{segment} when tab_key=#{submitted}" do
          sway_locale, _user = setup
          bill = build_bill_for_schedule.call(sway_locale)

          put "/bill_of_the_month_schedule/#{bill.id}",
            params: {
              bill_of_the_month_schedule: {
                bill_id: bill.id,
                tab_key: submitted,
                scheduled_release_date_utc: Time.zone.today.to_s
              }
            }

          expect(response.location).to end_with("/admin/bill_creator/#{bill.id}/#{segment}")
        end
      end

      it "reads the canonical tab name from the nested schedule payload" do
        sway_locale, _user = setup
        bill = build_bill_for_schedule.call(sway_locale)

        put "/bill_of_the_month_schedule/#{bill.id}",
          params: {
            bill_of_the_month_schedule: {
              bill_id: bill.id,
              bill_creator_tab: "summary",
              scheduled_release_date_utc: Time.zone.today.to_s
            }
          }

        expect(response.location).to end_with("/admin/bill_creator/#{bill.id}/summary")
      end

      it "does not restore a legacy tab when the nested canonical value is empty" do
        sway_locale, _user = setup
        bill = build_bill_for_schedule.call(sway_locale)

        put "/bill_of_the_month_schedule/#{bill.id}",
          params: {
            bill_of_the_month_schedule: {
              bill_id: bill.id,
              bill_creator_tab: "",
              tab_key: "summary",
              scheduled_release_date_utc: Time.zone.today.to_s
            }
          }

        expect(response.location).to end_with("/admin/bill_creator/#{bill.id}/schedule")
      end

      it "falls back to /schedule when tab_key is unknown (defensive)" do
        sway_locale, _user = setup
        bill = build_bill_for_schedule.call(sway_locale)

        put "/bill_of_the_month_schedule/#{bill.id}",
          params: {
            bill_of_the_month_schedule: {
              bill_id: bill.id,
              tab_key: "garbage",
              scheduled_release_date_utc: Time.zone.today.to_s
            }
          }

        expect(response.location).to end_with("/admin/bill_creator/#{bill.id}/schedule")
      end
    end

    context "when bill is not found" do
      it "returns 404 for admin via Rails default ActiveRecord::RecordNotFound rescue" do
        setup

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

      # @lat: [[bill-of-the-month-schedule-admin-guard-order#Bill of the Month schedule: admin guard order and tab redirect default]]
      it "redirects to root for non-admin on nonexistent bill ID without 404" do
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

    context "with mobile bootstrap cache invalidation" do
      include_context "with in-memory Rails.cache"

      it "evicts the cached featured bill for the bill's locale on successful schedule update" do
        sway_locale, _user = setup
        bill = build_bill_for_schedule.call(sway_locale)
        cache_key = "api_v1_bootstrap:botm:#{sway_locale.id}"
        Rails.cache.write(cache_key, {"id" => bill.id, "title" => "Stale"})

        put "/bill_of_the_month_schedule/#{bill.id}",
          params: {
            bill_of_the_month_schedule: {
              bill_id: bill.id,
              tab_key: nil,
              scheduled_release_date_utc: Time.zone.today.to_s
            }
          }

        expect(response).to have_http_status(:see_other).or have_http_status(:found)
        expect(Rails.cache.read(cache_key)).to be_nil
      end

      it "preserves the cached featured bill when schedule update is refused" do
        sway_locale, _user = setup
        bill = build_bill_for_schedule.call(sway_locale)
        cache_key = "api_v1_bootstrap:botm:#{sway_locale.id}"
        Rails.cache.write(cache_key, {"id" => bill.id, "title" => "Stale"})

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

        expect(response).to have_http_status(:see_other).or have_http_status(:found)
        expect(Rails.cache.read(cache_key)).to eq({"id" => bill.id, "title" => "Stale"})
      end
    end
  end

  describe "PATCH /update" do
    let(:bearer_json_headers) do
      lambda do |user|
        authenticate_as(user).merge("Accept" => "application/json", "Content-Type" => "application/json")
      end
    end

    def patch_schedule(bill, date, user)
      patch "/bill_of_the_month_schedule/#{bill.id}",
        params: {bill_id: bill.id, scheduled_release_date_utc: date}.to_json,
        headers: bearer_json_headers.call(user)
    end

    # @lat: [[mobile-bill-creator#Sections#The schedule section]]
    it "schedules the bill for a bearer client and answers 200 JSON with no redirect" do
      sway_locale, user = setup
      bill = build_bill_for_schedule.call(sway_locale)

      patch_schedule(bill, "2026-09-08", user)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(bill.reload.scheduled_release_date_utc).to eq(Date.new(2026, 9, 8))
    end

    # @lat: [[mobile-bill-creator#Sections#The schedule section]]
    it "unschedules the bill when the date is blank" do
      sway_locale, user = setup
      bill = build_bill_for_schedule.call(sway_locale)
      bill.update_column(:scheduled_release_date_utc, Date.new(2026, 9, 8))

      patch_schedule(bill, "", user)

      expect(response).to have_http_status(:ok)
      expect(bill.reload.scheduled_release_date_utc).to be_nil
    end

    # @lat: [[mobile-bill-creator#Sections#The schedule section]]
    it "answers 422 JSON naming the date when another bill already holds it" do
      sway_locale, user = setup
      bill = build_bill_for_schedule.call(sway_locale)
      bill.update_column(:scheduled_release_date_utc, nil)
      other = build_bill_for_schedule.call(sway_locale)
      other.update_column(:scheduled_release_date_utc, Date.new(2026, 9, 8))

      patch_schedule(bill, "2026-09-08", user)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_body.dig(:error, :code)).to eq("validation_failed")
      expect(json_body.dig(:error, :message)).to eq("Another bill is already scheduled for that date.")
      expect(json_body.dig(:error, :details, :scheduled_release_date_utc)).to be_present
      expect(bill.reload.scheduled_release_date_utc).to be_nil
    end

    # @lat: [[mobile-bill-creator#Sections#The schedule section]]
    it "redirects the web with the error when another bill already holds the date" do
      sway_locale, _user = setup
      bill = build_bill_for_schedule.call(sway_locale)
      bill.update_column(:scheduled_release_date_utc, nil)
      other = build_bill_for_schedule.call(sway_locale)
      other.update_column(:scheduled_release_date_utc, Date.new(2026, 9, 8))

      put "/bill_of_the_month_schedule/#{bill.id}",
        params: {bill_of_the_month_schedule: {bill_id: bill.id, scheduled_release_date_utc: "2026-09-08"}}

      expect(response).to redirect_to(schedule_bill_creator_path(id: bill.id))
      expect(flash[:alert]).to eq("Another bill is already scheduled for that date.")

      follow_redirect!

      expect(inertia.props[:errors][:scheduled_release_date_utc]).to be_present
      expect(bill.reload.scheduled_release_date_utc).to be_nil
    end
  end
end
