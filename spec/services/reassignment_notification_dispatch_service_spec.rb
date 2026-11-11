# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReassignmentNotificationDispatchService do
  include ActiveJob::TestHelper

  let(:user) { create(:user, email: "voter@example.com").tap { |u| u.update_column(:is_email_verified, true) } }
  let(:district) { create(:district) }
  let(:legislator) { create(:legislator, district:) }

  before do
    clear_enqueued_jobs
    ActionMailer::Base.deliveries.clear
  end

  describe "#call" do
    it "does nothing when there are no pending reassignments" do
      expect {
        described_class.new(user.id).call
      }.not_to change { ActionMailer::Base.deliveries.count }
    end

    context "when user has legislator_updates disabled (default)" do
      let!(:reassignment) do
        RepresentativeReassignment.create!(
          user: user,
          district: district,
          legislator: legislator,
          reassignment_type: :vacancy_filled
        )
      end

      it "claims and marks notified_at but delivers no email or push" do
        pref = user.notification_preferences.find_or_create_by!(key: "legislator_updates")
        pref.update!(enabled: false)

        expect {
          described_class.new(user.id).call
        }.not_to change { ActionMailer::Base.deliveries.count }

        expect(reassignment.reload.notified_at).to be_present
        expect(enqueued_jobs).to be_empty
      end
    end

    context "when user has opted into legislator_updates" do
      let!(:reassignment) do
        RepresentativeReassignment.create!(
          user: user,
          district: district,
          legislator: legislator,
          reassignment_type: :vacancy_filled
        )
      end

      before do
        pref = user.notification_preferences.find_or_create_by!(key: "legislator_updates")
        pref.update!(enabled: true)
      end

      it "enqueues reassignment digest email and marks records as notified" do
        expect {
          described_class.new(user.id).call
        }.to have_enqueued_mail(RepresentativeReassignmentMailer, :reassignment_digest)

        expect(reassignment.reload.notified_at).to be_present
      end

      it "is idempotent on consecutive calls (claims only once)" do
        described_class.new(user.id).call

        clear_enqueued_jobs
        expect {
          described_class.new(user.id).call
        }.not_to have_enqueued_mail(RepresentativeReassignmentMailer, :reassignment_digest)
      end

      it "dispatches native push when active devices exist" do
        device = create(:user_device, user: user, push_token: "token123")

        expect {
          described_class.new(user.id).call
        }.to have_enqueued_job(SendNativePushJob).with(
          device.id,
          hash_including(kind: "legislator_updates")
        )
      end

      it "resets notified_at to nil and re-raises if delivery raises" do
        allow(RepresentativeReassignmentMailer).to receive(:reassignment_digest).and_raise(StandardError, "enqueue failed")

        expect {
          described_class.new(user.id).call
        }.to raise_error(StandardError, "enqueue failed")

        expect(reassignment.reload.notified_at).to be_nil
      end
    end
  end
end
