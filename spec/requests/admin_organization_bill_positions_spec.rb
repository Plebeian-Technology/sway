# frozen_string_literal: true

require "rails_helper"

# Checks that only admins can reach OrganizationBillPositionsController#create. The
# controller declares `before_action :verify_is_sway_admin, only: %i[create]`. These
# tests sign in and out to pin that down, using the :sway_admin factory trait, which
# gives the user a phone number listed in ADMIN_PHONES.
RSpec.describe "Admin organization bill positions", type: :request do
  let(:admin) { create(:user, :sway_admin) }
  let(:sway_locale) { create(:sway_locale) }
  let(:organization) { create(:organization, sway_locale: sway_locale) }
  let(:bill) { create(:bill, sway_locale: sway_locale) }

  before { sign_in admin }

  describe "POST /organization_bill_positions (admin-only via verify_is_sway_admin)" do
    it "creates positions when signed in as sway_admin" do
      expect {
        post organization_bill_positions_path,
          params: {
            organization_bill_position: {
              positions: [
                {
                  bill_id: bill.id,
                  organization_id: organization.id,
                  support: "support",
                  summary: "We support this bill."
                }
              ]
            }
          }
      }.to change(OrganizationBillPosition, :count).by(1)

      expect(response).to have_http_status(:ok)
    end

    it "returns :no_content when positions array is absent" do
      post organization_bill_positions_path,
        params: {organization_bill_position: {positions: nil}}

      expect(response).to have_http_status(:no_content)
    end

    # @lat: [[organization-position-removal#Taking an organization's position off a bill#Bulk position writes stay behind the service boundary]]
    it "returns 422 incomplete_position when a position omits organization_id" do
      expect {
        post organization_bill_positions_path,
          params: {
            organization_bill_position: {
              positions: [
                {bill_id: bill.id, support: "support", summary: "No org id"}
              ]
            }
          }
      }.not_to change(OrganizationBillPosition, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]["code"]).to eq("incomplete_position")
    end

    it "returns 422 incomplete_position when a position has a blank summary" do
      expect {
        post organization_bill_positions_path,
          params: {
            organization_bill_position: {
              positions: [
                {bill_id: bill.id, organization_id: organization.id,
                 support: "support", summary: "   "}
              ]
            }
          }
      }.not_to change(OrganizationBillPosition, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]["code"]).to eq("incomplete_position")
    end

    it "denies non-admin users (redirects to root)" do
      sign_out admin

      # Empty ADMIN_PHONES so the freshly built user's phone number is not an admin's.
      # The ensure block puts the original list back even if the test fails.
      original_admin_phones = User::ADMIN_PHONES.dup
      begin
        User.send(:remove_const, :ADMIN_PHONES)
        User.const_set(:ADMIN_PHONES, [])
        non_admin = create(:user)
        sign_in non_admin

        post organization_bill_positions_path,
          params: {
            organization_bill_position: {
              positions: [
                {
                  bill_id: bill.id,
                  organization_id: organization.id,
                  support: "support",
                  summary: "Should be denied."
                }
              ]
            }
          }

        # verify_is_sway_admin redirects to root_path on non-admin
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include("/")
      ensure
        User.send(:remove_const, :ADMIN_PHONES)
        User.const_set(:ADMIN_PHONES, original_admin_phones)
      end
    end

    it "denies logged-out users (redirect from authenticate_sway_user!)" do
      sign_out admin

      post organization_bill_positions_path,
        params: {
          organization_bill_position: {
            positions: [
              {
                bill_id: bill.id,
                organization_id: organization.id,
                support: "support",
                summary: "Should be denied."
              }
            ]
          }
        }

      expect(response).to have_http_status(:redirect)
    end
  end

  # Reading positions is admin-only as well. The outer before block has already signed
  # this test in as an admin.
  describe "GET /organization_bill_positions (admin-gated)" do
    it "returns scoped positions for a given bill_id" do
      create(
        :organization_bill_position,
        bill: bill,
        organization: organization
      )

      get organization_bill_positions_path, params: {bill_id: bill.id}

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
    end
  end

  # @lat: [[organization-notification-delivery#Immediate delivery uses a durable marker#Bulk upserts use the position callback token]]
  describe "POST /organization_bill_positions — bulk upsert notify + delivery" do
    let(:org2) { create(:organization, sway_locale: sway_locale, name: "Second Test Org") }

    it "enqueues exactly one NotifyOrganizationFollowersJob per unique organization (callback path)" do
      # Two organizations, one bill: after_commit fires once per saved row. Each is a
      # first position on that bill, labelled [:new_position], with its own delivery
      # token.
      post organization_bill_positions_path,
        params: {
          organization_bill_position: {
            positions: [
              {bill_id: bill.id, organization_id: organization.id,
               support: "support", summary: "Org 1 position"},
              {bill_id: bill.id, organization_id: org2.id,
               support: "oppose", summary: "Org 2 position"}
            ]
          }
        }

      expect(response).to have_http_status(:ok)
      expect(NotifyOrganizationFollowersJob).to have_been_enqueued.exactly(2).times
      expect(NotifyOrganizationFollowersJob).to have_been_enqueued
        .with(organization.id, bill.id, ["new_position"], anything)
      expect(NotifyOrganizationFollowersJob).to have_been_enqueued
        .with(org2.id, bill.id, ["new_position"], anything)
    end

    it "upserts rows as active:true so they are publicly visible AND notifiable (CR-02)" do
      post organization_bill_positions_path,
        params: {
          organization_bill_position: {
            positions: [
              {bill_id: bill.id, organization_id: organization.id,
               support: "support", summary: "New position"}
            ]
          }
        }

      expect(response).to have_http_status(:ok)
      inserted = OrganizationBillPosition.find_by(bill_id: bill.id, organization_id: organization.id)
      expect(inserted.active).to be(true)
    end

    it "keeps the position's primary key STABLE across re-submit (CR-03 — no destroy+re-insert)" do
      params = {
        organization_bill_position: {
          positions: [
            {bill_id: bill.id, organization_id: organization.id,
             support: "support", summary: "Original"}
          ]
        }
      }
      post organization_bill_positions_path, params: params
      first_id = OrganizationBillPosition.find_by!(bill_id: bill.id, organization_id: organization.id).id

      post organization_bill_positions_path, params: params
      second_id = OrganizationBillPosition.find_by!(bill_id: bill.id, organization_id: organization.id).id

      expect(second_id).to eq(first_id)
    end

    context "with an every_change follower (real fan-out, no stub)" do
      let(:params) do
        {
          organization_bill_position: {
            positions: [
              {bill_id: bill.id, organization_id: organization.id,
               support: "support", summary: "We support this bill."}
            ]
          }
        }
      end

      before do
        follower = create(:user).tap do |u|
          u.update_columns(sms_notifications_enabled: true, is_phone_verified: true)
        end
        create(:notification_preference, user: follower, key: "org_position_taken", enabled: true)
        create(:organization_follow,
          user: follower, organization: organization,
          notification_cadence: :every_change, notify_on_new_position: true)
      end

      it "delivers to the follower end-to-end on first approve (CR-02 regression)" do
        # Run only the notify job, so the SmsDeliveryJob it queues up stays in the
        # queue where the test can look for it. Nothing here is faked.
        expect {
          perform_enqueued_jobs(only: NotifyOrganizationFollowersJob) do
            post organization_bill_positions_path, params: params
          end
        }.to have_enqueued_job(SmsDeliveryJob)

        expect(response).to have_http_status(:ok)
      end

      it "does NOT re-deliver on an identical re-submit (CR-03 — double-click / network retry)" do
        # First approve delivers once.
        perform_enqueued_jobs(only: NotifyOrganizationFollowersJob) do
          post organization_bill_positions_path, params: params
        end

        # The very same submission again: find_or_initialize finds the existing row,
        # nothing has changed, so save! writes nothing, after_commit never fires, no
        # notify job is queued, and no text message goes out.
        expect {
          perform_enqueued_jobs(only: NotifyOrganizationFollowersJob) do
            post organization_bill_positions_path, params: params
          end
        }.not_to have_enqueued_job(SmsDeliveryJob)
      end
    end
  end

  # @lat: [[organization-position-removal#Removal deactivates, it does not delete]]
  describe "DELETE /organization_bill_positions/:id" do
    let!(:position) do
      create(:organization_bill_position,
        bill: bill, organization: organization, active: true,
        support: "FOR", summary: "We support this bill.")
    end

    it "lowers the active flag instead of destroying the row" do
      expect {
        delete organization_bill_position_path(position)
      }.not_to change(OrganizationBillPosition, :count)

      expect(position.reload.active).to be(false)
    end

    it "leaves the organization standing" do
      expect {
        delete organization_bill_position_path(position)
      }.not_to change(Organization, :count)

      expect(Organization.find_by(id: organization.id)).to be_present
    end

    context "with an every_change follower" do
      before do
        follower = create(:user).tap do |u|
          u.update_columns(sms_notifications_enabled: true, is_phone_verified: true)
        end
        create(:notification_preference, user: follower, key: "org_position_taken", enabled: true)
        create(:organization_follow,
          user: follower, organization: organization,
          notification_cadence: :every_change, notify_on_new_position: true)
      end

      it "tells nobody that the position went away" do
        expect {
          delete organization_bill_position_path(position)
        }.not_to have_enqueued_job(NotifyOrganizationFollowersJob)
      end
    end

    # @lat: [[organization-position-removal#Removal is recorded where the other decisions are]]
    it "records the removal in the activity log next to the other decisions" do
      delete organization_bill_position_path(position)

      entry = PipelineActivityLogEntry.where(event_type: "org_position_decision").order(:id).last
      expect(entry).to be_present
      expect(entry.payload["decision"]).to eq("removed")
      expect(entry.payload["org_name"]).to eq(organization.name)
      expect(entry.payload["bill_id"]).to eq(bill.id)
    end

    it "answers 404 for an id that names no position" do
      delete organization_bill_position_path(id: position.id + 10_000)

      expect(response).to have_http_status(:not_found)
    end

    it "is a no-op rather than a failure on a position already removed" do
      position.update!(active: false)

      expect {
        delete organization_bill_position_path(position)
      }.not_to raise_error

      expect(response).to have_http_status(:found)
      expect(position.reload.active).to be(false)
    end

    # @lat: [[organization-position-removal#Removal is recorded where the other decisions are]]
    it "records one decision however many times the removal is fired" do
      delete organization_bill_position_path(position)

      expect {
        delete organization_bill_position_path(position)
      }.not_to change {
        PipelineActivityLogEntry.where(event_type: "org_position_decision").count
      }
    end

    # @lat: [[bill-creator-shell#The Bill Creator shell#Why tab URLs retain legacy compatibility]]
    it "returns the operator to the tab the removal was fired from using the canonical key" do
      delete organization_bill_position_path(position, bill_creator_tab: "creator")

      expect(response.location).to include("/admin/bill_creator/#{bill.id}/creator")
    end

    it "still reads a legacy tab_key on the removal request" do
      delete organization_bill_position_path(position, tab_key: "creator")

      expect(response.location).to include("/admin/bill_creator/#{bill.id}/creator")
    end

    it "leaves the organization off the page the operator lands back on" do
      delete organization_bill_position_path(position, tab_key: "summary")
      get summary_bill_creator_path(bill)

      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props[:bill][:organizations].pluck(:name)).not_to include(organization.name)
    end
  end

  describe "DELETE /organization_bill_positions/:id for a bearer request" do
    let!(:position) do
      create(:organization_bill_position,
        bill: bill, organization: organization, active: true,
        support: "FOR", summary: "We support this bill.")
    end
    let(:bearer_json_headers) do
      lambda do |user|
        authenticate_as(user).merge("Accept" => "application/json")
      end
    end

    # @lat: [[mobile-bill-creator#Sections#The organizations section]]
    it "deactivates the position and answers 200 JSON with no redirect" do
      delete organization_bill_position_path(position), headers: bearer_json_headers.call(admin)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(response.headers["Location"]).to be_nil
      expect(position.reload.active).to be(false)
    end

    it "refuses a non-admin with a forbidden JSON error" do
      non_admin = create(:user)
      create(:user_legislator, user: non_admin)
      non_admin.complete!

      delete organization_bill_position_path(position), headers: bearer_json_headers.call(non_admin)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
      expect(position.reload.active).to be(true)
    end
  end

  include_examples "requires sway admin",
    verb: :post,
    path: "/organization_bill_positions",
    params: {
      organization_bill_position: {
        positions: []
      }
    }
end
