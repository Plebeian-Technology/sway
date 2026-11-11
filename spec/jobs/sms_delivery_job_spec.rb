# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmsDeliveryJob, type: :job do
  describe "#perform" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TWILIO_ACCOUNT_SID").and_return("AC123")
      allow(ENV).to receive(:[]).with("TWILIO_AUTH_TOKEN").and_return("token")
      allow(ENV).to receive(:[]).with("TWILIO_FROM_PHONE").and_return(
        "9876543210"
      )
      # @lat: [[seeded-development-users#Outbound SMS is refused outside production]]
      stub_app_config(:ops, allow_nonproduction_sms: true)
    end

    describe "the production-only guard" do
      # @lat: [[seeded-development-users#Outbound SMS is refused outside production]]
      it "does not build a Twilio client outside production while the switch is off" do
        with_app_config(:ops, allow_nonproduction_sms: false) do
          expect(Twilio::REST::Client).not_to receive(:new)

          log_output = StringIO.new
          original_logger = Rails.logger
          Rails.logger = ActiveSupport::Logger.new(log_output)
          begin
            described_class.new.perform(to: "3335550001", body: "Hello")
          ensure
            Rails.logger = original_logger
          end

          expect(log_output.string).to include("outbound SMS is production-only")
        end
      end

      it "sends outside production once the switch is on" do
        client = instance_double(Twilio::REST::Client)
        messages =
          instance_double(Twilio::REST::Api::V2010::AccountContext::MessageList)
        allow(Twilio::REST::Client).to receive(:new).and_return(client)
        allow(client).to receive(:messages).and_return(messages)

        expect(messages).to receive(:create).with(
          from: "9876543210",
          to: "3335550001",
          body: "Hello Reply STOP to opt out."
        )

        with_app_config(:ops, allow_nonproduction_sms: true) do
          described_class.new.perform(to: "3335550001", body: "Hello")
        end
      end

      it "sends in production even with the switch off" do
        allow(Rails).to receive(:env).and_return(
          ActiveSupport::StringInquirer.new("production")
        )
        client = instance_double(Twilio::REST::Client)
        messages =
          instance_double(Twilio::REST::Api::V2010::AccountContext::MessageList)
        allow(Twilio::REST::Client).to receive(:new).and_return(client)
        allow(client).to receive(:messages).and_return(messages)

        expect(messages).to receive(:create)

        with_app_config(:ops, allow_nonproduction_sms: false) do
          described_class.new.perform(to: "3335550001", body: "Hello")
        end
      end
    end

    it "sends SMS via Twilio" do
      client = instance_double(Twilio::REST::Client)
      messages =
        instance_double(Twilio::REST::Api::V2010::AccountContext::MessageList)

      allow(Twilio::REST::Client).to receive(:new).and_return(client)
      allow(client).to receive(:messages).and_return(messages)

      expect(messages).to receive(:create).with(
        from: "9876543210",
        to: "1234567890",
        body: "Hello Reply STOP to opt out."
      )

      described_class.new.perform(to: "1234567890", body: "Hello")
    end

    # @lat: [[sms-notification-service-design#Why the opt-out suffix is appended once in SmsDeliveryJob]]
    describe "opt-out suffix" do
      it "appends the opt-out suffix to every body sent to Twilio" do
        client = instance_double(Twilio::REST::Client)
        messages =
          instance_double(Twilio::REST::Api::V2010::AccountContext::MessageList)
        allow(Twilio::REST::Client).to receive(:new).and_return(client)
        allow(client).to receive(:messages).and_return(messages)

        expect(messages).to receive(:create).with(
          from: "9876543210",
          to: "1234567890",
          body: "New Bill of the Month in Test City: Test Bill. Check it out on Sway! Reply STOP to opt out."
        )

        described_class.new.perform(
          to: "1234567890",
          body: "New Bill of the Month in Test City: Test Bill. Check it out on Sway!"
        )
      end

      it "does not double-append the suffix when the body already ends with it" do
        client = instance_double(Twilio::REST::Client)
        messages =
          instance_double(Twilio::REST::Api::V2010::AccountContext::MessageList)
        allow(Twilio::REST::Client).to receive(:new).and_return(client)
        allow(client).to receive(:messages).and_return(messages)

        expect(messages).to receive(:create).with(
          from: "9876543210",
          to: "1234567890",
          body: "Hello world Reply STOP to opt out."
        )

        described_class.new.perform(
          to: "1234567890",
          body: "Hello world Reply STOP to opt out."
        )
      end
    end

    # @lat: [[twilio-error-phone-redaction#Why Twilio error handling redacts recipient identifiers]]
    describe "PII log hygiene" do
      it "keeps the full recipient phone and SMS body out of the logs on success" do
        client = instance_double(Twilio::REST::Client)
        messages =
          instance_double(Twilio::REST::Api::V2010::AccountContext::MessageList)
        allow(Twilio::REST::Client).to receive(:new).and_return(client)
        allow(client).to receive(:messages).and_return(messages)
        allow(messages).to receive(:create)

        log_output = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log_output)
        begin
          described_class.perform_now(to: "+14105551234", body: "Your secret code is 998877")
        ensure
          Rails.logger = original_logger
        end

        logs = log_output.string
        expect(logs).to include("job_start")
        expect(logs).not_to include("+14105551234")
        expect(logs).not_to include("998877")
        expect(logs).not_to include("Your secret code")
      end

      # @lat: [[twilio-error-phone-redaction#Why SmsDeliveryJob raises DeliveryError outside the rescue block]]
      it "retries on a Twilio error instead of swallowing it, keeping the phone out of the logs" do
        client = instance_double(Twilio::REST::Client)
        messages =
          instance_double(Twilio::REST::Api::V2010::AccountContext::MessageList)
        allow(Twilio::REST::Client).to receive(:new).and_return(client)
        allow(client).to receive(:messages).and_return(messages)

        # A realistic Twilio error 21211, whose message contains the recipient's
        # phone number — the exact string SwayLogging.log_exception would leak.
        # The earlier version of this test used "boom", which has no phone number
        # in it, so it passed whether or not the fix was there.
        response = double(
          "Twilio::Response",
          status_code: 400,
          body: {"code" => 21211, "message" => "The 'To' number +14105551234 is not a valid phone number."}
        )
        # The type signatures Twilio ships get RestError.new's argument count
        # wrong for (message, response), so the type check is skipped here, the
        # way this repo skips it for untyped test helpers.
        rest_error = Twilio::REST::RestError.new("Unable to create record", response) # steep:ignore
        allow(messages).to receive(:create).and_raise(rest_error)

        log_output = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log_output)
        begin
          # retry_on puts the job back on the queue instead of swallowing the
          # error. The old begin/rescue returned quietly with nothing queued.
          expect {
            described_class.perform_now(to: "+14105551234", body: "unused secret body")
          }.to have_enqueued_job(SmsDeliveryJob)
        ensure
          Rails.logger = original_logger
        end

        logs = log_output.string
        # The phone number sits inside the RestError message. Without the rescue
        # that cleans it, it would land in job_fail's log_exception output.
        expect(logs).not_to include("+14105551234")
        expect(logs).not_to include("unused secret body")
        # The bare numeric code is safe to log, and seeing it proves the rescue ran.
        expect(logs).to include("code=21211")
      end
    end

    describe "sanitized DeliveryError + early-return guards" do
      # @lat: [[twilio-error-phone-redaction#Why SmsDeliveryJob raises DeliveryError outside the rescue block]]
      it "raises a DeliveryError with no cause and no phone in its message" do
        client = instance_double(Twilio::REST::Client)
        messages =
          instance_double(Twilio::REST::Api::V2010::AccountContext::MessageList)
        allow(Twilio::REST::Client).to receive(:new).and_return(client)
        allow(client).to receive(:messages).and_return(messages)

        response = double(
          "Twilio::Response",
          status_code: 400,
          body: {"code" => 21211, "message" => "The 'To' number +14105551234 is not a valid phone number."}
        )
        rest_error = Twilio::REST::RestError.new("Unable to create record", response) # steep:ignore
        allow(messages).to receive(:create).and_raise(rest_error)

        expect {
          described_class.new.perform(to: "+14105551234", body: "unused secret body")
        }.to raise_error(described_class::DeliveryError) do |error|
          # With no cause chain, log_exception cannot leak the phone number from
          # the RestError.
          expect(error.cause).to be_nil
          expect(error.message).not_to include("+14105551234")
          # Only the harmless numeric code and status come along.
          expect(error.message).to include("code=21211")
        end
      end

      it "does not contact Twilio when the recipient or body is blank" do
        expect(Twilio::REST::Client).not_to receive(:new)

        described_class.new.perform(to: "", body: "Hello")
        described_class.new.perform(to: "1234567890", body: "")
      end

      it "warns and returns without contacting Twilio when TWILIO_FROM_PHONE is unset" do
        allow(ENV).to receive(:[]).with("TWILIO_FROM_PHONE").and_return(nil)
        expect(Twilio::REST::Client).not_to receive(:new)

        log_output = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log_output)
        begin
          described_class.new.perform(to: "1234567890", body: "Hello")
        ensure
          Rails.logger = original_logger
        end

        expect(log_output.string).to include("TWILIO_FROM_PHONE is not set")
      end
    end
  end
end
