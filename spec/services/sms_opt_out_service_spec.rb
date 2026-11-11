# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmsOptOutService do
  describe "#call" do
    it "disables sms_notifications_enabled for a STOP body" do
      user = create(:user, phone: "4105551234")
      user.update_column(:sms_notifications_enabled, true)

      described_class.new(from: "+14105551234", body: "STOP").call

      expect(user.reload.sms_notifications_enabled).to be(false)
    end

    it "enables sms_notifications_enabled for a START body" do
      user = create(:user, phone: "4105551234")

      described_class.new(from: "+14105551234", body: "START").call

      expect(user.reload.sms_notifications_enabled).to be(true)
    end

    %w[STOP STOPALL UNSUBSCRIBE CANCEL END QUIT OPTOUT REVOKE].each do |keyword|
      it "recognizes #{keyword} as an opt-out keyword" do
        user = create(:user, phone: "4105551234")
        user.update_column(:sms_notifications_enabled, true)

        described_class.new(from: "+14105551234", body: keyword).call

        expect(user.reload.sms_notifications_enabled).to be(false)
      end
    end

    %w[START YES UNSTOP SUBSCRIBE].each do |keyword|
      it "recognizes #{keyword} as an opt-in keyword" do
        user = create(:user, phone: "4105551234")

        described_class.new(from: "+14105551234", body: keyword).call

        expect(user.reload.sms_notifications_enabled).to be(true)
      end
    end

    it "matches case-insensitively with surrounding whitespace" do
      user = create(:user, phone: "4105551234")
      user.update_column(:sms_notifications_enabled, true)

      described_class.new(from: "+14105551234", body: " stop ").call

      expect(user.reload.sms_notifications_enabled).to be(false)
    end

    it "leaves the flag untouched for a body that isn't a recognized keyword" do
      user = create(:user, phone: "4105551234")
      user.update_column(:sms_notifications_enabled, true)

      described_class.new(from: "+14105551234", body: "hello").call

      expect(user.reload.sms_notifications_enabled).to be(true)
    end

    # @lat: [[inbound-sms#Inbound SMS#The flag write skips validations]]
    it "bumps updated_at so the row's modification time reflects the opt-out" do
      user = create(:user, phone: "4105551234")
      user.update_columns(sms_notifications_enabled: true, updated_at: 3.days.ago)
      before = user.reload.updated_at

      described_class.new(from: "+14105551234", body: "STOP").call

      expect(user.reload.updated_at).to be > before
    end

    it "resolves an E.164 From to the user whose stored phone is the normalized 10-digit form" do
      user = create(:user, phone: "2025551234")
      user.update_column(:sms_notifications_enabled, true)

      described_class.new(from: "+12025551234", body: "STOP").call

      expect(user.reload.sms_notifications_enabled).to be(false)
    end

    # @lat: [[inbound-sms#Inbound SMS#An unrecognised sender is not an error]]
    it "does nothing and raises nothing for an unknown phone number" do
      expect {
        described_class.new(from: "+19995551234", body: "STOP").call
      }.not_to raise_error
    end
  end

  # @lat: [[inbound-sms#Inbound SMS#The keyword sets are pinned to the registered campaign]]
  describe "the registered A2P campaign's keywords" do
    registered_opt_out = %w[OPTOUT CANCEL END QUIT UNSUBSCRIBE REVOKE STOP STOPALL]
    registered_opt_in = %w[SUBSCRIBE START]

    it "are all recognised as opt-out words" do
      expect(described_class::STOP_KEYWORDS).to include(*registered_opt_out)
    end

    it "are all recognised as opt-in words" do
      expect(described_class::START_KEYWORDS).to include(*registered_opt_in)
    end
  end
end
